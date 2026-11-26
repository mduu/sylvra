import Foundation
import Platform
import SylvraCore

/// Loads the workflow runs, jobs and deployments of a pull request's merge commit with one GraphQL request.
public struct GitHubDeliveryLoader: DeliveryLoading {
    let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    public func loadDelivery(for id: PullRequestID) async throws -> Delivery? {
        let response = try await client.graphQL(
            Self.query,
            variables: ["owner": .string(id.owner), "name": .string(id.repository), "number": .int(id.number)],
            as: DeliveryResponse.self)
        return response.repository?.pullRequest?.delivery(for: id)
    }

    public func approve(_ approval: DeliveryStage.Approval) async throws {
        _ = try await client.graphQL(
            """
            mutation($run: ID!, $environments: [ID!]!) {
              approveDeployments(input: {workflowRunId: $run, environmentIds: $environments}) { clientMutationId }
            }
            """,
            variables: [
                "run": .string(approval.workflowRunID), "environments": .array([.string(approval.environmentID)]),
            ],
            as: EmptyAnswer.self)
    }

    static let query = """
        query Delivery($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              title state mergedAt
              mergeCommit {
                oid
                checkSuites(first: 30) { nodes {
                  workflowRun {
                    id url event createdAt
                    workflow { name }
                    pendingDeploymentRequests(first: 10) { nodes { currentUserCanApprove environment { id name } } }
                  }
                  checkRuns(first: 50) { nodes {
                    id name status conclusion startedAt completedAt detailsUrl
                    deployment { environment }
                    pendingDeploymentRequest { environment { name } }
                    steps(first: 30) { nodes { name number conclusion } }
                    annotations(first: 5) { nodes { message annotationLevel } }
                  } }
                } }
                deployments(first: 30) { nodes {
                  environment state createdAt
                  latestStatus { state createdAt logUrl environmentUrl }
                } }
              }
            }
          }
        }
        """
}

private struct EmptyAnswer: Decodable, Sendable {}

// MARK: - Response

struct DeliveryResponse: Decodable, Sendable {
    let repository: Repository?
    struct Repository: Decodable, Sendable { let pullRequest: PullRequestNode? }
    struct Nodes<Value: Decodable & Sendable>: Decodable, Sendable {
        let nodes: [Value?]?
        var values: [Value] { (nodes ?? []).compactMap { $0 } }
    }

    struct PullRequestNode: Decodable, Sendable {
        let title: String
        let state: String
        let mergedAt: Date?
        let mergeCommit: Commit?

        /// `nil` while the pull request is not merged.
        func delivery(for id: PullRequestID) -> Delivery? {
            guard state == "MERGED", let mergeCommit else { return nil }
            let runs = (mergeCommit.checkSuites?.values ?? []).compactMap(\.run)
            let deployments = (mergeCommit.deployments?.values ?? []).map(\.model)
            return Delivery(
                pullRequest: id, title: title, mergeCommitSHA: mergeCommit.oid, mergedAt: mergedAt,
                stages: StagePlanner.stages(runs: runs, deployments: deployments))
        }
    }

    struct Commit: Decodable, Sendable {
        let oid: String
        let checkSuites: Nodes<CheckSuite>?
        let deployments: Nodes<Deployment>?
    }

    struct CheckSuite: Decodable, Sendable {
        let workflowRun: WorkflowRun?
        let checkRuns: Nodes<CheckRun>?

        /// Only GitHub Actions runs: other apps' check suites are checks, not a delivery.
        var run: StagePlanner.Run? {
            guard let workflowRun else { return nil }
            return StagePlanner.Run(
                id: workflowRun.id, name: workflowRun.workflow?.name ?? String(localized: "Workflow"),
                event: workflowRun.event ?? "", url: workflowRun.url, createdAt: workflowRun.createdAt,
                jobs: (checkRuns?.values ?? []).map(\.job),
                pending: (workflowRun.pendingDeploymentRequests?.values ?? []).compactMap { request in
                    request.environment.flatMap { environment in
                        environment.id.map {
                            .init(
                                environment: environment.name, environmentID: $0,
                                viewerCanApprove: request.currentUserCanApprove ?? false)
                        }
                    }
                })
        }
    }

    struct WorkflowRun: Decodable, Sendable {
        let id: String
        let url: URL?
        let event: String?
        let createdAt: Date?
        let workflow: Named?
        let pendingDeploymentRequests: Nodes<DeploymentRequest>?
    }

    struct Named: Decodable, Sendable { let name: String }
    struct Environment: Decodable, Sendable {
        let id: String?
        let name: String
    }
    struct DeploymentRequest: Decodable, Sendable {
        let currentUserCanApprove: Bool?
        let environment: Environment?
    }

    struct CheckRun: Decodable, Sendable {
        let id: String
        let name: String
        let status: String
        let conclusion: String?
        let startedAt: Date?
        let completedAt: Date?
        let detailsUrl: URL?
        let deployment: JobDeployment?
        let pendingDeploymentRequest: DeploymentRequest?
        let steps: Nodes<Step>?
        let annotations: Nodes<Annotation>?

        struct JobDeployment: Decodable, Sendable { let environment: String? }
        struct Step: Decodable, Sendable {
            let name: String
            let number: Int
            let conclusion: String?
        }
        struct Annotation: Decodable, Sendable {
            let message: String
            let annotationLevel: String?
        }

        var job: StagePlanner.Job {
            let state = Self.state(status: status, conclusion: conclusion)
            let failedSteps = (steps?.values ?? []).sorted { $0.number < $1.number }
                .filter { ["FAILURE", "TIMED_OUT"].contains($0.conclusion ?? "") }.map(\.name)
            let errors = (annotations?.values ?? []).filter { $0.annotationLevel == "FAILURE" }.map(\.message)
            return StagePlanner.Job(
                job: DeliveryJob(
                    id: id, name: name, state: state, startedAt: startedAt, finishedAt: completedAt, url: detailsUrl,
                    failedSteps: state == .failed ? failedSteps : [], errors: state == .failed ? errors : []),
                environment: deployment?.environment ?? pendingDeploymentRequest?.environment?.name)
        }

        static func state(status: String, conclusion: String?) -> StageState {
            switch status {
            case "COMPLETED":
                switch conclusion {
                case "SUCCESS", "NEUTRAL": .succeeded
                case "SKIPPED": .skipped
                case "CANCELLED", "STALE": .cancelled
                default: .failed
                }
            case "IN_PROGRESS": .running
            case "WAITING": .needsApproval
            default: .waiting
            }
        }
    }

    struct Deployment: Decodable, Sendable {
        let environment: String?
        let state: String?
        let createdAt: Date?
        let latestStatus: Status?
        struct Status: Decodable, Sendable {
            let state: String?
            let createdAt: Date?
            let logUrl: URL?
            let environmentUrl: URL?
        }

        var model: StagePlanner.Deployment {
            StagePlanner.Deployment(
                environment: environment ?? String(localized: "Deployment"),
                state: Self.state(latestStatus?.state ?? state), createdAt: createdAt,
                finishedAt: latestStatus?.createdAt, url: latestStatus?.logUrl ?? latestStatus?.environmentUrl)
        }

        /// `INACTIVE` and `DESTROYED`: deployed once, replaced or removed since.
        static func state(_ state: String?) -> StageState {
            switch state {
            case "SUCCESS", "ACTIVE", "INACTIVE", "DESTROYED": .succeeded
            case "FAILURE", "ERROR": .failed
            case "IN_PROGRESS": .running
            case "WAITING": .needsApproval
            case "ABANDONED": .cancelled
            default: .waiting
            }
        }
    }
}
