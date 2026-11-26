import Foundation
import SylvraCore
import Testing

@testable import FeatureDelivery

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let id = PullRequestID(owner: "acme", repository: "billing", number: 7)

private func delivery(_ states: [(String, StageState)]) -> Delivery {
    Delivery(
        pullRequest: id, title: "Fix VAT rounding", mergeCommitSHA: "abc123", mergedAt: now,
        stages: states.map {
            DeliveryStage(
                id: $0.0, name: $0.0, kind: $0.0 == "build" ? .build : .environment, workflow: "CI", state: $0.1)
        })
}

/// Records which stages were checked and answers with a fixed verdict.
private final class RecordingVerifier: DeliveryVerifying, @unchecked Sendable {
    var requests: [VerificationRequest] = []
    var failure: String?

    func verify(_ request: VerificationRequest) async throws -> StageVerification {
        if let failure { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
        requests.append(request)
        return StageVerification(
            stageID: request.stage.id, stageName: request.stage.name, verdict: .healthy, summary: "Fine.",
            isSecondLook: request.isSecondLook)
    }
}

private final class ScriptedDeliveries: DeliveryLoading, @unchecked Sendable {
    var script: [Delivery]
    init(_ script: [Delivery]) { self.script = script }
    func loadDelivery(for id: PullRequestID) async throws -> Delivery? {
        script.count > 1 ? script.removeFirst() : script.first
    }
    func approve(_ approval: DeliveryStage.Approval) async throws {}

    func loadLog(jobID: Int, in id: PullRequestID) async throws -> String { "log of \(jobID)" }
}

struct VerificationPromptTests {
    private func request(_ stage: DeliveryStage, notes: String = "", second: Bool = false) -> VerificationRequest {
        VerificationRequest(
            pullRequest: id, title: "Fix VAT rounding", body: "Rounds per invoice.",
            delivery: delivery([("build", .succeeded), ("prod", stage.state)]), stage: stage, monitoringNotes: notes,
            isSecondLook: second)
    }

    @Test func aDeployedStageIsCheckedForErrorsAndTheChangesEffect() {
        let stage = DeliveryStage(id: "prod", name: "prod", kind: .environment, workflow: "CI", state: .succeeded)
        let prompt = VerificationPrompt.prompt(for: request(stage, notes: "Datadog service:billing-api"), now: now)
        #expect(prompt.contains("acme/billing #7 — Fix VAT rounding"))
        #expect(prompt.contains("Merge commit: abc123"))
        #expect(prompt.contains("Rounds per invoice."))
        #expect(prompt.contains("Datadog service:billing-api"))
        #expect(prompt.contains("new errors or more errors since the deployment"))
        #expect(prompt.contains("AGENTS.md / CLAUDE.md"))
        // The agent only reads, and says what it could not check instead of guessing.
        #expect(prompt.contains("You only read") && prompt.contains("notChecked"))
        #expect(!prompt.contains("second look"))
        #expect(VerificationPrompt.prompt(for: request(stage, second: true), now: now).contains("second look"))
    }

    @Test func aFailedStageIsAskedForItsCause() {
        let stage = DeliveryStage(
            id: "test", name: "test", kind: .environment, workflow: "CI", state: .failed,
            jobs: [
                DeliveryJob(
                    id: "j", name: "migrate", state: .failed, failedSteps: ["Run migrations"], errors: ["exit 1"])
            ])
        let prompt = VerificationPrompt.prompt(for: request(stage), now: now)
        #expect(prompt.contains("The stage failed. Find out why"))
        #expect(prompt.contains("failed steps: Run migrations") && prompt.contains("reported: exit 1"))
    }

    @Test func theAgentMayOnlyRunReadingCommands() {
        #expect(VerificationPrompt.allowedTools.allSatisfy { $0.hasPrefix("Bash(gh ") || $0.hasPrefix("Bash(git ") })
        let writing = ["merge", "push", "api", "rerun", "delete", "edit", "create", "close", "commit"]
        #expect(!VerificationPrompt.allowedTools.contains { rule in writing.contains { rule.contains(" \($0)") } })
    }

