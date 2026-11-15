import SwiftUI

/// Placeholder for the Open in IDE screen (container: will own state and side effects).
public struct OpenInIDEScreen: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("Open in IDE", systemImage: "hammer", description: Text("Coming soon"))
    }
}

#Preview {
    OpenInIDEScreen()
}
