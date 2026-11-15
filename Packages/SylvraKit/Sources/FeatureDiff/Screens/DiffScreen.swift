import SwiftUI

/// Placeholder for the Diff screen (container: will own state and side effects).
public struct DiffScreen: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("Diff", systemImage: "plus.forwardslash.minus", description: Text("Coming soon"))
    }
}

#Preview {
    DiffScreen()
}
