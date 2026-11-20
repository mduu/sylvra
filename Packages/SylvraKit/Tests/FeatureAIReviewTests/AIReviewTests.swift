import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureAIReview

private func file(_ path: String, lines: ClosedRange<Int>, noise: Bool = false) -> ReviewableFile {
    ReviewableFile(
        path: path, patch: "@@ -1 +1 @@\n+x", changedNewLines: Set(lines),
        visibleNewLines: Set(lines.lowerBound - 3...lines.upperBound + 3),
        isNoise: noise)
}

struct ShardPlannerTests {
    @Test func smallPRsUseOneShard() {
        let shards = ShardPlanner.plan(
            [file("A/a.swift", lines: 1...10), file("B/b.swift", lines: 1...10)], maxShards: 3, threshold: 400)
        #expect(shards.count == 1)
    }

    @Test func largePRsAreSplitByFolderAndExcludeNoise() {
        let files = [
            file("Sources/Billing/A.swift", lines: 1...300), file("Tests/BillingTests/ATests.swift", lines: 1...100),
            file("Sources/Export/B.swift", lines: 1...250), file("Sources/Auth/C.swift", lines: 1...200),
            file("Package.resolved", lines: 1...50, noise: true),
        ]
        let shards = ShardPlanner.plan(files, maxShards: 3, threshold: 400)
        #expect(shards.count == 3)
        #expect(!shards.flatMap(\.files).contains { $0.isNoise })
        let billing = shards.first { $0.files.contains { $0.path.hasPrefix("Sources/Billing") } }
        #expect(billing?.files.contains { $0.path.hasPrefix("Tests/BillingTests") } == true)
    }
}

struct ReviewMergerTests {
    let opus = AgentSource(provider: "Claude Code", model: "opus", effort: "high")
    let fable = AgentSource(provider: "Claude Code", model: "fable", effort: "high")

