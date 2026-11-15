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
