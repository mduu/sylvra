import SwiftUI

/// Placeholder for the Settings screen (container: will own state and side effects).
public struct SettingsScreen: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("Settings", systemImage: "gearshape", description: Text("Coming soon"))
    }
}

#Preview {
    SettingsScreen()
}
