import Foundation
import OSLog

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
        case .http(let status, let message):
            if GitHubClient.isTransient(status) {
                String(
                    localized:
                        "GitHub didn't answer in time (\(status)). It may be busy or the request was too large — try again in a moment."
                )
            } else {
                "GitHub \(status): \(message)"
            }
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
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // A cancelled task (e.g. the user kept typing) is not an error worth showing.
            throw CancellationError()
        }
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
    private let logger = SylvraLog.logger("github")
    private let retryDelays: [Duration]

    /// Remaining GraphQL / REST budget as reported by the last response.
    public private(set) var rateLimitRemaining: Int?
    /// GitHub left out results of these organizations (IDs) because the token isn't authorized
    /// for their SAML single sign-on (`X-GitHub-SSO: partial-results`).
    public private(set) var ssoRestrictedOrganizations: Set<String> = []

    public init(
        baseURL: URL? = GitHubClient.defaultEndpoint,
        tokenProvider: any GitHubTokenProviding,
        transport: any HTTPTransport = URLSessionTransport(),
        retryDelays: [Duration] = [.seconds(1), .seconds(3)]
    ) {
        self.retryDelays = retryDelays
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

        // Mutations are never retried: a gateway timeout doesn't tell whether they were applied.
        let isMutation = query.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("mutation")
        let log = LogContext(
            title: "GraphQL " + CommandLogText.graphQLOperation(query),
            request: Self.describe(variables), showsResponse: true)
        let data = try await perform(request, retryTransient: !isMutation, log: log)
        let envelope = try await Self.decodeEnvelope(GraphQLEnvelope<Response>.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            logger.error("GraphQL errors: \(errors.map(\.message).joined(separator: " | "), privacy: .public)")
            throw GitHubError.graphQL(errors.map(\.message))
        }
        guard let payload = envelope.data else {
            throw GitHubError.decoding("GraphQL response without data")
        }
        return payload
    }

    /// Decodes off the actor: parallel requests (the inbox sections) otherwise decode one after the other.
    private nonisolated static func decodeEnvelope<Envelope: Decodable>(_ type: Envelope.Type, from data: Data)
        async throws -> Envelope
    {
        do {
            return try GitHubJSON.decoder.decode(type, from: data)
        } catch {
            throw GitHubError.decoding(String(describing: error))
        }
    }

    /// GET request against the REST API returning the raw body (e.g. diffs with a custom `Accept` header).
    public func rest(
        path: String, query: [URLQueryItem] = [], accept: String = "application/vnd.github+json"
    ) async throws -> Data {
        var request = try await authorizedRequest(path: path, query: query)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let query = query.isEmpty ? "" : "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        // Diffs and file contents are code: the panel only shows their size.
        let isCode = accept.contains("diff") || accept.contains("raw") || path.contains("/contents/")
        let log = LogContext(title: "GET /\(path)\(query)", request: nil, showsResponse: !isCode)
        return try await perform(request, retryTransient: true, log: log)
    }

    /// How a request appears in the Commands panel.
    private struct LogContext: Sendable {
        let title: String
        let request: String?
        let showsResponse: Bool
    }

    private static func describe(_ variables: [String: GraphQLValue]) -> String? {
        guard !variables.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(variables)).map { String(decoding: $0, as: UTF8.self) }
    }

    private func record(_ log: LogContext, started: Date, result: Result<Data, any Error>) {
        let entry: CommandLogEntry
        switch result {
        case .success(let data):
            let duration = Date.now.timeIntervalSince(started)
            // Pretty-printing a large answer for the panel took longer than decoding it: done in the
            // background instead of on the actor that the next requests wait for.
            Task.detached(priority: .utility) {
                CommandLog.record(
                    CommandLogEntry(
                        kind: .github, title: log.title, startedAt: started, duration: duration,
                        status: "200", isFailure: false, request: log.request,
                        response: log.showsResponse
                            ? CommandLogText.jsonPreview(data)
                            : CommandLogText.sizeOnly(data.count, reason: "code, not shown")))
            }
            return
        case .failure(let error):
            if error is CancellationError { return }
            let status: String =
                if case GitHubError.http(let code, _) = error { "\(code)" } else { "failed" }
            entry = CommandLogEntry(
                kind: .github, title: log.title, startedAt: started, duration: Date.now.timeIntervalSince(started),
                status: status, isFailure: true, request: log.request, response: String(describing: error))
        }
        CommandLog.record(entry)
    }

    /// Gateway errors GitHub returns when a request times out or the backend is busy.
    public static func isTransient(_ status: Int) -> Bool {
        [502, 503, 504].contains(status)
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

    /// Sends the request; transient gateway errors are retried with the configured back-off.
    private func perform(_ request: URLRequest, retryTransient: Bool, log: LogContext) async throws -> Data {
        let started = Date.now
        do {
            let data = try await performWithRetries(request, retryTransient: retryTransient)
            record(log, started: started, result: .success(data))
            return data
        } catch {
            record(log, started: started, result: .failure(error))
            throw error
        }
    }

    private func performWithRetries(_ request: URLRequest, retryTransient: Bool) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await performOnce(request)
            } catch GitHubError.http(let status, let message) {
                let path = request.url?.path ?? ""
                guard retryTransient, Self.isTransient(status), attempt < retryDelays.count else {
                    logger.error("\(path, privacy: .public) failed: \(status) \(message, privacy: .public)")
                    throw GitHubError.http(status: status, message: message)
                }
                logger.notice("\(path, privacy: .public) returned \(status), retrying")
                try await Task.sleep(for: retryDelays[attempt])
                attempt += 1
            } catch let error as GitHubError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let path = request.url?.path ?? ""
                logger.error("\(path, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                throw error
            }
        }
    }

    private func performOnce(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
            rateLimitRemaining = Int(remaining)
        }
        if let sso = response.value(forHTTPHeaderField: "X-GitHub-SSO") {
            ssoRestrictedOrganizations.formUnion(Self.ssoOrganizations(sso))
        }
        if response.statusCode == 401 {
            cachedToken = nil
            throw GitHubError.notAuthenticated
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(GitHubMessage.self, from: data))?.message
            throw GitHubError.http(
                status: response.statusCode,
                message: message ?? Self.plainText(data)
            )
        }
        return data
    }
}

extension GitHubClient {
    /// Organization IDs of `X-GitHub-SSO: partial-results; organizations=21955855,20582480`.
    static func ssoOrganizations(_ header: String) -> [String] {
        guard header.contains("partial-results") else { return [] }
        guard let list = header.components(separatedBy: "organizations=").dropFirst().first else { return ["?"] }
        return list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Short plain-text excerpt of an error body (HTML error pages are reduced to their text).
    static func plainText(_ data: Data) -> String {
        let raw = String(bytes: data.prefix(2000), encoding: .utf8) ?? ""
        let text = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(text.prefix(200))
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
    case array([GraphQLValue])
    case null

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .null: try container.encodeNil()
        }
    }
}