    @Test func decodesTheAgentsAnswer() throws {
        let json = """
            {"verdict": "problems", "summary": " Error rate doubled. ", "intent": "Fixes rounding.",
             "checks": [{"title": "New errors", "outcome": "problem", "finding": "0.2 % → 0.5 %",
                         "evidence": "Datadog logs status:error, 30 min before/after"}],
             "notChecked": ["UI"]}
            """
        let stage = DeliveryStage(id: "prod", name: "prod", kind: .environment, workflow: "CI", state: .succeeded)
        let result = try VerificationPrompt.decode(Data(json.utf8), for: request(stage), now: now)
        #expect(result.verdict == .problems && result.summary == "Error rate doubled.")
        #expect(result.checks.first?.outcome == .problem && result.notChecked == ["UI"])
        #expect(result.stageID == "prod" && result.checkedAt == now)
    }
}

@MainActor
struct VerificationModelTests {
    @Test func checkingAStageKeepsTheResultAndPassesTheNotes() async throws {
        let verifier = RecordingVerifier()
        let name = "verification-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = DeliveryModel(
            loader: ScriptedDeliveries([delivery([("build", .succeeded), ("prod", .succeeded)])]), verifier: verifier,
            defaults: defaults)
        model.pullRequestInfo = { _ in .init(title: "Fix VAT rounding", body: "Rounds per invoice.") }
        model.setMonitoringNotes(" Datadog service:billing-api ", for: id)
        await model.load(id)
        await model.verify("prod", of: id)
        let stage = try #require(model.delivery(for: id)?.stages.last)
        #expect(model.verification(of: stage, in: id)?.verdict == .healthy)
        #expect(verifier.requests.first?.monitoringNotes == "Datadog service:billing-api")
        #expect(verifier.requests.first?.body == "Rounds per invoice.")
        #expect(!model.isVerifying(stage, in: id))
    }

