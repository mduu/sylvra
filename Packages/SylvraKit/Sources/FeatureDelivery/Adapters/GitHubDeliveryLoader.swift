import Foundation
import Platform
import SylvraCore

/// Loads the workflow runs, jobs and deployments of a pull request's merge commit with one GraphQL request.
public struct GitHubDeliveryLoader: DeliveryLoading {
    let client: GitHubClient
    /// Workflow files per path and commit: they never change, and the delivery reloads every 30 s.
    private let workflows = WorkflowFileCache()

    public init(client: GitHubClient) {
        self.client = client
    }

    public func loadDelivery(for id: PullRequestID) async throws -> Delivery? {
        let response = try await client.graphQL(
            Self.query,
            variables: ["owner": .string(id.owner), "name": .string(id.repository), "number": .int(id.number)],
            as: DeliveryResponse.self)
        guard let pullRequest = response.repository?.pullRequest, let commit = pullRequest.mergeCommit else {
            return nil
        }
        let paths = Set((commit.checkSuites?.values ?? []).compactMap { $0.workflowRun?.file?.path })
        var files: [String: WorkflowFile] = [:]
        for path in paths {
            files[path] = await workflowFile(path, at: commit.oid, in: id)
        }
        return pullRequest.delivery(for: id, workflows: files)
    }

    /// The workflow file as of the merge commit (`nil`: not readable — the graph then has no dependencies).
    private func workflowFile(_ path: String, at sha: String, in id: PullRequestID) async -> WorkflowFile? {
        let key = "\(id.owner)/\(id.repository)/\(path)@\(sha)"
        if let cached = await workflows.file(for: key) { return cached }
        guard
            let data = try? await client.rest(
                path: "repos/\(id.owner)/\(id.repository)/contents/\(path)",
                query: [URLQueryItem(name: "ref", value: sha)],
                accept: "application/vnd.github.raw"),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        let file = WorkflowFile(yaml: text)
        await workflows.store(file, for: key)
        return file
    }

    public func loadLog(jobID: Int, in id: PullRequestID) async throws -> String {
        let data = try await client.rest(
            path: "repos/\(id.owner)/\(id.repository)/actions/jobs/\(jobID)/logs", accept: "application/vnd.github.raw")
        return String(decoding: data, as: UTF8.self)
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
                    file { path }
                    workflow { name }
                    pendingDeploymentRequests(first: 10) { nodes { currentUserCanApprove environment { id name } } }
                  }
                  checkRuns(first: 50) { nodes {
                    id databaseId name status conclusion startedAt completedAt detailsUrl
                    deployment { environment }
                    pendingDeploymentRequest { environment { name } }
                    steps(first: 50) { nodes { name number status conclusion } }
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

        /// `nil` while the pull request is not merged. `workflows`: the workflow files by path.
        func delivery(for id: PullRequestID, workflows: [String: WorkflowFile] = [:]) -> Delivery? {
            guard state == "MERGED", let mergeCommit else { return nil }
            let runs = (mergeCommit.checkSuites?.values ?? []).compactMap { suite -> StagePlanner.Run? in
                var run = suite.run
                run?.workflow = suite.workflowRun?.file.flatMap { workflows[$0.path] }
                return run
            }
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
        let file: File?
        let pendingDeploymentRequests: Nodes<DeploymentRequest>?
        struct File: Decodable, Sendable { let path: String }
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
        let databaseId: Int?
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
            let status: String?
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
                    failedSteps: state == .failed ? failedSteps : [], errors: state == .failed ? errors : [],
                    jobID: databaseId,
                    steps: (steps?.values ?? []).sorted { $0.number < $1.number }.map { step in
                        JobStep(
                            number: step.number, name: step.name,
                            state: Self.state(status: step.status ?? "COMPLETED", conclusion: step.conclusion))
                    }),
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

/// Workflow files already read, per path and commit.
actor WorkflowFileCache {
    private var files: [String: WorkflowFile] = [:]

    func file(for key: String) -> WorkflowFile? { files[key] }

    func store(_ file: WorkflowFile, for key: String) {
        if files.count > 50 { files.removeAll() }
        files[key] = file
    }
}
