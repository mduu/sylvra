import Foundation
import Testing

@testable import FeatureTerminal

@MainActor
private final class Processes: TerminalProcessHosting {
    var terminated: [UUID] = []
    func terminate(_ id: UUID) { terminated.append(id) }
}

/// Claude sessions survive a restart as tabs that can be continued; plain shells don't.
@MainActor
struct ClaudeSessionRestoreTests {
    private let defaults = UserDefaults(suiteName: "restore-\(UUID().uuidString)")!

    @Test func claudeTabsComeBackAfterARestart() {
        let before = TerminalModel(host: Processes(), defaults: defaults)
        let home = FileManager.default.temporaryDirectory
        before.openTab(title: "zsh", directory: home)
        before.openTab(title: "Claude · #812", directory: home, command: "claude", isClaude: true)

        let after = TerminalModel(host: Processes(), defaults: defaults)
        #expect(after.sessions.map(\.title) == ["Claude · #812"])
        #expect(after.sessions.first?.isRestored == true)
        #expect(after.sessions.first?.directory == home)
        #expect(after.isPresented == false)
    }

    @Test func aTabClaudeCodeNamesIsRememberedToo() {
        let model = TerminalModel(host: Processes(), defaults: defaults)
        let id = model.openTab(title: "zsh")
        model.updateTitle("✳ Claude Code", of: id)
        #expect(TerminalModel(host: Processes(), defaults: defaults).sessions.count == 1)
    }

    @Test func continuingRunsClaudeContinueInTheSameFolder() throws {
        let before = TerminalModel(host: Processes(), defaults: defaults)
        before.openTab(title: "Claude · #812", directory: FileManager.default.temporaryDirectory, isClaude: true)
        let model = TerminalModel(host: Processes(), defaults: defaults)
        let restored = try #require(model.sessions.first)
        model.resume(restored.id)
        let session = try #require(model.sessions.first)
        #expect(model.sessions.count == 1)
        #expect(session.command == "claude --continue")
        #expect(session.directory == restored.directory)
        #expect(!session.isRestored)
        #expect(model.selectedID == session.id)
        #expect(model.isPresented)
    }

    @Test func aMissingFolderIsReported() throws {
        let before = TerminalModel(host: Processes(), defaults: defaults)
        before.openTab(title: "Claude", directory: URL(fileURLWithPath: "/nonexistent-\(UUID())"), isClaude: true)
        let model = TerminalModel(host: Processes(), defaults: defaults)
        model.resume(try #require(model.sessions.first).id)
        #expect(model.errorMessage != nil)
        #expect(model.sessions.first?.isRestored == true)
    }

    @Test func closingForgetsIt() throws {
        let before = TerminalModel(host: Processes(), defaults: defaults)
        let id = before.openTab(title: "Claude", isClaude: true)
        before.closeTab(id)
        #expect(TerminalModel(host: Processes(), defaults: defaults).sessions.isEmpty)
    }
}
