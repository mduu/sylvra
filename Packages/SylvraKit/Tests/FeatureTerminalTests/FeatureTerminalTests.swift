import Foundation
import Testing

@testable import FeatureTerminal

@MainActor
private final class FakeHost: TerminalProcessHosting {
    var terminated: [UUID] = []
    func terminate(_ id: UUID) { terminated.append(id) }
}

@MainActor
private final class FakeOpener: ExternalTerminalOpening {
    var opened: [(URL, String)] = []
    var error: (any Error)?
    func open(_ directory: URL, bundleIdentifier: String) async throws {
        if let error { throw error }
        opened.append((directory, bundleIdentifier))
    }
}

@MainActor
struct TerminalModelTests {
    private let home = URL(fileURLWithPath: "/Users/test")
    private let host = FakeHost()
    private let opener = FakeOpener()
    private let defaults = UserDefaults(suiteName: "sylvra-terminal-\(UUID().uuidString)")!

    private func makeModel() -> TerminalModel {
        TerminalModel(defaultDirectory: home, host: host, opener: opener, defaults: defaults)
    }

    @Test func openTabUsesDefaultsAndSelects() {
        let model = makeModel()
        let first = model.openTab()
        #expect(model.isPresented)
        #expect(model.selectedSession?.directory == home)
        #expect(model.selectedSession?.title == "/Users/test")

        let worktree = URL(fileURLWithPath: "/tmp/worktree")
        let second = model.openTab(title: "Run tests", directory: worktree, command: "swift test")
        #expect(model.sessions.map(\.id) == [first, second])
        #expect(model.selectedSession?.command == "swift test")
        #expect(model.selectedSession?.directory == worktree)
    }

    @Test func closingSelectsNeighbourAndTerminates() {
        let model = makeModel()
        let a = model.openTab()
        let b = model.openTab()
        let c = model.openTab()
        model.selectedID = b
        model.closeTab(b)
        #expect(model.selectedID == c)
        #expect(host.terminated == [b])
        model.closeTab(c)
        #expect(model.selectedID == a)
        model.closeTab(a)
        #expect(model.sessions.isEmpty)
        #expect(!model.isPresented)
    }

    @Test func toggleOpensAFirstTabAndKeepsSessions() {
        let model = makeModel()
        model.toggle()
        #expect(model.isPresented)
        #expect(model.sessions.count == 1)
        model.toggle()
        #expect(!model.isPresented)
        #expect(model.sessions.count == 1)
        model.defaultDirectory = URL(fileURLWithPath: "/tmp/other")
        model.toggle()
        #expect(model.sessions.count == 1)
        #expect(host.terminated.isEmpty)
    }

    @Test func tracksTitlesAndExit() {
        let model = makeModel()
        let id = model.openTab()
        model.updateTitle("  vim  ", of: id)
        model.updateTitle("", of: id)
        model.markExited(id, code: 3)
        #expect(model.selectedSession?.title == "vim")
        #expect(model.selectedSession?.hasExited == true)
        #expect(model.selectedSession?.exitCode == 3)
    }

    @Test func externalTerminalUsesSettingAndSelectedDirectory() async {
        let model = makeModel()
        await model.openInExternalTerminal()
        #expect(opener.opened.last?.0 == home)
        #expect(opener.opened.last?.1 == "com.apple.Terminal")

        defaults.set("com.googlecode.iterm2", forKey: TerminalPreferences.externalTerminalKey)
        model.openTab(directory: URL(fileURLWithPath: "/tmp/w"))
        await model.openInExternalTerminal()
        #expect(opener.opened.last?.0.path == "/tmp/w")
        #expect(opener.opened.last?.1 == "com.googlecode.iterm2")
        #expect(model.externalTerminal.name == "iTerm2")

        opener.error = ExternalTerminalError.notInstalled("x")
        await model.openInExternalTerminal()
        #expect(model.errorMessage != nil)
    }

    @Test func shellSetting() {
        let model = makeModel()
        #expect(model.shell == ShellLaunch.loginShell())
        defaults.set("/opt/homebrew/bin/fish", forKey: TerminalPreferences.shellKey)
        #expect(model.shell == "/opt/homebrew/bin/fish")
    }
}

struct ShellLaunchTests {
    @Test func interactiveLoginShell() {
        let launch = ShellLaunch.make(shell: "/bin/zsh", command: nil, baseEnvironment: ["PATH": "/usr/bin"])
        #expect(launch.executable == "/bin/zsh")
        #expect(launch.arguments.isEmpty)
        #expect(launch.execName == "-zsh")
        #expect(launch.environment.contains("TERM=xterm-256color"))
        #expect(launch.environment.contains("PATH=/usr/bin"))
        #expect(launch.environment.contains("LANG=en_US.UTF-8"))
    }

    @Test func dropsVariablesOfTheSessionSylvraWasStartedFrom() {
        let launch = ShellLaunch.make(
            shell: "/bin/zsh", command: nil,
            baseEnvironment: [
                "PATH": "/usr/bin", "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "TMUX": "/tmp/tmux-501/default",
                "TMUX_PANE": "%1", "CLAUDE_CONFIG_DIR": "/Users/me/.claude",
            ])
        #expect(!launch.environment.contains { $0.hasPrefix("CLAUDECODE=") })
        #expect(!launch.environment.contains { $0.hasPrefix("CLAUDE_CODE_") })
        #expect(!launch.environment.contains { $0.hasPrefix("TMUX") })
        #expect(launch.environment.contains("CLAUDE_CONFIG_DIR=/Users/me/.claude"))
        #expect(launch.environment.contains("PATH=/usr/bin"))
    }

    @Test func commandIsPassedAsArgumentNotSpliced() {
        let launch = ShellLaunch.make(shell: "/bin/bash", command: "swift test '{x}'", baseEnvironment: [:])
        #expect(launch.executable == "/bin/bash")
        #expect(launch.arguments == ["-l", "-c", ShellLaunch.commandWrapper, "/bin/bash", "swift test '{x}'"])
    }

    @Test func nonPOSIXShellRunsCommandViaZsh() {
        let launch = ShellLaunch.make(
            shell: "/opt/homebrew/bin/fish", command: "ls", baseEnvironment: ["LANG": "de_CH"])
        #expect(launch.executable == "/bin/zsh")
        #expect(launch.arguments.suffix(2) == ["/opt/homebrew/bin/fish", "ls"])
        #expect(launch.environment.contains("LANG=de_CH"))
        #expect(launch.environment.contains("SHELL=/opt/homebrew/bin/fish"))
    }

    @Test func externalTerminalLookup() {
        #expect(ExternalTerminal.named("com.mitchellh.ghostty").name == "Ghostty")
        #expect(ExternalTerminal.named("org.example.term").name == "org.example.term")
    }
}

struct TerminalFontSizeTests {
    @Test func keepsStoredSizesWithinRange() {
        #expect(TerminalPreferences.fontSize(0) == TerminalPreferences.defaultFontSize)
        #expect(TerminalPreferences.fontSize(15) == 15)
        #expect(TerminalPreferences.fontSize(3) == TerminalPreferences.fontSizes.lowerBound)
        #expect(TerminalPreferences.fontSize(99) == TerminalPreferences.fontSizes.upperBound)
        #expect(TerminalPreferences.fontSize(13.6) == 14)
    }
}
