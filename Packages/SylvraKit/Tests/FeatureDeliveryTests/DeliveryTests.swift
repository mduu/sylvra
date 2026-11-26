import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureDelivery

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let id = PullRequestID(owner: "acme", repository: "billing", number: 7)

private func job(_ name: String, _ state: StageState, environment: String? = nil) -> StagePlanner.Job {
    StagePlanner.Job(
        job: DeliveryJob(
            id: name, name: name, state: state, startedAt: now, finishedAt: state.isFinished ? now + 60 : nil),
        environment: environment)
}

struct StagePlannerTests {
    @Test func aWorkflowBecomesABuildStageAndOneStagePerEnvironment() {
        let run = StagePlanner.Run(
            id: "r1", name: "CI/CD", event: "push", createdAt: now,
            jobs: [
                job("compile", .succeeded), job("test", .succeeded), job("deploy dev", .succeeded, environment: "dev"),
                job("smoke dev", .succeeded, environment: "dev"), job("deploy prod", .running, environment: "prod"),
            ])
        let stages = StagePlanner.stages(runs: [run])
        #expect(stages.map(\.name) == ["CI/CD", "dev", "prod"])
        #expect(stages.map(\.kind) == [.build, .environment, .environment])
        #expect(stages.map(\.state) == [.succeeded, .succeeded, .running])
        #expect(stages[1].jobs.map(\.name) == ["deploy dev", "smoke dev"])
        // A running stage has no end yet.
        #expect(stages[2].finishedAt == nil && stages[1].finishedAt == now + 60)
    }

    @Test func thePullRequestsOwnChecksAreNoDelivery() {
        let checks = StagePlanner.Run(
            id: "r0", name: "PR checks", event: "pull_request", jobs: [job("lint", .succeeded)])
        #expect(StagePlanner.stages(runs: [checks]).isEmpty)
    }

    @Test func anEnvironmentWaitingForApprovalIsAStageBeforeItsJobsExist() throws {
        let run = StagePlanner.Run(
            id: "r1", name: "Deploy", event: "push", jobs: [job("deploy test", .succeeded, environment: "test")],
            pending: [.init(environment: "prod", environmentID: "E1", viewerCanApprove: true)])
        let stages = StagePlanner.stages(runs: [run])
        let prod = try #require(stages.last)
        #expect(stages.map(\.name) == ["test", "prod"])
        #expect(prod.state == .needsApproval)
        #expect(prod.approval == .init(workflowRunID: "r1", environmentID: "E1", viewerCanApprove: true))
    }

    @Test func chainedWorkflowsFollowInTheOrderTheyStarted() {
        let deploy = StagePlanner.Run(
            id: "r2", name: "Deploy", event: "workflow_run", createdAt: now + 600,
            jobs: [job("deploy", .waiting, environment: "prod")])
        let build = StagePlanner.Run(
            id: "r1", name: "Build", event: "push", createdAt: now, jobs: [job("build", .succeeded)])
        #expect(StagePlanner.stages(runs: [deploy, build]).map(\.name) == ["Build", "prod"])
    }

    @Test func workflowsThatOnlyBuildAndCheckAreOneStage() {
        let lint = StagePlanner.Run(
            id: "r1", name: "Lint", event: "push", createdAt: now, jobs: [job("lint", .succeeded)])
        let tests = StagePlanner.Run(
            id: "r2", name: "Tests", event: "push", createdAt: now + 1, jobs: [job("unit", .running)])
        let nightly = StagePlanner.Run(id: "r3", name: "Nightly", event: "schedule", jobs: [job("scan", .failed)])
        let stages = StagePlanner.stages(runs: [tests, lint, nightly])
        #expect(stages.map(\.name) == ["Build & checks"])
        #expect(stages.first?.jobs.map(\.name) == ["Lint · lint", "Tests · unit"])
        // What merely ran on the same commit doesn't count.
        #expect(stages.first?.state == .running)
    }

