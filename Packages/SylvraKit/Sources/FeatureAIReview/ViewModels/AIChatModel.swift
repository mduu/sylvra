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
    }

    /// Context chips shown above the input; removable by the reviewer.
    public struct Context: Equatable, Sendable {
        public var file: String?
        public var finding: String?
    }

    public typealias ContextProvider = @MainActor @Sendable (PullRequestID) -> String

    public private(set) var conversations: [PullRequestID: [Message]] = [:]
    public private(set) var isSending = false
    public var draft = ""
    public var context = Context()

    private var sessions: [PullRequestID: String] = [:]
    private let provider: any AgentProvider
    private let settings: @MainActor () -> ReviewSettings
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
        provider: any AgentProvider, settings: @escaping @MainActor () -> ReviewSettings,
        prContext: @escaping ContextProvider, workspace: @escaping AIReviewModel.WorkspaceProvider
    ) {
        self.provider = provider
        self.settings = settings
        self.prContext = prContext
        self.workspace = workspace
    }

    public func messages(for id: PullRequestID?) -> [Message] {
        id.flatMap { conversations[$0] } ?? []
    }

    public func send(_ text: String? = nil, for id: PullRequestID) async {
        let question = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        if text == nil { draft = "" }
        conversations[id, default: []].append(Message(role: .user, text: question))
        isSending = true
        defer { isSending = false }

        let current = settings()
        var prompt = question
        if let file = context.file { prompt += "\n\n(Current file: \(file))" }
        if let finding = context.finding { prompt += "\n\n(Selected finding: \(finding))" }
        if sessions[id] == nil { prompt = prContext(id) + "\n\n---\n\n" + prompt }
        let directory = try? await workspace(id)
        do {
            let reply = try await provider.chat(
                ChatRequest(
                    message: prompt, sessionID: sessions[id], model: current.models.first ?? "opus",
                    language: current.agentLanguage, workingDirectory: directory))
            sessions[id] = reply.sessionID
            conversations[id, default: []].append(Message(role: .assistant, text: reply.text))
        } catch {
            conversations[id, default: []].append(Message(role: .error, text: String(describing: error)))
        }
    }

    public func reset(_ id: PullRequestID) {
        conversations[id] = nil
        sessions[id] = nil
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
