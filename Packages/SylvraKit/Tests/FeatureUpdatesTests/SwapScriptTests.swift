import Foundation
import Testing

@testable import FeatureUpdates

/// Runs the real swap script on folders standing in for the apps; `open` is a stub that records its argument.
struct SwapScriptTests {
    struct Setup {
        let root: URL
        let target: URL
        let staged: URL
        var opened: URL { root.appending(path: "opened.txt") }
    }

    static func setup(stagedExists: Bool = true) throws -> Setup {
        let root = FileManager.default.temporaryDirectory.appending(path: "swap-\(UUID().uuidString)")
        let target = root.appending(path: "Applications/Sylvra.app")
        let staged = root.appending(path: "Applications/.Sylvra-update-1.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appending(path: "version"))
        if stagedExists {
            try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
            try Data("new".utf8).write(to: staged.appending(path: "version"))
        }
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let open = bin.appending(path: "open")
        try Data("#!/bin/sh\nprintf '%s' \"$1\" > \"\(root.path)/opened.txt\"\n".utf8).write(to: open)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: open.path)
        return Setup(root: root, target: target, staged: staged)
    }

    static func run(_ setup: Setup) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        // A process id that doesn't exist: the script doesn't wait.
        process.arguments = [
            "-c", SystemUpdateInstaller.swapScript, "sylvra-update", "99999999", setup.staged.path,
            setup.target.path,
        ]
        process.environment = ["PATH": setup.root.appending(path: "bin").path + ":/bin:/usr/bin"]
        try process.run()
        process.waitUntilExit()
    }

    static func version(at app: URL) throws -> String {
        String(decoding: try Data(contentsOf: app.appending(path: "version")), as: UTF8.self)
    }

    @Test func swapsInTheNewVersionAndOpensIt() throws {
        let setup = try Self.setup()
        try Self.run(setup)
        #expect(try Self.version(at: setup.target) == "new")
        #expect(!FileManager.default.fileExists(atPath: setup.staged.path))
        #expect(!FileManager.default.fileExists(atPath: setup.target.path + ".previous"))
        #expect(String(decoding: try Data(contentsOf: setup.opened), as: UTF8.self) == setup.target.path)
    }

    @Test func keepsTheOldVersionWhenTheNewOneIsMissing() throws {
        let setup = try Self.setup(stagedExists: false)
        try Self.run(setup)
        #expect(try Self.version(at: setup.target) == "old")
        #expect(!FileManager.default.fileExists(atPath: setup.target.path + ".previous"))
        #expect(FileManager.default.fileExists(atPath: setup.opened.path))
    }
}