    @Test func deploymentsOfOtherSystemsAddTheirEnvironments() {
        let run = StagePlanner.Run(
            id: "r1", name: "Build", event: "push", createdAt: now,
            jobs: [job("build", .succeeded), job("deploy", .succeeded, environment: "dev")])
        let stages = StagePlanner.stages(
            runs: [run],
            deployments: [
                // The job's own deployment: no second stage.
                .init(environment: "dev", state: .succeeded, createdAt: now),
                .init(environment: "production", state: .failed, createdAt: now + 100),
                .init(environment: "production", state: .running, createdAt: now + 900),
            ])
        #expect(stages.map(\.name) == ["Build", "dev", "production"])
        // The latest deployment to an environment counts.
        #expect(stages.last?.state == .running && stages.last?.workflow == nil)
    }

    @Test func aFailureDecidesAStagesState() {
        #expect(DeliveryStage.state(of: [.succeeded, .failed, .running]) == .failed)
        #expect(DeliveryStage.state(of: [.succeeded, .waiting]) == .running)
        #expect(DeliveryStage.state(of: [.waiting, .waiting]) == .waiting)
        #expect(DeliveryStage.state(of: [.skipped, .skipped]) == .skipped)
        #expect(DeliveryStage.state(of: [.succeeded, .skipped]) == .succeeded)
    }
}

struct DeliveryStateTests {
    static func delivery(_ states: [(String, StageState)], mergedAt: Date = now) -> Delivery {
        Delivery(
            pullRequest: id, title: "Add export", mergeCommitSHA: "abc", mergedAt: mergedAt,
            stages: states.map {
                DeliveryStage(
                    id: $0.0, name: $0.0, kind: $0.0 == "build" ? .build : .environment, workflow: "CI", state: $0.1)
            })
    }

    @Test func tellsWhereTheDeliveryStands() {
        let running = Self.delivery([("build", .succeeded), ("dev", .running), ("prod", .waiting)])
        #expect(running.headline() == "dev is running" && running.currentStage?.name == "dev")
        #expect(!running.isFinished())
        let failed = Self.delivery([("build", .succeeded), ("dev", .failed), ("prod", .skipped)])
        #expect(failed.headline() == "dev failed" && failed.isFinished() && failed.overallState() == .failed)
        let done = Self.delivery([("build", .succeeded), ("dev", .succeeded), ("prod", .succeeded)])
        #expect(done.headline() == "Deployed to prod" && done.currentStage?.name == "prod")
    }

    /// Nothing starting after a merge is a finding, but only after a while.
    @Test func noStagesMeansWaitingAtFirstThenNothingStarted() {
        let delivery = Self.delivery([])
        #expect(!delivery.isFinished(at: now + 60))
        #expect(delivery.headline(at: now + 60) == "Waiting for the deployment to start")
        #expect(delivery.isFinished(at: now + 600))
        #expect(delivery.headline(at: now + 600) == "No deployment started")
    }

    @Test func eventsNameTheStagesThatChanged() {
        let before = Self.delivery([("build", .running), ("dev", .waiting), ("prod", .waiting)])
        let after = Self.delivery([("build", .succeeded), ("dev", .failed), ("prod", .needsApproval)])
        #expect(
            DeliveryEvent.changes(from: before, to: after).map(\.kind)
                == [.stageSucceeded("build"), .stageFailed("dev"), .needsApproval("prod")])
        // The first load is the starting point, not news.
        #expect(DeliveryEvent.changes(from: nil, to: after).isEmpty)
        #expect(DeliveryEvent.changes(from: after, to: after).isEmpty)
    }
}

/// Returns the deliveries it was given, one per load (the last one again after that).
private final class ScriptedLoader: DeliveryLoading, @unchecked Sendable {
    var script: [Delivery?]
    var approved: [DeliveryStage.Approval] = []
    var refusal: String?

    init(_ script: [Delivery?]) { self.script = script }

