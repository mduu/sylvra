import CoreGraphics
import Foundation
import SylvraCore
import Testing

@testable import FeatureDelivery

private func job(_ name: String, _ state: StageState = .succeeded, needs: [String] = []) -> DeliveryJob {
    DeliveryJob(id: name, name: name, state: state, needs: needs)
}

struct WorkflowFileTests {
    static let yaml = """
        name: CI/CD
        on:
          push:
            branches: [main]   # deliver main
        jobs:
          compile:
            name: Compile
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v4
              - run: make
          unit:
            name: "Unit tests"
            needs: compile
            strategy:
              matrix:
                os: [ubuntu, macos]
          lint:
            needs: [compile]
          deploy-dev:
            name: Deploy dev
            needs:
              - unit
              - lint
            environment: dev
        """

    @Test func readsJobsNamesAndNeeds() {
        let file = WorkflowFile(yaml: Self.yaml)
        #expect(file.jobs.map(\.key) == ["compile", "unit", "lint", "deploy-dev"])
        #expect(file.jobs.map(\.name) == ["Compile", "Unit tests", nil, "Deploy dev"])
        #expect(file.jobs.map(\.needs) == [[], ["compile"], ["compile"], ["unit", "lint"]])
    }

    @Test func findsTheJobOfACheckRun() {
        let file = WorkflowFile(yaml: Self.yaml)
        #expect(file.job(forCheckRun: "Unit tests (macos)")?.key == "unit")
        #expect(file.job(forCheckRun: "lint")?.key == "lint")
        #expect(file.job(forCheckRun: "Deploy dev")?.key == "deploy-dev")
        #expect(file.job(forCheckRun: "Something else") == nil)
    }

    @Test func linksCheckRunsByTheWorkflowsNeeds() {
        let jobs = ["Compile", "Unit tests (ubuntu)", "Unit tests (macos)", "lint", "Deploy dev"].map {
            StagePlanner.Job(job: job($0))
        }
        let linked = StagePlanner.linked(jobs, by: WorkflowFile(yaml: Self.yaml)).map(\.job)
        #expect(linked[1].needs == ["Compile"])
        // Both matrix instances, and the job without a name by its key.
        #expect(linked[4].needs == ["Unit tests (ubuntu)", "Unit tests (macos)", "lint"])
        let unlinked = StagePlanner.linked(jobs, by: nil)
        #expect(unlinked.allSatisfy { $0.job.needs.isEmpty })
    }
}

struct WorkflowGraphLayoutTests {
    private let stages = [
        DeliveryStage(
            id: "build", name: "Build", kind: .build, workflow: "CI", state: .succeeded,
            jobs: [
                job("Compile"), job("Unit", needs: ["Compile"]), job("Integration", needs: ["Compile"]),
                job("Lint", needs: ["Compile"]),
            ]),
        DeliveryStage(
            id: "dev", name: "dev", kind: .environment, workflow: "CI", state: .running,
            jobs: [job("Deploy dev", .running, needs: ["Unit", "Integration", "Lint"])]),
        DeliveryStage(id: "prod", name: "prod", kind: .environment, workflow: "CI", state: .needsApproval),
    ]

    @Test func jobsStandInColumnsByWhatTheyWaitFor() throws {
        let layout = WorkflowGraphLayout(stages: stages)
        let frame = { (id: String) in layout.nodes.first { $0.id == id }?.frame ?? .zero }
        // The split: three jobs in the second column, one above the other, centred on the first.
        #expect(frame("Unit").minX == frame("Integration").minX && frame("Unit").minX > frame("Compile").maxX)
        #expect(frame("Integration").midY == frame("Compile").midY)
        #expect(frame("Unit").maxY < frame("Integration").minY)
        // Stages side by side, each in its own band; a stage without jobs is one box.
        #expect(layout.bands.map(\.stageID) == ["build", "dev", "prod"])
        let firstBand = try #require(layout.bands.first)
        let lastBand = try #require(layout.bands.last)
        #expect(frame("Deploy dev").minX > firstBand.frame.maxX)
        #expect(layout.nodes.last?.id == "stage#prod" && layout.nodes.last?.job == nil)
        #expect(layout.size.width == lastBand.frame.maxX)
    }