    private func output(_ findings: String) throws -> AgentReviewOutput {
        try JSONDecoder().decode(
            AgentReviewOutput.self, from: Data(#"{"summary":"s","findings":\#(findings),"patterns":[]}"#.utf8))
    }

    @Test func mergesReadingOrdersAndDropsUnknownFiles() throws {
        let decode = { (json: String) in
            try JSONDecoder().decode(
                AgentReviewOutput.self,
                from: Data(#"{"summary":"s","findings":[],"patterns":[],"readingOrder":\#(json)}"#.utf8))
        }
        let first = try decode(#"[{"path":"b.swift","reason":"core","risky":true},{"path":"x.swift","reason":"?"}]"#)
        let second = try decode(#"[{"path":"a.swift","reason":"tests"},{"path":"b.swift","reason":"again"}]"#)
        let result = ReviewMerger.merge(
            [(first, opus), (second, fable)], files: [file("a.swift", lines: 1...2), file("b.swift", lines: 1...2)])
        #expect(result.readingOrder.map(\.path) == ["b.swift", "a.swift"])
        #expect(result.readingOrder.first?.isRisky == true)
    }

    @Test func decodesCachedResultsWithoutReadingOrder() throws {
        let json = #"{"summary":"s","findings":[],"patterns":[],"history":[]}"#
        let result = try JSONDecoder().decode(ReviewResult.self, from: Data(json.utf8))
        #expect(result.readingOrder.isEmpty)
    }

    @Test func mergesDuplicatesAcrossModels() throws {
        let first = try output(
            #"[{"path":"a.swift","startLine":10,"endLine":10,"severity":"major","category":"bug","title":"Rounding drifts invoice totals","rationale":"r","confidence":0.9}]"#
        )
        let second = try output(
            #"[{"path":"a.swift","startLine":11,"endLine":11,"severity":"major","category":"bug","title":"Invoice totals drift because of rounding","rationale":"r","confidence":0.8}]"#
        )
        let result = ReviewMerger.merge([(first, opus), (second, fable)], files: [file("a.swift", lines: 8...12)])
        #expect(result.findings.count == 1)
        #expect(result.findings.first?.sources == [opus, fable])
    }

    @Test func reanchorsOrMarksUnanchored() throws {
        let raw = try output(
            #"[{"path":"a.swift","startLine":40,"endLine":40,"severity":"minor","category":"style","title":"x","rationale":"r","confidence":0.5},{"path":"a.swift","startLine":17,"endLine":17,"severity":"minor","category":"design","title":"y","rationale":"r","confidence":0.5}]"#
        )
        let result = ReviewMerger.merge([(raw, opus)], files: [file("a.swift", lines: 8...12)])
        let far = try #require(result.findings.first { $0.title == "x" })
        let near = try #require(result.findings.first { $0.title == "y" })
        #expect(!far.isAnchored)
        #expect(near.isAnchored && near.startLine == 15)
    }

    @Test func sortsBySeverity() throws {
        let raw = try output(
            #"[{"path":"a.swift","startLine":9,"endLine":9,"severity":"nit","category":"style","title":"nit","rationale":"","confidence":0.1},{"path":"a.swift","startLine":10,"endLine":10,"severity":"critical","category":"security","title":"crit","rationale":"","confidence":0.9}]"#
        )
        let result = ReviewMerger.merge([(raw, opus)], files: [file("a.swift", lines: 8...12)])
        #expect(result.findings.map(\.title) == ["crit", "nit"])
    }
}

struct ClaudeCodeProviderTests {
    @Test func decodesStructuredOutput() throws {
        let stdout =
            #"{"type":"result","result":"ignored","structured_output":{"summary":"ok","findings":[],"patterns":[{"name":"MVVM","verdict":"followed","rationale":"r"}]}}"#
        let output = try ClaudeCodeProvider.decode(
            ProcessResult(exitCode: 0, standardOutput: stdout, standardError: ""))
        #expect(output.summary == "ok")
        #expect(output.patterns?.first?.verdict == .followed)
    }

    @Test func reportsFailures() {
        #expect(throws: AgentError.self) {
            _ = try ClaudeCodeProvider.decode(
                ProcessResult(exitCode: 1, standardOutput: "", standardError: "Not logged in"))
        }
    }

    @Test func argumentsAreReadOnlyAndStructured() {
        let request = ReviewRequest(
            pullRequestTitle: "t", pullRequestBody: "b", shard: .init(name: "All", files: []), repositoryContext: [],
            history: [], model: "fable", effort: "high", language: "German", workingDirectory: nil)
        let arguments = ClaudeCodeProvider.arguments(for: request)
        #expect(arguments.contains("--json-schema"))
        #expect(arguments.contains("fable"))
        #expect(!arguments.contains("Bash") && !arguments.contains("Edit") && !arguments.contains("Write"))
        #expect(request.prompt.contains("in German"))
    }

    @Test func schemaIsValidJSON() throws {
        _ = try JSONSerialization.jsonObject(with: Data(ReviewRequest.outputSchema.utf8))
    }
}

struct RepoContextDiscoveryTests {
    @Test func followsImportsAndSpecFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sylvra-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "specs"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "@AGENTS.md\n".write(to: root.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
        try "Read specs/architecture.md and [UX](specs/ux.md).".write(
            to: root.appending(path: "AGENTS.md"), atomically: true, encoding: .utf8)
        try "Slices.".write(to: root.appending(path: "specs/architecture.md"), atomically: true, encoding: .utf8)
        try "Calm.".write(to: root.appending(path: "specs/ux.md"), atomically: true, encoding: .utf8)

        let paths = RepoContextDiscovery().documents(in: root).map(\.path)
        #expect(paths.contains("AGENTS.md") && paths.contains("CLAUDE.md"))
        #expect(paths.contains("specs/architecture.md") && paths.contains("specs/ux.md"))
        #expect(Set(paths).count == paths.count)
    }
}

@MainActor
struct AIReviewModelTests {
    let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    private func model() -> AIReviewModel {
        AIReviewModel(
            engine: ReviewEngine(provider: DemoAgentProvider(delay: .zero)),
            files: { _ in [file("Sources/Billing/InvoiceService.swift", lines: 8...10)] },
            workspace: { _ in nil },
            defaults: UserDefaults(suiteName: "sylvra-ai-\(UUID().uuidString)")!)
    }

    @Test func runsReviewAndKeepsResultPerPR() async {
        let model = model()
        await model.run(id, title: "Add invoice export", body: "")
        #expect(model.runState == .done)
        #expect(model.progress.allSatisfy { $0.state == .done })
        #expect(model.visibleFindings(for: id).first?.severity == .major)
        #expect(model.results[id]?.patterns.count == 3)
    }

    @Test func perPROverrideAndDismiss() async throws {
        let model = model()
        model.toggleModel("fable", for: id)
        #expect(model.settings(for: id).models == ["opus", "fable"])
        #expect(model.defaultSettings.models == ["opus"])
        await model.run(id, title: "t", body: "")
        let first = try #require(model.visibleFindings(for: id).first)
        model.dismiss(first)
        #expect(!model.visibleFindings(for: id).contains(first))
    }

    /// Regression: clicking the highlight of the already selected finding didn't bring it back into view.
    @Test func showingAFindingAlwaysRequestsTheInspector() async throws {
        let model = model()
        await model.run(id, title: "t", body: "")
        let first = try #require(model.visibleFindings(for: id).first)
        model.tab = .patterns
        model.showFinding(first.id)
        let request = model.findingRequest
        #expect(model.selectedFindingID == first.id)
        #expect(model.tab == .findings)
        model.showFinding(first.id)
        #expect(model.findingRequest != request)
    }
}

@MainActor
struct AIChatModelTests {
    let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    @Test func keepsConversationAndSessionPerPR() async {
        let chat = AIChatModel(
            provider: DemoAgentProvider(delay: .zero), settings: { _ in ReviewSettings(agentLanguage: "German") },
            prContext: { _ in "PR context" }, workspace: { _ in nil })
        chat.draft = "Was ändert sich?"
        await chat.send(for: id)
        #expect(chat.draft.isEmpty)
        #expect(chat.messages(for: id).map(\.role) == [.user, .assistant])
        #expect(chat.messages(for: PullRequestID(owner: "o", repository: "r", number: 1)).isEmpty)
        chat.reset(id)
        #expect(chat.messages(for: id).isEmpty)
    }

    @Test func discussesSelectedCodePrivately() async throws {
        let chat = AIChatModel(
            provider: DemoAgentProvider(delay: .zero), settings: { _ in ReviewSettings() },
            prContext: { _ in "PR context" }, workspace: { _ in nil })
        let location = CodeLocation(path: "Sources/Billing/InvoiceService.swift", line: 9, side: .right, startLine: 8)
        await chat.discuss(.init(location: location, text: "sum + x"), question: "  ", for: id)
        let messages = chat.messages(for: id)
        #expect(messages.first?.location == location)
        #expect(messages.first?.text.isEmpty == false)
        #expect(chat.discussedLocations(for: id) == [location])
        let answer = try #require(messages.last)
        #expect(chat.location(answering: answer, in: id) == location)
        #expect(chat.context.code?.label == "InvoiceService.swift:8–9")
        #expect(!chat.isDiscussed(CodeLocation(path: location.path, line: 12, side: .right), in: id))
        #expect(chat.isDiscussed(CodeLocation(path: location.path, line: 9, side: .right), in: id))
        #expect(!chat.isDiscussed(CodeLocation(path: location.path, line: 9, side: .left), in: id))
        // Added after the first lookup: the cache follows new messages.
        let later = CodeLocation(path: location.path, line: 12, side: .right)
        await chat.discuss(.init(location: later, text: "x"), question: "?", for: id)
        #expect(chat.isDiscussed(later, in: id))
    }

    @Test func chatModelAndEffortDefaultToReviewSettingsAndCanChange() async throws {
        let provider = RecordingChatProvider()
        let chat = AIChatModel(
            provider: provider, settings: { _ in ReviewSettings(models: ["sonnet", "opus"], effort: "medium") },
            prContext: { _ in "PR context" }, workspace: { _ in nil })
        #expect(chat.options(for: id) == .init(model: "sonnet", effort: "medium"))
        chat.setModel("fable", for: id)
        chat.setEffort("max", for: id)
        await chat.send("Hi", for: id)
        let request = try #require(await provider.requests.last)
        #expect(request.model == "fable" && request.effort == "max")
        let other = PullRequestID(owner: "o", repository: "r", number: 1)
        #expect(chat.options(for: other) == .init(model: "sonnet", effort: "medium"))
    }

    @Test func startsNewChatsAndKeepsEarlierOnes() async throws {
        let provider = RecordingChatProvider()
        let chat = AIChatModel(
            provider: provider, settings: { _ in ReviewSettings() }, prContext: { _ in "PR context" },
            workspace: { _ in nil })
        chat.ask(aboutFinding: "Rounding drift", for: id)
        await chat.send("Why?", for: id)
        chat.ask(aboutFinding: "Rounding drift", for: id)
        #expect(chat.chatList(for: id).count == 1)

        chat.ask(aboutFinding: "CSV escaping", for: id)
        #expect(chat.chatList(for: id).count == 2)
        #expect(chat.messages(for: id).isEmpty)
        #expect(chat.context.finding == "CSV escaping")
        await chat.send("And this?", for: id)
        // A fresh chat starts a fresh agent session (with the PR context again).
        let requests = await provider.requests
        #expect(requests.last?.sessionID == nil)
        #expect(requests.last?.message.hasPrefix("PR context") == true)

        let first = try #require(chat.chatList(for: id).first)
        #expect(first.title == "Why?")
        chat.selectChat(first.id, for: id)
        #expect(chat.messages(for: id).map(\.text) == ["Why?", "ok"])
        await chat.send("More", for: id)
        #expect(await provider.requests.last?.sessionID == "s")
    }

    @Test func newChatReusesAnEmptyOne() {
        let chat = AIChatModel(
            provider: DemoAgentProvider(delay: .zero), settings: { _ in ReviewSettings() },
            prContext: { _ in "" }, workspace: { _ in nil })
        chat.newChat(for: id)
        chat.newChat(for: id)
        #expect(chat.chatList(for: id).count == 1)
    }

    @Test func chatPassesEffort() throws {
        let request = ChatRequest(
            message: "hi", sessionID: nil, model: "opus", effort: "low", language: "German", workingDirectory: nil)
        let arguments = ClaudeCodeProvider.chatArguments(for: request)
        let index = try #require(arguments.firstIndex(of: "--effort"))
        #expect(arguments[index + 1] == "low")
    }

    @Test func chatAsksForShortAnswersInTheLanguage() throws {
        let request = ChatRequest(
            message: "hi", sessionID: nil, model: "opus", language: "German", workingDirectory: nil)
        let arguments = ClaudeCodeProvider.chatArguments(for: request)
        let index = try #require(arguments.firstIndex(of: "--append-system-prompt"))
        let prompt = arguments[index + 1]
        #expect(prompt.contains("Answer in German"))
        #expect(prompt.contains("lead with the answer"))
        #expect(prompt.contains("1–4 sentences"))
        #expect(prompt.contains("path:line"))
    }

    @Test func findsCodeReferences() {
        let refs = AIChatModel.codeReferences(in: "See Sources/Billing/InvoiceService.swift:9 and Package.swift:3.")
        #expect(refs.map(\.path) == ["Sources/Billing/InvoiceService.swift", "Package.swift"])
        #expect(refs.map(\.line) == [9, 3])
    }

    @Test func chatResumesSessions() {
        let request = ChatRequest(
            message: "hi", sessionID: "abc", model: "opus", language: "German", workingDirectory: nil)
        let arguments = ClaudeCodeProvider.chatArguments(for: request)
        #expect(arguments.contains("--resume") && arguments.contains("abc"))
        #expect(!arguments.contains("--no-session-persistence"))
    }
}

@MainActor
struct AIReviewPersistenceTests {
    @Test func resultsSurviveRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "sylvra-ai-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = PullRequestID(owner: "acme", repository: "billing", number: 7)
        func makeModel() -> AIReviewModel {
            AIReviewModel(
                engine: ReviewEngine(provider: DemoAgentProvider(delay: .zero)),
                files: { _ in [file("Sources/Billing/InvoiceService.swift", lines: 8...10)] }, workspace: { _ in nil },
                defaults: UserDefaults(suiteName: "sylvra-ai-\(UUID().uuidString)")!,
                cache: JSONCache(directory: directory))
        }
        await makeModel().run(id, title: "t", body: "")
        await JSONCache.waitForWrites()
        #expect(makeModel().results[id]?.findings.isEmpty == false)
        #expect(PullRequestID("acme/billing#7") == id)
    }
}

struct CommentRewriterTests {
    @Test func promptAsksForShortFactualToneAndKeepsSuggestions() {
        let prompt = CommentRewriter.prompt(for: "Round once.", language: "German", style: .improve)
        #expect(prompt.contains("in German"))
        #expect(prompt.contains("at most two sentences"))
        #expect(prompt.contains("factual and neutral"))
        #expect(prompt.contains("```suggestion block exactly"))
    }

    @Test func eachStyleHasItsOwnTask() {
        let shorten = CommentRewriter.prompt(for: "x", language: "English", style: .shorten)
        let translate = CommentRewriter.prompt(for: "x", language: "German", style: .translate)
        #expect(shorten.contains("short and crisp"))
        #expect(translate.contains("Translate"))
        #expect(!translate.contains("Improve"))
    }

    @Test func guardDetectsDroppedSuggestions() {
        let original = "Round once.\n\n```suggestion\nlet x = 1\n```"
        #expect(
            SuggestionGuard.keepsSuggestions(
                original: original, rewritten: "Bitte einmal runden.\n\n```suggestion\nlet x = 1\n```"))
        #expect(!SuggestionGuard.keepsSuggestions(original: original, rewritten: "Bitte einmal runden."))
    }
}

/// Remembers chat requests and answers briefly.
private actor RecordingChatProvider: AgentProvider {
    nonisolated let name = "recording"
    private(set) var requests: [ChatRequest] = []

    func detectVersion() async -> String? { "1" }

    func review(_ request: ReviewRequest) async throws -> AgentReviewOutput {
        throw AgentError.failed("not used")
    }

    func chat(_ request: ChatRequest) async throws -> ChatReply {
        requests.append(request)
        return ChatReply(text: "ok", sessionID: "s")
    }
}
