import FeatureSettings
import SwiftUI

/// App entry point. The `App` target is the composition root: it wires the feature slices together.
@main
struct SylvraApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootScreen(environment: environment)
        }
        .defaultSize(width: 1440, height: 900)

        Settings {
            SettingsScreen()
        }
    }
}
