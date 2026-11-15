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
