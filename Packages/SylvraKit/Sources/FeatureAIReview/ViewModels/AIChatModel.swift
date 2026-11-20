import Foundation
import Observation
import SylvraCore

/// One chat conversation per pull request (see specs/ux.md §10).
@MainActor
@Observable
public final class AIChatModel {
    public struct Message: Identifiable, Equatable, Sendable {
        public enum Role: Sendable { case user, assistant, error }
        public let id = UUID()
        public let role: Role
        public let text: String
        /// Code the question was about (Discuss on a diff selection).
        public var location: CodeLocation?
    }

    /// Code selected in the diff to discuss privately with the agent.
    public struct CodeSnippet: Equatable, Sendable {
        public let location: CodeLocation
        public let text: String

        public init(location: CodeLocation, text: String) {
            self.location = location
            self.text = text
        }

        /// `InvoiceService.swift:8–9`
        public var label: String {
            let file = (location.path as NSString).lastPathComponent
            let lines = location.lines
            return lines.count > 1 ? "\(file):\(lines.lowerBound)–\(lines.upperBound)" : "\(file):\(location.line)"
        }
    }

    /// Context chips shown above the input; removable by the reviewer.
    public struct Context: Equatable, Sendable {
        public var file: String?
        public var finding: String?
        public var code: CodeSnippet?
    }

    /// One conversation with the agent; a PR can have several (one per finding or question, say).
    public struct Chat: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public var messages: [Message] = []
        /// The finding the chat was started for ("Ask in chat").
        public var finding: String?
        var sessionID: String?