    @Test func aRunningCheckCanBeStopped() async throws {
        final class SlowVerifier: DeliveryVerifying, @unchecked Sendable {
            func verify(_ request: VerificationRequest) async throws -> StageVerification {
                try await Task.sleep(for: .seconds(30))
                return StageVerification(stageID: "prod", stageName: "prod", verdict: .healthy, summary: "late")
            }
        }
        let model = DeliveryModel(
            loader: ScriptedDeliveries([delivery([("prod", .succeeded)])]), verifier: SlowVerifier())
        await model.load(id)
        let stage = try #require(model.delivery(for: id)?.stages.first)
        model.startVerifying("prod", of: id)
        for _ in 0..<50 where !model.isVerifying(stage, in: id) { await Task.yield() }
        #expect(model.isVerifying(stage, in: id))
        model.stopVerifying("prod", of: id)
        for _ in 0..<200 where model.isVerifying(stage, in: id) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.isVerifying(stage, in: id))
        #expect(model.verification(of: stage, in: id) == nil && model.verificationError(of: stage, in: id) == nil)
    }

    @Test func aFailedCheckShowsItsReason() async throws {
        let verifier = RecordingVerifier()
        verifier.failure = "Claude Code is not installed"
        let model = DeliveryModel(loader: ScriptedDeliveries([delivery([("prod", .succeeded)])]), verifier: verifier)
        await model.load(id)
        await model.verify("prod", of: id)
        let stage = try #require(model.delivery(for: id)?.stages.first)
        #expect(model.verificationError(of: stage, in: id) == "Claude Code is not installed")
        #expect(model.verification(of: stage, in: id) == nil)
    }

    /// Followed deliveries with the option on: a deployed stage is checked after the settling time, production
    /// once more later, and the delivery stays followed until then.
    @Test func followedDeliveriesAreCheckedWhenTheirStagesSettle() async {
        let verifier = RecordingVerifier()
        let model = DeliveryModel(
            loader: ScriptedDeliveries([
                delivery([("build", .running), ("prod", .waiting)]),
                delivery([("build", .succeeded), ("prod", .succeeded)]),
            ]), verifier: verifier)
        model.verifiesAutomatically = true
        var events: [DeliveryEvent.Kind] = []
        model.onEvent = { events.append($0.kind) }
        model.follow(id)
        await model.refreshFollowed(now: now)
        await model.refreshFollowed(now: now + 30)
        // Deployed just now: not checked yet, and a passed build is never checked.
        #expect(verifier.requests.isEmpty)
        await model.refreshFollowed(now: now + 30 + DeliveryModel.verificationDelay)
        #expect(verifier.requests.map(\.stage.name) == ["prod"])
        #expect(events.contains(.verified("prod", .healthy)))
        // Still followed: production gets a second look.
        await model.refreshFollowed(now: now + 30 + DeliveryModel.verificationDelay + DeliveryModel.settleTime)
        #expect(model.isFollowing(id))
        await model.refreshFollowed(now: now + 30 + DeliveryModel.secondLookDelay)
        #expect(verifier.requests.map(\.isSecondLook) == [false, true])
        await model.refreshFollowed(now: now + 60 + DeliveryModel.secondLookDelay)
        #expect(!model.isFollowing(id))
    }

    @Test func aFailedStageIsCheckedAtOnceAndNothingWithoutTheOption() async {
        let script = [delivery([("build", .running)]), delivery([("build", .failed)])]
        let verifier = RecordingVerifier()
        let model = DeliveryModel(loader: ScriptedDeliveries(script), verifier: verifier)
        model.verifiesAutomatically = true
        model.follow(id)
        await model.refreshFollowed(now: now)
        await model.refreshFollowed(now: now + 30)
        #expect(verifier.requests.map(\.stage.name) == ["build"])

        let quiet = RecordingVerifier()
        let manual = DeliveryModel(loader: ScriptedDeliveries(script), verifier: quiet)
        manual.follow(id)
        await manual.refreshFollowed(now: now)
        await manual.refreshFollowed(now: now + 30)
        #expect(quiet.requests.isEmpty)
    }

    @Test func productionIsTheEnvironmentNamedLikeItElseTheLast() {
        #expect(
            delivery([("build", .succeeded), ("production", .succeeded), ("smoke", .succeeded)]).productionStage?.name
                == "production")
        #expect(
            delivery([("build", .succeeded), ("dev", .succeeded), ("stage", .succeeded)]).productionStage?.name
                == "stage")
        #expect(delivery([("build", .succeeded)]).productionStage == nil)
    }

    /// The AI check is a band of its own: selecting it shows the stage's checks, selecting the stage its jobs.
    @Test func theAICheckIsItsOwnPartOfTheGraph() async throws {
        let stages = delivery([("build", .succeeded), ("dev", .succeeded), ("prod", .running)])
        let model = DeliveryModel(loader: ScriptedDeliveries([stages]), verifier: RecordingVerifier())
        await model.load(id)
        // Deployed environments can be checked; a running one and a passed build not.
        #expect(model.aiColumns(for: id).map(\.stage.name) == ["dev"])
        await model.verify("dev", of: id)
        model.selectAICheck("dev", of: id)
        #expect(model.isShowingAICheck(for: id) && model.shownStage(for: id)?.name == "dev")
        // The recording verifier answers without checks: nothing to show yet but the column.
        #expect(model.shownItem(for: id) == nil)
        #expect(model.aiColumns(for: id).first?.result?.verdict == .healthy)
        model.selectStage("dev", of: id)
        #expect(!model.isShowingAICheck(for: id))
    }

    /// Tools a check was refused can be allowed once, for every repository: the next checks get them.
    @Test func allowedToolsGoWithEveryCheck() async throws {
        let name = "allowed-tools-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let verifier = RecordingVerifier()
        let model = DeliveryModel(
            loader: ScriptedDeliveries([delivery([("prod", .succeeded)])]), verifier: verifier, defaults: defaults)
        await model.load(id)
        var refused = StageVerification(stageID: "prod", stageName: "prod", verdict: .unchecked, summary: "")
        refused.deniedTools = ["mcp__datadog__analyze_datadog_logs", "mcp__datadog__load_datadog_skill"]
        #expect(model.stillDenied(in: refused).count == 2)

        model.allowForChecks(["mcp__datadog__analyze_datadog_logs"])
        #expect(model.stillDenied(in: refused) == ["mcp__datadog__load_datadog_skill"])
        await model.verify("prod", of: id)
        #expect(verifier.requests.last?.allowedTools == ["mcp__datadog__analyze_datadog_logs"])

        // Kept across launches, and can be taken back.
        let restarted = DeliveryModel(loader: ScriptedDeliveries([]), defaults: defaults)
        #expect(restarted.allowedCheckTools == ["mcp__datadog__analyze_datadog_logs"])
        restarted.stopAllowingForChecks("mcp__datadog__analyze_datadog_logs")
        #expect(restarted.allowedCheckTools.isEmpty)
    }

    /// Results saved before the newer fields existed still load.
    @Test func olderSavedResultsStillDecode() throws {
        let json =
            #"{"stageID":"prod","stageName":"prod","verdict":"healthy","summary":"ok","intent":"","checks":[],"notChecked":[],"checkedAt":0,"isSecondLook":false}"#
        let result = try JSONDecoder().decode(StageVerification.self, from: Data(json.utf8))
        #expect(result.activity.isEmpty && result.deniedTools.isEmpty && result.verdict == .healthy)
    }
}
