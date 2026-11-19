import DesignSystem
import SwiftUI

/// The settings window. Feature-specific panes are provided by the app (slices don't import each other).
public struct SettingsScreen<AIPane: View, NotificationsPane: View, TerminalPane: View, WorktreesPane: View>: View {
    private let aiPane: AIPane
    private let notificationsPane: NotificationsPane
    private let terminalPane: TerminalPane
    private let worktreesPane: WorktreesPane

    public init(
        @ViewBuilder ai: () -> AIPane, @ViewBuilder notifications: () -> NotificationsPane,
        @ViewBuilder terminal: () -> TerminalPane, @ViewBuilder worktrees: () -> WorktreesPane
    ) {
        aiPane = ai()
        notificationsPane = notifications()
        terminalPane = terminal()
        worktreesPane = worktrees()
    }

    public var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("AI", systemImage: "sparkles") { aiPane }
            Tab("Notifications", systemImage: "bell") { notificationsPane }
            if TerminalPane.self != EmptyView.self {
                Tab("Terminal & Tools", systemImage: "terminal") { terminalPane }
            }
            if WorktreesPane.self != EmptyView.self {
                Tab("Worktrees", systemImage: "folder") { worktreesPane }
            }
        }
        .frame(width: 520)
        .frame(minHeight: 360)
    }
}

extension SettingsScreen where TerminalPane == EmptyView, WorktreesPane == EmptyView {
    public init(@ViewBuilder ai: () -> AIPane, @ViewBuilder notifications: () -> NotificationsPane) {
        self.init(ai: ai, notifications: notifications, terminal: { EmptyView() }, worktrees: { EmptyView() })
    }
}

/// Appearance and languages.
struct GeneralSettingsView: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.auto.rawValue
    @AppStorage("commentLanguage") private var commentLanguage = "English"
    @AppStorage(AITextSize.storageKey) private var aiTextSize = AITextSize.standard.rawValue

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Picker("AI text size", selection: $aiTextSize) {
                ForEach(AITextSize.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .help("Chat, findings and the AI summary")
            Picker("Language of GitHub comments", selection: $commentLanguage) {
                ForEach(["English", "German", "French", "Italian", "Spanish"], id: \.self) { Text($0).tag($0) }
            }
            Section {
                LabeledContent("Version") {
                    Text(verbatim: AppVersion.display()).textSelection(.enabled).monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
    }
}
