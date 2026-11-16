import Foundation
import Testing

@testable import Platform

/// Transport returning canned responses and recording requests.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    var status = 200
    /// Statuses for the first requests (then `status`).
    var statusSequence: [Int] = []
    var body = Data()
    var headers: [String: String] = [:]
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let code = requests.count <= statusSequence.count ? statusSequence[requests.count - 1] : status
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
        return (body, response)
    }
}

struct GitHubClientTests {
    private func client(_ transport: FakeTransport, token: String? = "secret") -> GitHubClient {
        GitHubClient(tokenProvider: StaticTokenProvider(token), transport: transport, retryDelays: [.zero, .zero])
    }

    @Test func decodesViewer() async throws {
        let transport = FakeTransport()
        transport.body = Data(#"{"data":{"viewer":{"login":"mduu","name":"Marc","avatarUrl":"https://a/1"}}}"#.utf8)
        transport.headers = ["X-RateLimit-Remaining": "4999"]

        let viewer = try await client(transport).viewer()

        #expect(viewer.login == "mduu")
        #expect(viewer.initials == "M")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(transport.requests.first?.url?.path == "/graphql")
        #expect(await client(transport).rateLimitRemaining == nil)
    }

    @Test func tracksRateLimit() async throws {
        let transport = FakeTransport()
        transport.body = Data(#"{"data":{"viewer":{"login":"a","name":null,"avatarUrl":null}}}"#.utf8)
        transport.headers = ["X-RateLimit-Remaining": "42"]
        let github = client(transport)
        _ = try await github.viewer()
        #expect(await github.rateLimitRemaining == 42)
    }

    @Test func surfacesGraphQLErrors() async throws {
        let transport = FakeTransport()
        transport.body = Data(#"{"errors":[{"message":"Field 'x' doesn't exist"}]}"#.utf8)
        await #expect(throws: GitHubError.graphQL(["Field 'x' doesn't exist"])) {
            _ = try await client(transport).viewer()
        }
    }

    @Test func mapsUnauthorized() async throws {
        let transport = FakeTransport()
        transport.status = 401
        transport.body = Data(#"{"message":"Bad credentials"}"#.utf8)
        await #expect(throws: GitHubError.notAuthenticated) {
            _ = try await client(transport).viewer()
        }
    }

    @Test func requiresToken() async throws {
        await #expect(throws: GitHubError.notAuthenticated) {
            _ = try await client(FakeTransport(), token: nil).viewer()
        }
    }

    @Test func mapsHTTPErrorsWithMessage() async throws {
        let transport = FakeTransport()
        transport.status = 502
        transport.body = Data(#"{"message":"Server Error"}"#.utf8)
        await #expect(throws: GitHubError.http(status: 502, message: "Server Error")) {
            _ = try await client(transport).viewer()
        }
    }

    @Test func retriesGatewayTimeouts() async throws {
        let transport = FakeTransport()
        transport.statusSequence = [502, 504]
        transport.body = Data(#"{"data":{"viewer":{"login":"a","name":null,"avatarUrl":null}}}"#.utf8)
        let viewer = try await client(transport).viewer()
        #expect(viewer.login == "a")
        #expect(transport.requests.count == 3)
    }

    @Test func givesUpAfterRetries() async throws {
        let transport = FakeTransport()
        transport.status = 502
        transport.body = Data("<html><head><title>502 Bad Gateway</title></head><body>nginx</body></html>".utf8)
        await #expect(throws: GitHubError.http(status: 502, message: "502 Bad Gateway nginx")) {
            _ = try await client(transport).viewer()
        }
        #expect(transport.requests.count == 3)
        #expect(GitHubError.http(status: 502, message: "").errorDescription?.contains("<html>") == false)
    }

    @Test func neverRetriesMutations() async throws {
        let transport = FakeTransport()
        transport.status = 502
        struct Empty: Decodable, Sendable {}
        await #expect(throws: GitHubError.self) {
            _ = try await client(transport).graphQL("mutation { x }", as: Empty.self)
        }
        #expect(transport.requests.count == 1)
    }
}