    func loadDelivery(for id: PullRequestID) async throws -> Delivery? {
        script.count > 1 ? script.removeFirst() : script.first.flatMap { $0 }
    }

    func approve(_ approval: DeliveryStage.Approval) async throws {
        if let refusal { throw GitHubError.graphQL([refusal]) }
        approved.append(approval)
    }

    func loadLog(jobID: Int, in id: PullRequestID) async throws -> String { "log of \(jobID)" }
}

@MainActor
struct DeliveryModelTests {
    @Test func aFollowedDeliveryReportsItsStagesAndEndsWhenThrough() async {
        let loader = ScriptedLoader([
            DeliveryStateTests.delivery([("build", .running), ("prod", .waiting)]),
            DeliveryStateTests.delivery([("build", .succeeded), ("prod", .running)]),
            DeliveryStateTests.delivery([("build", .succeeded), ("prod", .succeeded)]),
        ])
        let model = DeliveryModel(loader: loader)
        var events: [DeliveryEvent.Kind] = []
        model.onEvent = { events.append($0.kind) }
        model.follow(id)
        await model.refreshFollowed(now: now)
        #expect(events.isEmpty)
        await model.refreshFollowed(now: now + 30)
        await model.refreshFollowed(now: now + 60)
        #expect(events == [.stageSucceeded("build"), .stageSucceeded("prod")])
        // Still followed for a while: a workflow started by the finished one may follow.
        #expect(model.isFollowing(id))
        await model.refreshFollowed(now: now + 60 + DeliveryModel.settleTime)
        #expect(!model.isFollowing(id))
        #expect(events.last == .complete)
    }

    @Test func aFailedDeliveryEndsAtOnceWithoutASecondMessage() async {
        let loader = ScriptedLoader([
            DeliveryStateTests.delivery([("build", .running)]), DeliveryStateTests.delivery([("build", .failed)]),
        ])
        let model = DeliveryModel(loader: loader)
        var events: [DeliveryEvent.Kind] = []
        model.onEvent = { events.append($0.kind) }
        model.follow(id)
        await model.refreshFollowed(now: now)
        await model.refreshFollowed(now: now + 30)
        #expect(events == [.stageFailed("build")])
        #expect(!model.isFollowing(id))
    }

    @Test func nothingStartingIsReportedOnce() async {
        let model = DeliveryModel(loader: ScriptedLoader([DeliveryStateTests.delivery([])]))
        var events: [DeliveryEvent.Kind] = []
        model.onEvent = { events.append($0.kind) }
        model.follow(id)
        await model.refreshFollowed(now: now + 60)
        #expect(events.isEmpty && model.isFollowing(id))
        await model.refreshFollowed(now: now + 600)
        #expect(events == [.nothingStarted] && !model.isFollowing(id))
    }

    /// Auto-merge: followed before GitHub merged.
    @Test func aPullRequestNotMergedYetStaysFollowed() async {
        let model = DeliveryModel(loader: ScriptedLoader([nil]))
        model.follow(id)
        await model.refreshFollowed(now: now)
        #expect(model.isFollowing(id) && model.delivery(for: id) == nil)
    }

    @Test func followedDeliveriesSurviveARestart() {
        let name = "delivery-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removePersistentDomain(forName: name) }
        DeliveryModel(loader: ScriptedLoader([nil]), defaults: defaults).follow(id)
        #expect(DeliveryModel(loader: ScriptedLoader([nil]), defaults: defaults).followed == [id])
    }

    @Test func approvingGoesToGitHubAndARefusalIsShown() async throws {
        let waiting = DeliveryStage(
            id: "prod", name: "prod", kind: .environment, workflow: "CI", state: .needsApproval,
            approval: .init(workflowRunID: "r1", environmentID: "E1", viewerCanApprove: true))
        var delivery = DeliveryStateTests.delivery([])
        delivery.stages = [waiting]
        let loader = ScriptedLoader([delivery])
        let model = DeliveryModel(loader: loader)
        await model.load(id)
        let stage = try #require(model.shownStage(for: id))
        await model.approve(stage, of: id)
        #expect(loader.approved == [.init(workflowRunID: "r1", environmentID: "E1", viewerCanApprove: true)])

        loader.refusal = "Not a reviewer"
        await model.approve(stage, of: id)
        #expect(model.approvalError?.contains("Not a reviewer") == true)
        #expect(loader.approved.count == 1)
    }
}

