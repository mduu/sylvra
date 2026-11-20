import DesignSystem
import SwiftUI
import SylvraCore

/// The settings window. Feature-specific panes are provided by the app (slices don't import each other).
public struct SettingsScreen<
    AIPane: View, NotificationsPane: View, TerminalPane: View, RepositoriesPane: View, WorktreesPane: View
>: View {
    private let aiPane: AIPane
    private let notificationsPane: NotificationsPane
    private let terminalPane: TerminalPane
    private let repositoriesPane: RepositoriesPane
    private let worktreesPane: WorktreesPane

    public init(
        @ViewBuilder ai: () -> AIPane, @ViewBuilder notifications: () -> NotificationsPane,
        @ViewBuilder terminal: () -> TerminalPane,
        @ViewBuilder repositories: () -> RepositoriesPane, @ViewBuilder worktrees: () -> WorktreesPane
    ) {
        aiPane = ai()
        notificationsPane = notifications()
        terminalPane = terminal()
        repositoriesPane = repositories()
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
            if RepositoriesPane.self != EmptyView.self {
                Tab("Repositories", systemImage: "folder") { repositoriesPane }
            }
            if WorktreesPane.self != EmptyView.self {
                Tab("Worktrees", systemImage: "arrow.triangle.branch") { worktreesPane }
            }
        }
        .frame(width: 520)
        .frame(minHeight: 520)
    }
}

extension SettingsScreen where TerminalPane == EmptyView, RepositoriesPane == EmptyView, WorktreesPane == EmptyView {
    public init(@ViewBuilder ai: () -> AIPane, @ViewBuilder notifications: () -> NotificationsPane) {
        self.init(
            ai: ai, notifications: notifications, terminal: { EmptyView() }, repositories: { EmptyView() },
            worktrees: { EmptyView() })
    }
}

/// Appearance, languages and updates.
struct GeneralSettingsView: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.auto.rawValue
    @AppStorage("commentLanguage") private var commentLanguage = "English"
    @AppStorage(AITextSize.storageKey) private var aiTextSize = AITextSize.standard.rawValue
    @AppStorage(UpdatePreferences.automaticChecksKey) private var checksForUpdates = true

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
                Toggle("Check for updates automatically", isOn: $checksForUpdates)
                    .help("Looks for new releases on GitHub at launch and every few hours")
            }
        }
        .formStyle(.grouped)
    }
}
