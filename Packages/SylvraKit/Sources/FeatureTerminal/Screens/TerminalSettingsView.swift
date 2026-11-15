import SwiftUI

/// Shell and external terminal settings (a `Form` section; the app places it in the "Terminal & Tools" pane).
public struct TerminalSettingsView: View {
    @AppStorage(TerminalPreferences.shellKey) private var shell = ""
    @AppStorage(TerminalPreferences.externalTerminalKey) private var externalApp = ""
    @State private var usesCustomApp = false

    public init() {}

    public var body: some View {
        Section("Terminal") {
            TextField("Shell", text: $shell, prompt: Text(ShellLaunch.loginShell()))
                .help("Leave empty to use your login shell.")
            Picker("External terminal", selection: appSelection) {
                ForEach(ExternalTerminal.presets) { Text($0.name).tag($0.bundleIdentifier) }
                Text("Other…").tag(Self.other)
            }
            if usesCustomApp || !isPreset {
                TextField("Bundle identifier", text: $externalApp, prompt: Text(verbatim: "com.example.Terminal"))
            }
        }
    }

    private static let other = "other"

    private var isPreset: Bool {
        externalApp.isEmpty || ExternalTerminal.presets.contains { $0.bundleIdentifier == externalApp }
    }

    private var appSelection: Binding<String> {
        Binding(
            get: {
                if usesCustomApp || !isPreset { return Self.other }
                return externalApp.isEmpty ? ExternalTerminal.terminal.bundleIdentifier : externalApp
            },
            set: { value in
                usesCustomApp = value == Self.other
                if !usesCustomApp { externalApp = value }
            })
    }
}

#Preview {
    Form { TerminalSettingsView() }
        .formStyle(.grouped)
}
