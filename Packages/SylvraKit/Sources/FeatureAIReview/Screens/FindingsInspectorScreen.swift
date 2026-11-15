import SwiftUI

/// Placeholder for the AI Findings screen (container: will own state and side effects).
public struct FindingsInspectorScreen: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("AI Findings", systemImage: "sparkles", description: Text("Coming soon"))
    }
}

#Preview {
    FindingsInspectorScreen()
}
