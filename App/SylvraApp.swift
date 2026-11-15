import FeatureAIReview
import FeatureActivity
import FeatureSettings
import SwiftUI

/// App entry point. The `App` target is the composition root: it wires the feature slices together.
@main
struct SylvraApp: App {
    @State private var environment = AppEnvironment()
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.auto.rawValue

    var body: some Scene {
        WindowGroup {
            RootScreen(environment: environment)
                .preferredColorScheme(AppearanceSetting(rawValue: appearance)?.colorScheme)
        }
        .defaultSize(width: 1440, height: 900)
        .commands { ReviewCommands() }

        Settings {
            SettingsScreen {
                AIReviewSettingsView(model: environment.aiReview)
            } notifications: {
                NotificationSettingsView(center: environment.activity)
            }
            .preferredColorScheme(AppearanceSetting(rawValue: appearance)?.colorScheme)
        }
    }
}