    @Test func linesRunFromEdgeToEdgeAndJoin() throws {
        let layout = WorkflowGraphLayout(stages: stages)
        let edge = { (id: String) in layout.edges.first { $0.id == id } }
        // The split inside the build, at right angles.
        let split = try #require(edge("Compile>Unit"))
        let compile = try #require(layout.nodes.first { $0.id == "Compile" }).frame
        let unit = try #require(layout.nodes.first { $0.id == "Unit" }).frame
        #expect(split.points.first == CGPoint(x: compile.maxX, y: compile.midY))
        #expect(split.points.last == CGPoint(x: unit.minX, y: unit.midY))
        #expect(zip(split.points, split.points.dropFirst()).allSatisfy { $0.x == $1.x || $0.y == $1.y })
        // The join into dev follows `needs` across the stages; prod hangs on dev's last job.
        #expect(["Unit>Deploy dev", "Integration>Deploy dev", "Lint>Deploy dev"].allSatisfy { edge($0) != nil })
        #expect(edge("Deploy dev>stage#prod")?.isWalked == false)
        #expect(edge("Compile>Unit")?.isWalked == true)
    }

    @Test func withoutNeedsTheJobsOfAStageStandTogether() {
        let plain = DeliveryStage(
            id: "s", name: "Checks", kind: .build, workflow: nil, state: .succeeded, jobs: [job("A"), job("B")])
        #expect(WorkflowGraphLayout.grid(plain).map(\.count) == [2])
    }
}

struct JobLogTests {
    @Test func shortensTimestampsAndMarksGroupsAndErrors() {
        let log = JobLog(
            text: """
                2026-11-26T14:30:43.4123Z ##[group]Run ./deploy/migrate.sh
                2026-11-26T14:30:44.9Z Applying migration 0142 … failed
                2026-11-26T14:30:45.0Z ##[error]relation "invoices" already exists
                2026-11-26T14:30:45.1Z ##[endgroup]
                plain line

                """)
        #expect(log.lines.map(\.time) == ["14:30:43", "14:30:44", "14:30:45", ""])
        #expect(log.lines.map(\.kind) == [.heading, .plain, .error, .plain])
        #expect(log.lines[0].text == "Run ./deploy/migrate.sh")
        #expect(log.lines[2].text == "relation \"invoices\" already exists")
    }

    @Test func theExcerptShowsTheErrorElseTheEnd() {
        let text = (0..<100).map { "line \($0)" } + ["##[error]boom"] + (0..<100).map { "after \($0)" }
        let log = JobLog(text: text.joined(separator: "\n"))
        let error = log.lines.firstIndex { $0.kind == .error } ?? -1
        #expect(log.excerpt.contains(error) && log.excerpt.count == JobLog.excerptLength)
        let quiet = JobLog(text: (0..<100).map { "line \($0)" }.joined(separator: "\n"))
        #expect(quiet.excerpt.upperBound == 100 && quiet.hiddenCount == 100 - JobLog.excerptLength)
    }
}

struct DeliveryBadgeTests {
    private func delivery(_ states: [StageState], mergedAt: Date = .now) -> Delivery {
        Delivery(
            pullRequest: .init(owner: "acme", repository: "billing", number: 1), title: "T", mergeCommitSHA: "a",
            mergedAt: mergedAt,
            stages: states.enumerated().map { index, state in
                DeliveryStage(
                    id: "s\(index)", name: index == 0 ? "build" : "env\(index)",
                    kind: index == 0 ? .build : .environment,
                    workflow: "CI", state: state)
            })
    }

    @Test func tellsTheOutcome() {
        #expect(delivery([.succeeded, .running]).badge().outcome == .inProgress)
        #expect(delivery([.succeeded, .running]).badge().dots == [.done, .running])
        #expect(delivery([.succeeded, .failed]).badge().outcome == .problem)
        #expect(delivery([.succeeded, .succeeded]).badge().text == "Live")
        #expect(delivery([.succeeded, .succeeded]).badge(verdicts: ["s1": .healthy]).text == "Live · checked healthy")
        let problems = delivery([.succeeded, .succeeded]).badge(verdicts: ["s1": .problems])
        #expect(problems.outcome == .problem && problems.text == "Live · problems found")
        #expect(delivery([.succeeded, .cancelled]).badge().outcome == .inProgress)
    }
}
