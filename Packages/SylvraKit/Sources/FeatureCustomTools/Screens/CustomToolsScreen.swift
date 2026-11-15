import SwiftUI

/// Placeholder for the Custom Tools screen (container: will own state and side effects).
public struct CustomToolsScreen: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("Custom Tools", systemImage: "wrench.and.screwdriver", description: Text("Coming soon"))
    }
}

#Preview {
    CustomToolsScreen()
}
