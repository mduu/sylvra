import Foundation
import Testing

@testable import FeatureTerminal

struct ClaudeSessionCommandTests {
    @Test func readsThePromptDeletesItsFileAndStartsClaude() {
        let command = ClaudeSessionCommand.command(promptFile: URL(fileURLWithPath: "/tmp/sylvra-session-1.txt"))
        #expect(
            command
                == #"prompt="$(cat '/tmp/sylvra-session-1.txt')"; rm -f '/tmp/sylvra-session-1.txt'; claude "$prompt""#
        )
    }

    @Test func theExternalScriptDeletesItself() {
        let script = ClaudeSessionCommand.script(command: "claude", directory: URL(fileURLWithPath: "/w/it's"))
        #expect(script == "#!/bin/zsh -l\nrm -f \"$0\"\ncd '/w/it'\\''s' && claude\n")
    }

    @Test func runsTheCommandForReal() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "csc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "sylvra-session-x.txt")
        try "Why did \"prod\" fail? $(rm -rf /)".write(to: file, atomically: true, encoding: .utf8)
        // `claude` replaced by printf: the prompt arrives as one argument, unexpanded, and the file is gone.
        let command = ClaudeSessionCommand.command(promptFile: file).replacingOccurrences(
            of: "claude ", with: "printf %s ")
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output == "Why did \"prod\" fail? $(rm -rf /)")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func removesOnlyOldSessionFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "csc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appending(path: "sylvra-session-old.txt")
        let fresh = directory.appending(path: "sylvra-session-new.command")
        let other = directory.appending(path: "other.txt")
        for file in [old, fresh, other] { try "x".write(to: file, atomically: true, encoding: .utf8) }
        let twoDaysAgo = Date.now.addingTimeInterval(-2 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: other.path)
        await ClaudeSessionCommand.removeLeftovers(in: directory)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}
