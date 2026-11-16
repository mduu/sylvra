import Foundation
import Testing

@testable import Platform

struct CommandLogTextTests {
    @Test func namesGraphQLOperationsByTheirTopLevelFields() {
        #expect(CommandLogText.graphQLOperation("query { viewer { login } }") == "query viewer")
        #expect(
            CommandLogText.graphQLOperation(
                "query($q0: String!) {\ns0: search(query: $q0, type: ISSUE, first: 30) { nodes { ...PR } }\n}\n"
                    + "fragment PR on PullRequest { number }") == "query search")
        #expect(
            CommandLogText.graphQLOperation("mutation($id: ID!) { markFileAsViewed(input: {}) { clientMutationId } }")
                == "mutation markFileAsViewed")
        #expect(
            CommandLogText.graphQLOperation("query { repository(owner: \"a\", name: \"b\") { id } viewer { login } }")
                == "query repository, viewer")
    }

    @Test func shortensLongArgumentsAndPreviews() {
        let line = CommandLogText.commandLine("claude", ["-p", String(repeating: "x", count: 500)])
        #expect(line.count < 220)
        let preview = CommandLogText.preview(String(repeating: "a", count: 5_000))
        #expect(preview.hasPrefix(String(repeating: "a", count: 2_000)))
        #expect(preview.contains("in total"))
        #expect(CommandLogText.jsonPreview(Data(#"{"b":1,"a":[]}"#.utf8)) == "{\n  \"a\" : [\n\n  ],\n  \"b\" : 1\n}")
    }
}

/// The Commands panel must never show tokens or code.
struct ProcessLogEntryTests {
    private let git = URL(fileURLWithPath: "/usr/bin/git")

    private func entry(_ executable: URL, _ arguments: [String], stdout: String, exit: Int32 = 0) -> CommandLogEntry {
        ProcessLogEntry.make(
            ProcessLogEntry.Invocation(
                executable: executable, arguments: arguments, workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
                input: nil, started: .now),
            result: .success(ProcessResult(exitCode: exit, standardOutput: stdout, standardError: "")),
            isCancelled: false)
    }

    @Test func hidesTokens() {
        let gh = entry(URL(fileURLWithPath: "/opt/homebrew/bin/gh"), ["auth", "token"], stdout: "gho_secret123")
        #expect(gh.response?.contains("gho_secret123") == false)
        #expect(gh.response?.contains("secret, not shown") == true)
        #expect(gh.kind == .process)
    }

    @Test func hidesCodeButShowsOtherGitOutput() {
        let diff = entry(git, ["diff", "HEAD~1"], stdout: "+let password = 1")
        #expect(diff.response?.contains("password") == false)
        let revParse = entry(git, ["rev-parse", "FETCH_HEAD"], stdout: "abc123")
        #expect(revParse.response == "abc123")
        #expect(revParse.kind == .git)
        #expect(revParse.title == "git rev-parse FETCH_HEAD")
        #expect(revParse.request == "in /tmp/repo")
    }

    @Test func marksFailures() {
        let failed = entry(git, ["fetch", "origin"], stdout: "", exit: 128)
        #expect(failed.isFailure)
        #expect(failed.status == "exit 128")
    }
}

@MainActor
struct CommandLogTests {
    @Test func keepsTheNewestEntries() {
        let log = CommandLog(limit: 3)
        for index in 0..<5 {
            log.append(
                CommandLogEntry(
                    kind: .git, title: "\(index)", startedAt: .now, duration: 0, status: "exit 0", isFailure: false))
        }
        #expect(log.entries.map(\.title) == ["2", "3", "4"])
        log.clear()
        #expect(log.entries.isEmpty)
    }
}
