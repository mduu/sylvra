import Foundation
import Platform
import SylvraCore

/// Check run reports ("Summary" on GitHub), loaded when the reviewer opens a check.
extension GitHubPullRequestDetailLoader {
    public func loadCheckReport(nodeID: String) async throws -> CheckReport {
        let response = try await client.graphQL(
            Self.checkReportQuery, variables: ["id": .string(nodeID)], as: CheckReportResponse.self)
        guard let node = response.node else { throw GitHubError.graphQL(["Check run not found"]) }
        return node.report
    }

    static let checkReportQuery = """
        query($id: ID!) {
          node(id: $id) {
            ... on CheckRun {
              title summary text
              annotations(first: 50) {
                nodes { path annotationLevel title message location { start { line } } }
              }
            }
          }
        }
        """
}

struct CheckReportResponse: Decodable, Sendable {
    let node: Node?

    struct Node: Decodable, Sendable {
        let title: String?
        let summary: String?
        let text: String?
        let annotations: Annotations?

        var report: CheckReport {
            CheckReport(
                title: title, summary: summary, text: text,
                annotations: annotations?.nodes.compactMap { $0?.annotation } ?? [])
        }
    }

    struct Annotations: Decodable, Sendable { let nodes: [AnnotationNode?] }

    struct AnnotationNode: Decodable, Sendable {
        let path: String
        let annotationLevel: String?
        let title: String?
        let message: String
        let location: Location?
        struct Location: Decodable, Sendable { let start: Position }
        struct Position: Decodable, Sendable { let line: Int? }

        var annotation: CheckReport.Annotation {
            CheckReport.Annotation(
                path: path, line: location?.start.line,
                level: annotationLevel.flatMap(CheckReport.Annotation.Level.init(rawValue:)) ?? .notice,
                title: title, message: message)
        }
    }
}
