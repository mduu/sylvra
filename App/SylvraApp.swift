import FeatureSettings
import SwiftUI

/// App entry point. The `App` target is the composition root: it wires the feature slices together.
@main
struct SylvraApp: App {
    var body: some Scene {
        WindowGroup {
            RootScreen()
        }

        Settings {
            SettingsScreen()
        }
    }
}
