import SwiftUI

/// Placeholder for the Pull Request screen (container: will own state and side effects).
public struct PullRequestScreen: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("Pull Request", systemImage: "arrow.triangle.pull", description: Text("Coming soon"))
    }
}

#Preview {
    PullRequestScreen()
}
