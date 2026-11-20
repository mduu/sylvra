import Foundation
import Platform
import Testing

@testable import FeatureUpdates

/// Answers like the real tools; `hdiutil attach` puts an app into the mount point, `ditto` creates the copy.
actor FakeTools: ProcessRunning {
    var failing: String?
    var team = SystemUpdateInstaller.teamIdentifier
    private(set) var calls: [[String]] = []

    init(failing: String? = nil, team: String = SystemUpdateInstaller.teamIdentifier) {
        self.failing = failing
        self.team = team
    }

    func run(_ executable: URL, arguments: [String], workingDirectory: URL?, input: Data?) async throws
        -> ProcessResult
    {
        let tool = executable.lastPathComponent
        calls.append([tool] + arguments)
        if tool == failing { return ProcessResult(exitCode: 3, standardOutput: "", standardError: "rejected") }
        if tool == "hdiutil", arguments.first == "attach", let index = arguments.firstIndex(of: "-mountpoint") {
            try FileManager.default.createDirectory(
                at: URL(filePath: arguments[index + 1]).appending(path: "Sylvra.app"),
                withIntermediateDirectories: true)
        }
        if tool == "ditto", let target = arguments.last {
            try FileManager.default.createDirectory(at: URL(filePath: target), withIntermediateDirectories: true)
        }
        if tool == "codesign", arguments.first == "-dv" {
            return ProcessResult(
                exitCode: 0, standardOutput: "", standardError: "Identifier=x\nTeamIdentifier=\(team)\n")
        }
        return ProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

struct SystemUpdateInstallerTests {
    static func applications() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "updates-\(UUID().uuidString)/Applications")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func stagesAVerifiedAppNextToTheRunningOne() async throws {
        let folder = try Self.applications()
        let tools = FakeTools()
        let installer = SystemUpdateInstaller(runner: tools, appURL: folder.appending(path: "Sylvra.app"))
        #expect(installer.canReplaceApp)

        let staged = try await installer.prepare(diskImage: URL(filePath: "/tmp/Sylvra-0.5.36.dmg"))
        #expect(staged.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(staged.lastPathComponent.hasPrefix(".Sylvra-update-"))

        let order = await tools.calls.map(\.first)
        #expect(order.prefix(3) == ["codesign", "spctl", "hdiutil"])
        #expect(await tools.calls.contains { $0.first == "spctl" && $0.contains("execute") })
    }

    @Test func refusesADiskImageThatIsNotNotarized() async throws {
        let tools = FakeTools(failing: "spctl")
        let installer = SystemUpdateInstaller(
            runner: tools, appURL: try Self.applications().appending(path: "Sylvra.app"))
        await #expect(throws: UpdateError.notTrusted("not notarized: rejected")) {
            try await installer.prepare(diskImage: URL(filePath: "/tmp/Sylvra.dmg"))
        }
        #expect(await !tools.calls.contains { $0.first == "hdiutil" })
    }

    @Test func refusesAnAppOfAnotherTeam() async throws {
        let tools = FakeTools(team: "ABCDE12345")
        let installer = SystemUpdateInstaller(
            runner: tools, appURL: try Self.applications().appending(path: "Sylvra.app"))
        await #expect(throws: UpdateError.notTrusted("signed by another team")) {
            try await installer.prepare(diskImage: URL(filePath: "/tmp/Sylvra.dmg"))
        }
        #expect(await !tools.calls.contains { $0.first == "ditto" })
    }

    @Test func cannotReplaceAnAppOutsideApplications() {
        let installer = SystemUpdateInstaller(
            runner: FakeTools(), appURL: FileManager.default.temporaryDirectory.appending(path: "Sylvra.app"))
        #expect(!installer.canReplaceApp)
    }
}
