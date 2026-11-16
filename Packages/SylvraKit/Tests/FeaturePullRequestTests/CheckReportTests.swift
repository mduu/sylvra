import Foundation
import Platform
import Testing

@testable import FeaturePullRequest

struct CheckReportTests {
    @Test func decodesSummaryAndAnnotations() throws {
        let json = """
            {"node": {"title": "1 failed", "summary": "## Tests\\n1 failed", "text": null,
              "annotations": {"nodes": [
                {"path": "Tests/A.swift", "annotationLevel": "FAILURE", "title": "testA", "message": "boom",
                 "location": {"start": {"line": 12}}},
                {"path": "README.md", "annotationLevel": "OTHER", "title": null, "message": "note", "location": null}]}}}
            """
        let response = try GitHubJSON.decoder.decode(CheckReportResponse.self, from: Data(json.utf8))
        let report = try #require(response.node).report
        #expect(report.title == "1 failed")
        #expect(report.annotations.map(\.line) == [12, nil])
        #expect(report.annotations.map(\.level) == [.failure, .notice])
        #expect(!report.isEmpty)
        #expect(CheckReport(summary: "  \n").isEmpty)
    }

    @Test func splitsMarkdownIntoBlocks() {
        let blocks = SimpleMarkdownView.blocks(
            "## Results\n**41 passed**\n- `a`\n* b\n\n```\nline 1\nline 2\n```\n<details>tail</details>")
        #expect(
            blocks == [
                .heading("Results"), .paragraph("**41 passed**\n• `a`\n• b"), .code("line 1\nline 2"),
                .paragraph("tail"),
            ])
    }

    @MainActor
    @Test func statusesShowTheirDescription() async throws {
        let model = PullRequestScreenModel(loader: DemoPullRequestDetailLoader())
        let status = PullRequestDetail.CheckRun(
            name: "ci/legacy", state: .failure, duration: nil, url: nil, statusDescription: "Build failed")
        #expect(try await model.report(for: status).summary == "Build failed")
        let run = PullRequestDetail.CheckRun(
            name: "unit", state: .failure, duration: nil, url: nil, nodeID: "demo-unit-tests")
        #expect(try await model.report(for: run).annotations.count == 1)
    }
}
