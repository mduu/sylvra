import SwiftUI

/// Placeholder for the Inbox screen (container: will own state and side effects).
public struct InboxScreen: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("Inbox", systemImage: "tray", description: Text("Coming soon"))
    }
}

#Preview {
    InboxScreen()
}