struct GitHubDeliveryMappingTests {
    static let json = """
        {"repository": {"pullRequest": {
          "title": "Add export", "state": "MERGED", "mergedAt": "2026-11-20T10:00:00Z",
          "mergeCommit": {"oid": "abc123",
            "checkSuites": {"nodes": [
              {"workflowRun": null, "checkRuns": {"nodes": [{"id": "x", "name": "other app", "status": "COMPLETED",
                "conclusion": "SUCCESS", "startedAt": null, "completedAt": null, "detailsUrl": null}]}},
              {"workflowRun": {"id": "WR1", "url": "https://github.com/o/r/actions/runs/1", "event": "push",
                  "createdAt": "2026-11-20T10:00:05Z", "workflow": {"name": "CI/CD"},
                  "pendingDeploymentRequests": {"nodes": [
                    {"currentUserCanApprove": true, "environment": {"id": "E_prod", "name": "prod"}}]}},
               "checkRuns": {"nodes": [
                 {"id": "c1", "name": "build", "status": "COMPLETED", "conclusion": "SUCCESS",
                  "startedAt": "2026-11-20T10:00:10Z", "completedAt": "2026-11-20T10:03:10Z", "detailsUrl": null,
                  "deployment": null, "pendingDeploymentRequest": null, "steps": {"nodes": []},
                  "annotations": {"nodes": []}},
                 {"id": "c2", "name": "deploy test", "status": "COMPLETED", "conclusion": "FAILURE",
                  "startedAt": "2026-11-20T10:03:20Z", "completedAt": "2026-11-20T10:04:00Z", "detailsUrl": null,
                  "deployment": {"environment": "test"}, "pendingDeploymentRequest": null,
                  "steps": {"nodes": [{"name": "Migrate", "number": 3, "conclusion": "FAILURE"},
                                      {"name": "Checkout", "number": 1, "conclusion": "SUCCESS"}]},
                  "annotations": {"nodes": [{"message": "exit code 1", "annotationLevel": "FAILURE"},
                                            {"message": "node 16 is deprecated", "annotationLevel": "WARNING"}]}}
               ]}}
            ]},
            "deployments": {"nodes": [
              {"environment": "test", "state": "FAILURE", "createdAt": "2026-11-20T10:03:20Z", "latestStatus": null}
            ]}
          }
        }}}
        """

    @Test func mapsRunsJobsAndPendingApprovals() throws {
        let response = try GitHubJSON.decoder.decode(DeliveryResponse.self, from: Data(Self.json.utf8))
        let delivery = try #require(response.repository?.pullRequest?.delivery(for: id))
        #expect(delivery.mergeCommitSHA == "abc123")
        #expect(delivery.stages.map(\.name) == ["CI/CD", "test", "prod"])
        #expect(delivery.stages.map(\.state) == [.succeeded, .failed, .needsApproval])
        let failed = try #require(delivery.stages[1].jobs.first)
        #expect(failed.failedSteps == ["Migrate"] && failed.errors == ["exit code 1"])
        #expect(delivery.stages[2].approval?.environmentID == "E_prod")
        #expect(delivery.stages[0].duration == 180)
    }

    @Test func anOpenPullRequestHasNoDelivery() throws {
        let json = Self.json.replacingOccurrences(of: #""state": "MERGED""#, with: #""state": "OPEN""#)
        let response = try GitHubJSON.decoder.decode(DeliveryResponse.self, from: Data(json.utf8))
        #expect(response.repository?.pullRequest?.delivery(for: id) == nil)
    }
}
