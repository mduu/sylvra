import SwiftUI

/// Placeholder for the Activity screen (container: will own state and side effects).
public struct ActivityScreen: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("Activity", systemImage: "clock.arrow.circlepath", description: Text("Coming soon"))
    }
}

#Preview {
    ActivityScreen()
}
