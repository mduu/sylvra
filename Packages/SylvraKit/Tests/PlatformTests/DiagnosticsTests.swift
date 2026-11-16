import Foundation
import Testing

@testable import Platform

/// URL protocol that never answers, so a request stays in flight until it is cancelled.
final class HangingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

struct DiagnosticsTests {
    /// Regression: typing while a repository search was loading showed `NSURLErrorDomain -999`.
    @Test func cancelledRequestsThrowCancellationError() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]
        let transport = URLSessionTransport(session: URLSession(configuration: configuration))
        let task = Task {
            try await transport.send(URLRequest(url: try #require(URL(string: "https://example.invalid/graphql"))))
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func logLineContainsLevelCategoryAndMessage() {
        let entry = DiagnosticLogEntry(
            id: 1, date: .now, level: .error, category: "github", message: "/graphql failed: 502")
        #expect(entry.line.hasSuffix(" error github: /graphql failed: 502"))
    }
}
