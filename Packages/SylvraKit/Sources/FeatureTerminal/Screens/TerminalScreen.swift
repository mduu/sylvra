import SwiftUI

/// Placeholder for the Terminal screen (container: will own state and side effects).
public struct TerminalScreen: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("Terminal", systemImage: "terminal", description: Text("Coming soon"))
    }
}

#Preview {
    TerminalScreen()
}
