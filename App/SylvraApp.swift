import AppKit
import DesignSystem
import FeatureAIReview
import FeatureActivity
import FeatureOpenInIDE
import FeatureSettings
import Platform
import SwiftUI

/// App entry point. The `App` target is the composition root: it wires the feature slices together.
@main
struct SylvraApp: App {
    @State private var environment = AppEnvironment()
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.auto.rawValue
    @AppStorage(AITextSize.storageKey) private var aiTextSize = AITextSize.standard.rawValue

    /// `--appearance=light|dark` overrides the setting (screenshots).
    private let launchAppearance = CommandLine.arguments.first { $0.hasPrefix("--appearance=") }
        .flatMap { AppearanceSetting(rawValue: String($0.dropFirst("--appearance=".count))) }

    init() {
        ProcessSignals.ignoreBrokenPipes()
        ScrollerPreference.apply()
        WindowLayout.applyLaunchArgument()
        Self.expandReadingOrderIfAsked()
        DisplaySetupMonitor.shared.start()
    }

    /// `--expand-reading-order` (screenshots): the AI summary's reading order starts expanded, for this launch.
    private static func expandReadingOrderIfAsked(
        _ arguments: [String] = CommandLine.arguments, defaults: UserDefaults = .standard
    ) {
        guard arguments.contains("--expand-reading-order") else { return }
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        domain["aiReadingOrderExpanded"] = true
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    var body: some Scene {
        // One main window: the feature models are shared, so a second window would show mixed state.
        Window("Sylvra", id: "main") {
            RootScreen(environment: environment)
                .onAppear {
                    // Demo / screenshot launches start from a terminal: come to the front, otherwise macOS keeps
                    // the window ordered out while someone works in another app and it can't be captured.
                    if environment.isDemo { NSApplication.shared.activate() }
                }
                .preferredColorScheme(
                    launchAppearance?.colorScheme ?? AppearanceSetting(rawValue: appearance)?.colorScheme
                )
                .environment(\.aiTextScale, AITextSize(rawValue: aiTextSize)?.scale ?? 1)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            ReviewCommands()
            TerminalCommands(terminal: environment.terminal, panel: environment.bottomPanel)
            CommandLogCommands(panel: environment.bottomPanel)
            WindowLayoutCommands()
            DiagnosticCommands()
            WorktreeCommands(worktrees: environment.worktrees)
        }

        // The second window of the two-window layout: diff, AI and terminal for the selected pull request.
        Window("Sylvra Review", id: RootScreen.reviewWindowID) {
            RootScreen(environment: environment, role: .review)
                .preferredColorScheme(
                    launchAppearance?.colorScheme ?? AppearanceSetting(rawValue: appearance)?.colorScheme
                )
                .environment(\.aiTextScale, AITextSize(rawValue: aiTextSize)?.scale ?? 1)
        }
        .defaultSize(width: 1400, height: 900)

        DiagnosticLogWindow()

        Settings {
            SettingsScreen {
                AIReviewSettingsView(model: environment.aiReview)
            } notifications: {
                NotificationSettingsView(center: environment.activity)
            } terminal: {
                TerminalToolsSettingsPane(customTools: environment.customTools)
            } repositories: {
                RepositoriesSettingsPane(model: environment.worktrees)
            } worktrees: {
                WorktreesSettingsPane(model: environment.worktrees)
            }
            .preferredColorScheme(AppearanceSetting(rawValue: appearance)?.colorScheme)
        }
    }
}
