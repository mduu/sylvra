import FeatureAIReview
import FeatureDiff
import FeatureInbox
import FeaturePullRequest
import SwiftUI

/// Main window layout: inbox · pull request · diff, with the AI inspector on the right.
/// Composes feature slices — slices themselves never import each other.
struct RootScreen: View {
    @State private var isInspectorPresented = true

    var body: some View {
        NavigationSplitView {
            InboxScreen()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } content: {
            PullRequestScreen()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            DiffScreen()
        }
        .inspector(isPresented: $isInspectorPresented) {
            FindingsInspectorScreen()
                .inspectorColumnWidth(min: 260, ideal: 300)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("AI Inspector", systemImage: "sparkles")
                }
            }
        }
    }
}

#Preview {
    RootScreen()
}
