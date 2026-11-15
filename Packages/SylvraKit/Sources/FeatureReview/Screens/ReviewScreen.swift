import SwiftUI

/// Placeholder for the Review screen (container: will own state and side effects).
public struct ReviewScreen: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("Review", systemImage: "text.bubble", description: Text("Coming soon"))
    }
}

#Preview {
    ReviewScreen()
}
