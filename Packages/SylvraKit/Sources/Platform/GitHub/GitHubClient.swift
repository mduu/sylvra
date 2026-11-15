import Foundation

/// Errors of the GitHub client.
public enum GitHubError: Error, Equatable, Sendable, LocalizedError {
    /// No token available (not signed in).
    case notAuthenticated
    /// HTTP error with status code and message.
    case http(status: Int, message: String)
    /// GraphQL returned errors.
    case graphQL([String])
    /// The response could not be decoded.
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            String(localized: "Not signed in to GitHub. Run `gh auth login` or sign in in Settings.")
        case .http(let status, let message): "GitHub \(status): \(message)"
        case .graphQL(let messages): messages.joined(separator: "\n")
        case .decoding(let message): String(localized: "Unexpected response from GitHub: \(message)")
        }
    }
}

/// Sends HTTP requests. Abstracted so the client can be tested without network access.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession` based transport.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.http(status: 0, message: "No HTTP response")
        }
        return (data, http)
    }
}

/// Minimal GitHub API client (GraphQL + REST).
public actor GitHubClient {
    public static let defaultEndpoint = URL(string: "https://api.github.com")

    private let baseURL: URL
    private let tokenProvider: any GitHubTokenProviding
    private let transport: any HTTPTransport
    private var cachedToken: String?

    /// Remaining GraphQL / REST budget as reported by the last response.
    public private(set) var rateLimitRemaining: Int?

    public init(
        baseURL: URL? = GitHubClient.defaultEndpoint,
        tokenProvider: any GitHubTokenProviding,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.baseURL = baseURL ?? URL(fileURLWithPath: "/")
        self.tokenProvider = tokenProvider
        self.transport = transport
    }

    /// Runs a GraphQL query and decodes the `data` object into `Response`.
    public func graphQL<Response: Decodable & Sendable>(
        _ query: String,
        variables: [String: GraphQLValue] = [:],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let body = GraphQLRequestBody(query: query, variables: variables)
        var request = try await authorizedRequest(path: "graphql")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await perform(request)
        let envelope: GraphQLEnvelope<Response>
        do {
            envelope = try GitHubJSON.decoder.decode(GraphQLEnvelope<Response>.self, from: data)
        } catch {
            throw GitHubError.decoding(String(describing: error))
        }
        if let errors = envelope.errors, !errors.isEmpty {
            throw GitHubError.graphQL(errors.map(\.message))
        }
        guard let payload = envelope.data else {
            throw GitHubError.decoding("GraphQL response without data")
        }
        return payload
    }

    /// GET request against the REST API returning the raw body (e.g. diffs with a custom `Accept` header).
    public func rest(
        path: String, query: [URLQueryItem] = [], accept: String = "application/vnd.github+json"
    ) async throws -> Data {
        var request = try await authorizedRequest(path: path, query: query)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    // MARK: - Private

    private func authorizedRequest(path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        let token = try await token()
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Sylvra", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func token() async throws -> String {
        if let cachedToken { return cachedToken }
        guard let token = try await tokenProvider.token(), !token.isEmpty else {
            throw GitHubError.notAuthenticated
        }
        cachedToken = token
        return token
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
            rateLimitRemaining = Int(remaining)
        }
        if response.statusCode == 401 {
            cachedToken = nil
            throw GitHubError.notAuthenticated
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(GitHubMessage.self, from: data))?.message
            throw GitHubError.http(
                status: response.statusCode,
                message: message ?? String(bytes: data.prefix(200), encoding: .utf8) ?? ""
            )
        }
        return data
    }
}

/// JSON coding conventions of the GitHub API.
public enum GitHubJSON {
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct GitHubMessage: Decodable {
    let message: String
}

private struct GraphQLRequestBody: Encodable {
    let query: String
    let variables: [String: GraphQLValue]
}

private struct GraphQLEnvelope<Payload: Decodable>: Decodable {
    let data: Payload?
    let errors: [GraphQLErrorMessage]?
}

private struct GraphQLErrorMessage: Decodable {
    let message: String
}

/// A JSON value for GraphQL variables.
public enum GraphQLValue: Encodable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
