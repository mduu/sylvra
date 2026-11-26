import Foundation

extension GitHubClient {
    /// A writing request against the REST API (`POST`, `PUT` …) with a JSON body; returns the raw answer.
    /// Never retried: a timeout doesn't tell whether it was applied. The body is not logged (it may carry a
    /// file's content).
    public func restWrite(method: String, path: String, body: some Encodable & Sendable) async throws -> Data {
        var request = try await authorizedRequest(path: path)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let log = LogContext(title: "\(method) /\(path)", request: nil, showsResponse: true)
        return try await perform(request, retryTransient: false, log: log)
    }
}
