import Foundation
import Platform

/// Sends feedback as an issue to a GitHub repository with the user's own GitHub account.
///
/// GitHub's API has no upload for issue attachments. A screenshot is therefore committed to a branch of the
/// repository kept for that (`feedback-attachments`) and linked in the issue — which needs write access. Without
/// it the issue is created without the picture and the receipt says so.
public struct GitHubFeedbackSender: FeedbackSending {
    let client: GitHubClient
    let owner: String
    let repository: String
    static let branch = "feedback-attachments"

    public init(client: GitHubClient, owner: String, repository: String) {
        self.client = client
        self.owner = owner
        self.repository = repository
    }

    public func send(_ draft: FeedbackDraft, info: SystemInfo?, screenshot: Data?) async throws -> FeedbackReceipt {
        var markdown: String?
        var isMissing = false
        if draft.includesScreenshot, let screenshot {
            if let url = try? await upload(screenshot) {
                markdown = "![Sylvra window](\(url))"
            } else {
                isMissing = true
                markdown = "_A screenshot was taken but could not be uploaded; it may follow in a comment._"
            }
        }
        let issue = FeedbackIssue.make(from: draft, info: info, screenshot: markdown)
        let answer = try await client.restWrite(
            method: "POST", path: "repos/\(owner)/\(repository)/issues",
            body: IssueBody(title: issue.title, body: issue.body, labels: issue.labels))
        let created = try GitHubJSON.decoder.decode(CreatedIssue.self, from: answer)
        return FeedbackReceipt(number: created.number, url: created.htmlUrl, screenshotMissing: isMissing)
    }

    /// Commits the picture to the attachments branch (created from the default branch when missing) and
    /// returns the address that shows it.
    private func upload(_ png: Data) async throws -> String {
        let name = "feedback/\(UUID().uuidString.lowercased()).png"
        let body = FileBody(
            message: "Add feedback screenshot", content: png.base64EncodedString(), branch: Self.branch)
        let path = "repos/\(owner)/\(repository)/contents/\(name)"
        do {
            _ = try await client.restWrite(method: "PUT", path: path, body: body)
        } catch {
            // The branch may not exist yet.
            try await createBranch()
            _ = try await client.restWrite(method: "PUT", path: path, body: body)
        }
        return "https://github.com/\(owner)/\(repository)/blob/\(Self.branch)/\(name)?raw=true"
    }

    private func createBranch() async throws {
        let repo = try GitHubJSON.decoder.decode(
            RepositoryInfo.self, from: try await client.rest(path: "repos/\(owner)/\(repository)"))
        let head = try GitHubJSON.decoder.decode(
            Reference.self,
            from: try await client.rest(path: "repos/\(owner)/\(repository)/git/ref/heads/\(repo.defaultBranch)"))
        _ = try await client.restWrite(
            method: "POST", path: "repos/\(owner)/\(repository)/git/refs",
            body: NewReference(ref: "refs/heads/\(Self.branch)", sha: head.object.sha))
    }

    private struct IssueBody: Encodable, Sendable {
        let title: String
        let body: String
        let labels: [String]
    }

    private struct FileBody: Encodable, Sendable {
        let message: String
        let content: String
        let branch: String
    }

    private struct NewReference: Encodable, Sendable {
        let ref: String
        let sha: String
    }

    private struct CreatedIssue: Decodable, Sendable {
        let number: Int
        let htmlUrl: URL?
        enum CodingKeys: String, CodingKey {
            case number
            case htmlUrl = "html_url"
        }
    }

    private struct RepositoryInfo: Decodable, Sendable {
        let defaultBranch: String
        enum CodingKeys: String, CodingKey { case defaultBranch = "default_branch" }
    }
    private struct Reference: Decodable, Sendable {
        struct Object: Decodable, Sendable { let sha: String }
        let object: Object
    }
}

/// Pretends to send (demo mode, previews).
public struct DemoFeedbackSender: FeedbackSending {
    public init() {}

    public func send(_ draft: FeedbackDraft, info: SystemInfo?, screenshot: Data?) async throws -> FeedbackReceipt {
        try await Task.sleep(for: .milliseconds(600))
        return FeedbackReceipt(number: 42, url: URL(string: "https://github.com/mduu/sylvra/issues/42"))
    }
}
