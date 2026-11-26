import Foundation
import Platform
import Testing

@testable import FeatureFeedback

private let info = SystemInfo(
    appVersion: "0.8.3", build: "65", macOS: "27.2.0", model: "Mac16,7", architecture: "arm64", language: "de-CH",
    extras: [.init("Claude Code", "2.1.0")])

private func draft(_ title: String = "Diff loses selection", screenshot: Bool = false) -> FeedbackDraft {
    var draft = FeedbackDraft()
    draft.title = title
    draft.details = "Select text, then scroll."
    draft.includesScreenshot = screenshot
    return draft
}

struct FeedbackIssueTests {
    @Test func theIssueCarriesTextScreenshotAndVersions() {
        let issue = FeedbackIssue.make(from: draft(), info: info, screenshot: "![Sylvra window](https://x/y.png)")
        #expect(issue.title == "Diff loses selection")
        #expect(issue.labels == ["feedback", "bug"])
        #expect(
            issue.body == """
                Select text, then scroll.

                ### Screenshot

                ![Sylvra window](https://x/y.png)

                ### Environment

                - Sylvra 0.8.3 (65)
                - macOS 27.2.0
                - Mac16,7 · arm64
                - Language: de-CH
                - Claude Code: 2.1.0

                _Sent from Sylvra (Help → Send Feedback)._
                """)
    }

    @Test func versionsAreLeftOutWhenSwitchedOff() {
        var draft = draft()
        draft.includesSystemInfo = false
        draft.kind = .idea
        let issue = FeedbackIssue.make(from: draft, info: info)
        #expect(!issue.body.contains("Environment") && !issue.body.contains("macOS"))
        #expect(issue.labels == ["feedback", "enhancement"])
    }

    @Test func aTitleIsNeeded() {
        #expect(!draft("  ").canSend && draft().canSend)
    }
}

/// Answers per request path and records what was sent.
private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    /// Refuses writes to file contents (no write access).
    var refusesUploads = false

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        var status = 201
        var body = "{}"
        if path.hasSuffix("/issues") {
            body = #"{"number": 12, "html_url": "https://github.com/mduu/sylvra/issues/12"}"#
        } else if path.contains("/contents/") || path.hasSuffix("/git/refs") {
            status = refusesUploads ? 404 : 201
        } else if path.hasSuffix("/repos/mduu/sylvra") {
            (status, body) = (200, #"{"default_branch": "main"}"#)
        } else if path.contains("/git/ref/") {
            (status, body) = (200, #"{"object": {"sha": "abc"}}"#)
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"), statusCode: status, httpVersion: nil, headerFields: nil)
        return (Data(body.utf8), response ?? HTTPURLResponse())
    }
}

private struct Token: GitHubTokenProviding {
    func token() async throws -> String? { "secret" }
}

struct GitHubFeedbackSenderTests {
    private func sender(_ transport: ScriptedTransport) -> GitHubFeedbackSender {
        GitHubFeedbackSender(
            client: GitHubClient(tokenProvider: Token(), transport: transport, retryDelays: []), owner: "mduu",
            repository: "sylvra")
    }

    private func json(_ request: URLRequest) -> [String: Any] {
        (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    @Test func createsTheIssueWithTheUploadedScreenshot() async throws {
        let transport = ScriptedTransport()
        let receipt = try await sender(transport).send(
            draft(screenshot: true), info: info, screenshot: Data([1, 2, 3]))
        #expect(receipt == FeedbackReceipt(number: 12, url: URL(string: "https://github.com/mduu/sylvra/issues/12")))
        let upload = try #require(transport.requests.first)
        #expect(
            upload.httpMethod == "PUT" && upload.url?.path.contains("/repos/mduu/sylvra/contents/feedback/") == true)
        #expect(json(upload)["branch"] as? String == "feedback-attachments")
        #expect(json(upload)["content"] as? String == Data([1, 2, 3]).base64EncodedString())
        let issue = try #require(transport.requests.last)
        #expect(issue.httpMethod == "POST" && issue.url?.path.hasSuffix("/repos/mduu/sylvra/issues") == true)
        let body = json(issue)["body"] as? String ?? ""
        #expect(body.contains("![Sylvra window](https://github.com/mduu/sylvra/blob/feedback-attachments/feedback/"))
        #expect(json(issue)["title"] as? String == "Diff loses selection")
    }

    /// Without write access the issue is still created, and the receipt says the picture is missing.
    @Test func withoutWriteAccessTheIssueGoesOutWithoutThePicture() async throws {
        let transport = ScriptedTransport()
        transport.refusesUploads = true
        let receipt = try await sender(transport).send(draft(screenshot: true), info: info, screenshot: Data([1]))
        #expect(receipt.number == 12 && receipt.screenshotMissing)
        let body = json(try #require(transport.requests.last))["body"] as? String ?? ""
        #expect(body.contains("could not be uploaded") && !body.contains("!["))
    }

    @Test func noScreenshotNoUpload() async throws {
        let transport = ScriptedTransport()
        _ = try await sender(transport).send(draft(), info: nil, screenshot: Data([1]))
        #expect(transport.requests.count == 1)
    }
}

private struct FailingSender: FeedbackSending {
    func send(_ draft: FeedbackDraft, info: SystemInfo?, screenshot: Data?) async throws -> FeedbackReceipt {
        throw GitHubError.http(status: 410, message: "Issues are disabled")
    }
}

@MainActor
struct FeedbackModelTests {
    @Test func sendsOnlyWhatIsSwitchedOn() async {
        final class Recorder: FeedbackSending, @unchecked Sendable {
            var sent: [(info: SystemInfo?, screenshot: Data?)] = []
            func send(_ draft: FeedbackDraft, info: SystemInfo?, screenshot: Data?) async throws -> FeedbackReceipt {
                sent.append((info, screenshot))
                return FeedbackReceipt(number: 1, url: nil)
            }
        }
        let recorder = Recorder()
        let model = FeedbackModel(sender: recorder)
        model.systemInfo = { info }
        await model.begin(screenshot: Data([9]))
        model.draft.title = "Idea"
        model.draft.includesSystemInfo = false
        await model.send()
        #expect(recorder.sent.first?.info == nil && recorder.sent.first?.screenshot == nil)
        #expect(model.state == .sent(FeedbackReceipt(number: 1, url: nil)))
        // The next feedback starts empty.
        await model.begin(screenshot: nil)
        #expect(model.draft.title.isEmpty && model.state == .editing)
    }

    @Test func aFailureKeepsTheDraft() async {
        let model = FeedbackModel(sender: FailingSender())
        await model.begin(screenshot: nil)
        model.draft.title = "Bug"
        await model.send()
        guard case .failed(let message) = model.state else {
            Issue.record("expected a failure")
            return
        }
        #expect(message.contains("Issues are disabled"))
        model.edit()
        #expect(model.draft.title == "Bug" && model.state == .editing)
    }
}