        /// The first question, shortened (menus).
        public var title: String {
            guard let question = messages.first(where: { $0.role == .user })?.text else {
                return finding ?? String(localized: "New chat")
            }
            let line = question.split(separator: "\n").first.map(String.init) ?? question
            return line.count > 48 ? line.prefix(47) + "…" : line
        }
    }

    /// Model and effort for the chat of one PR; changeable between questions.
    public struct Options: Equatable, Sendable {
        public var model: String
        public var effort: String
    }

    public typealias ContextProvider = @MainActor @Sendable (PullRequestID) -> String

    /// All chats per PR, oldest first.
    public private(set) var chats: [PullRequestID: [Chat]] = [:]
    /// Discussed lines per pull request, rebuilt when messages are added (asked per visible diff row).
    @ObservationIgnored private var discussedCache: [PullRequestID: (messages: Int, lines: Set<DiscussedLine>)] = [:]
    private var activeChatIDs: [PullRequestID: Chat.ID] = [:]
    public private(set) var isSending = false
    public var draft = ""
    public var context = Context()

    /// Choices made in the chat; without one the PR's review settings apply.
    public private(set) var chosenOptions: [PullRequestID: Options] = [:]
    private let provider: any AgentProvider
    private let settings: @MainActor (PullRequestID) -> ReviewSettings
    private let prContext: ContextProvider
    private let workspace: AIReviewModel.WorkspaceProvider

    public static let quickPrompts = [
        String(localized: "Explain this change"),
        String(localized: "Is this tested?"),
        String(localized: "What could break?"),
        String(localized: "Which patterns does this follow?"),
    ]

    /// - Parameter prContext: PR title, description, findings… sent with the first message.
    public init(
        provider: any AgentProvider, settings: @escaping @MainActor (PullRequestID) -> ReviewSettings,
        prContext: @escaping ContextProvider, workspace: @escaping AIReviewModel.WorkspaceProvider
    ) {
        self.provider = provider
        self.settings = settings
        self.prContext = prContext
        self.workspace = workspace
    }

    /// The model and effort the next question uses.
    public func options(for id: PullRequestID) -> Options {
        if let chosen = chosenOptions[id] { return chosen }
        let current = settings(id)
        return Options(model: current.models.first ?? "opus", effort: current.effort)
    }

    public func setModel(_ model: String, for id: PullRequestID) {
        var chosen = options(for: id)
        chosen.model = model
        chosenOptions[id] = chosen
    }

    public func setEffort(_ effort: String, for id: PullRequestID) {
        var chosen = options(for: id)
        chosen.effort = effort
        chosenOptions[id] = chosen
    }

    public func messages(for id: PullRequestID?) -> [Message] {
        id.flatMap(activeChat(for:))?.messages ?? []
    }

    /// The chat shown and continued by the next question (`nil` before the first one).
    public func activeChat(for id: PullRequestID) -> Chat? {
        let list = chats[id] ?? []
        return list.first { $0.id == activeChatIDs[id] } ?? list.last
    }

    public func chatList(for id: PullRequestID?) -> [Chat] {
        id.flatMap { chats[$0] } ?? []
    }

    /// Starts a fresh conversation (the agent forgets the earlier one); the earlier chats stay selectable.
    public func newChat(for id: PullRequestID, finding: String? = nil) {
        context.code = nil
        if var current = activeChat(for: id), current.messages.isEmpty {
            current.finding = finding
            update(current, in: id)
            return
        }
        let chat = Chat(finding: finding)
        chats[id, default: []].append(chat)
        activeChatIDs[id] = chat.id
    }

    public func selectChat(_ chatID: Chat.ID, for id: PullRequestID) {
        guard chats[id]?.contains(where: { $0.id == chatID }) == true else { return }
        activeChatIDs[id] = chatID
    }

    /// "Ask in chat" on a finding: its own chat, unless the current one is about it or still empty.
    public func ask(aboutFinding title: String, for id: PullRequestID) {
        context.finding = title
        if activeChat(for: id)?.finding != title { newChat(for: id, finding: title) }
    }

    private func update(_ chat: Chat, in id: PullRequestID) {
        guard let index = chats[id]?.firstIndex(where: { $0.id == chat.id }) else { return }
        chats[id]?[index] = chat
    }

    private func append(_ message: Message, to chatID: Chat.ID, in id: PullRequestID, session: String? = nil) {
        guard let index = chats[id]?.firstIndex(where: { $0.id == chatID }) else { return }
        chats[id]?[index].messages.append(message)
        if let session { chats[id]?[index].sessionID = session }
    }

    public func send(_ text: String? = nil, for id: PullRequestID) async {
        let question = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        if text == nil { draft = "" }
        if activeChat(for: id) == nil {
            // The first chat of the PR; keeps the context (code under discussion) unlike "New chat".
            let first = Chat(finding: context.finding)
            chats[id] = [first]
            activeChatIDs[id] = first.id
        }
        guard let chat = activeChat(for: id) else { return }
        append(Message(role: .user, text: question, location: context.code?.location), to: chat.id, in: id)
        isSending = true
        defer { isSending = false }

        let current = settings(id)
        var prompt = question
        if let file = context.file { prompt += "\n\n(Current file: \(file))" }
        if let finding = context.finding { prompt += "\n\n(Selected finding: \(finding))" }
        if let code = context.code {
            let side = code.location.side == .left ? "old version" : "new version"
            prompt += "\n\n(About this code, \(code.label), \(side):\n```\n\(code.text)\n```)"
        }
        if chat.sessionID == nil { prompt = prContext(id) + "\n\n---\n\n" + prompt }
        let directory = try? await workspace(id)
        let options = options(for: id)
        do {
            let reply = try await provider.chat(
                ChatRequest(
                    message: prompt, sessionID: chat.sessionID, model: options.model, effort: options.effort,
                    language: current.agentLanguage, workingDirectory: directory))
            // The reply goes to the chat it answers, even if the reviewer switched chats meanwhile.
            append(Message(role: .assistant, text: reply.text), to: chat.id, in: id, session: reply.sessionID)
        } catch {
            append(Message(role: .error, text: String(describing: error)), to: chat.id, in: id)
        }
    }

    /// Starts a private discussion about selected code; nothing is posted to GitHub.
    public func discuss(_ snippet: CodeSnippet, question: String, for id: PullRequestID) async {
        // Other code gets its own chat; the same code continues the current one.
        if let current = activeChat(for: id), !current.messages.isEmpty,
            !current.messages.contains(where: { $0.location == snippet.location })
        {
            newChat(for: id)
        }
        context.code = snippet
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        await send(trimmed.isEmpty ? String(localized: "Explain this code and what could go wrong.") : trimmed, for: id)
    }

    /// Bumped to put the cursor into the chat's input (e.g. after *Ask AI* on selected code).
    public private(set) var inputFocusRequest = 0

    /// *Ask AI* on code selected in the diff: the code becomes the chat's context and the reviewer writes the
    /// question; nothing is sent yet. Other code than the current chat's gets a new chat.
    public func prepareDiscussion(_ snippet: CodeSnippet, for id: PullRequestID) {
        if let current = activeChat(for: id), !current.messages.isEmpty,
            !current.messages.contains(where: { $0.location == snippet.location })
        {
            newChat(for: id)
        }
        context.code = snippet
        inputFocusRequest += 1
    }

    /// Locations discussed in a PR's chat (for markers in the diff).
    public func discussedLocations(for id: PullRequestID?) -> [CodeLocation] {
        var seen: [CodeLocation] = []
        let all = chatList(for: id).flatMap(\.messages)
        for location in all.compactMap(\.location) where !seen.contains(location) {
            seen.append(location)
        }
        return seen
    }

    /// Chats of the pull request that have messages (the Chat tab's badge).
    public func chatCount(for id: PullRequestID?) -> Int {
        chatList(for: id).count { !$0.messages.isEmpty }
    }

    /// Whether a chat of the pull request asked about this line (path, side and last line).
    public func isDiscussed(_ location: CodeLocation, in id: PullRequestID?) -> Bool {
        guard let id else { return false }
        let chats = chatList(for: id)
        let count = chats.reduce(0) { $0 + $1.messages.count }
        if let cached = discussedCache[id], cached.messages == count {
            return cached.lines.contains(DiscussedLine(location))
        }
        let lines = Set(chats.flatMap(\.messages).compactMap(\.location).map(DiscussedLine.init))
        discussedCache[id] = (count, lines)
        return lines.contains(DiscussedLine(location))
    }

    /// The code location an answer is about: the latest question with code before it.
    public func location(answering message: Message, in id: PullRequestID?) -> CodeLocation? {
        let messages = messages(for: id)
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return nil }
        return messages[..<index].last { $0.location != nil }?.location
    }

    public func reset(_ id: PullRequestID) {
        chats[id] = nil
        activeChatIDs[id] = nil
    }

    /// A `path:line` reference inside an answer.
    public struct CodeReference: Sendable {
        public let range: Range<String.Index>
        public let path: String
        public let line: Int
    }

    /// Finds `path:line` references in a reply so the UI can link them (e.g. `Sources/A.swift:12`).
    public nonisolated static func codeReferences(in text: String) -> [CodeReference] {
        text.matches(of: /([A-Za-z0-9_\-.\/]+\.[A-Za-z0-9]+):(\d+)/).compactMap { match in
            guard let line = Int(match.2) else { return nil }
            return CodeReference(range: match.range, path: String(match.1), line: line)
        }
    }
}

/// A line as `AIChatModel.isDiscussed` compares it (a range's start line doesn't matter).
struct DiscussedLine: Hashable {
    let path: String
    let side: CodeLocation.Side
    let line: Int

    init(_ location: CodeLocation) {
        path = location.path
        side = location.side
        line = location.line
    }
}
