import SwiftUI

/// The settings window. Feature-specific panes are provided by the app (slices don't import each other).
public struct SettingsScreen<AIPane: View, NotificationsPane: View>: View {
    private let aiPane: AIPane
    private let notificationsPane: NotificationsPane

    public init(@ViewBuilder ai: () -> AIPane, @ViewBuilder notifications: () -> NotificationsPane) {
        aiPane = ai()
        notificationsPane = notifications()
    }

    public var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("AI", systemImage: "sparkles") { aiPane }
            Tab("Notifications", systemImage: "bell") { notificationsPane }
        }
        .frame(width: 520)
        .frame(minHeight: 360)
    }
}

/// Appearance and languages.
struct GeneralSettingsView: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.auto.rawValue
    @AppStorage("commentLanguage") private var commentLanguage = "English"

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Picker("Language of GitHub comments", selection: $commentLanguage) {
                ForEach(["English", "German", "French", "Italian", "Spanish"], id: \.self) { Text($0).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}
