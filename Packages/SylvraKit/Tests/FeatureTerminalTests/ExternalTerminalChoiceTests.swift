import Foundation
import Testing

@testable import FeatureTerminal

@MainActor
private final class NoHost: TerminalProcessHosting {
    func terminate(_ id: UUID) {}
}

/// Choosing the external terminal right at the panel's button (Ghostty, iTerm2 … instead of Terminal).
@MainActor
struct ExternalTerminalChoiceTests {
    private let defaults = UserDefaults(suiteName: "external-\(UUID().uuidString)")!

    @Test func listsTheInstalledTerminalsAndRemembersTheChoice() {
        let model = TerminalModel(host: NoHost(), defaults: defaults)
        model.isInstalled = { ["com.apple.Terminal", "com.mitchellh.ghostty"].contains($0) }
        #expect(model.installedExternalTerminals.map(\.name) == ["Terminal", "Ghostty"])
        #expect(model.externalTerminal == .terminal)

        model.externalTerminal = .named("com.mitchellh.ghostty")
        #expect(defaults.string(forKey: TerminalPreferences.externalTerminalKey) == "com.mitchellh.ghostty")
        #expect(TerminalModel(host: NoHost(), defaults: defaults).externalTerminal.name == "Ghostty")
    }

    @Test func aCustomAppFromTheSettingsIsListedToo() {
        defaults.set("org.alacritty", forKey: TerminalPreferences.externalTerminalKey)
        let model = TerminalModel(host: NoHost(), defaults: defaults)
        model.isInstalled = { $0 == "com.apple.Terminal" }
        #expect(model.installedExternalTerminals.map(\.bundleIdentifier) == ["com.apple.Terminal", "org.alacritty"])
    }
}
