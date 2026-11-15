import Foundation
import Testing

@testable import Platform

struct SystemProcessRunnerTests {
    @Test func capturesStandardOutput() async throws {
        let output = try await SystemProcessRunner().output(of: "echo", arguments: ["hello", "sylvra"])
        #expect(output == "hello sylvra")
    }

    @Test func passesArgumentsWithoutShellInterpretation() async throws {
        let output = try await SystemProcessRunner().output(of: "echo", arguments: ["$(whoami); rm -rf /"])
        #expect(output == "$(whoami); rm -rf /")
    }

    @Test func reportsNonZeroExitCodes() async throws {
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await SystemProcessRunner().output(of: "false", arguments: [])
        }
    }

    @Test func unknownToolsAreNotFound() async throws {
        await #expect(throws: ProcessRunnerError.executableNotFound("sylvra-does-not-exist")) {
            _ = try await SystemProcessRunner().output(of: "sylvra-does-not-exist", arguments: [])
        }
    }

    @Test func locatorSearchesHomebrew() {
        #expect(ExecutableLocator.searchDirectories.contains("/opt/homebrew/bin"))
        #expect(ExecutableLocator.locate("ls") != nil)
    }
}

struct ProcessInputTests {
    @Test func writesStandardInput() async throws {
        let cat = try #require(ExecutableLocator.locate("cat"))
        let result = try await SystemProcessRunner().run(
            cat, arguments: [], workingDirectory: nil, input: Data(String(repeating: "x", count: 200_000).utf8))
        #expect(result.standardOutput.count == 200_000)
    }
}

struct ProcessCancellationTests {
    @Test func cancellationTerminatesTheChild() async throws {
        let sleep = try #require(ExecutableLocator.locate("sleep"))
        let start = Date.now
        let task = Task { try await SystemProcessRunner().run(sleep, arguments: ["30"], workingDirectory: nil) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        _ = try? await task.value
        #expect(Date.now.timeIntervalSince(start) < 10)
    }

    @Test func nonUTF8OutputIsKept() async throws {
        let printf = try #require(ExecutableLocator.locate("printf"))
        let result = try await SystemProcessRunner().run(printf, arguments: ["caf\\351"], workingDirectory: nil)
        #expect(result.standardOutput.hasPrefix("caf"))
    }
}

struct JSONCacheTests {
    @Test func roundTripsValues() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "sylvra-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONCache(directory: directory)
        cache.save(["a": Date(timeIntervalSince1970: 0)], key: "acme/billing#1")
        #expect(cache.load([String: Date].self, key: "acme/billing#1")?["a"] == Date(timeIntervalSince1970: 0))
        #expect(cache.load([String: Date].self, key: "missing") == nil)
    }
}
