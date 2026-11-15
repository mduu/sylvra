import FeatureAIReview
import FeatureDiff
import FeatureInbox
import FeaturePullRequest
import SwiftUI
import SylvraCore

/// Main window layout: inbox · pull request · diff, with the AI inspector on the right.
/// Composes feature slices — slices themselves never import each other.
struct RootScreen: View {
    let environment: AppEnvironment
    @State private var selection: PullRequestSummary?
    @State private var isInspectorPresented = true

    var body: some View {
        NavigationSplitView {
            InboxScreen(model: environment.inbox, selection: $selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290)
        } content: {
            PullRequestScreen()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            DiffScreen()
        }
        .navigationTitle(selection.map { "\($0.id.repository) #\($0.id.number)" } ?? "Sylvra")
        .navigationSubtitle(selection?.title ?? "")
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
    RootScreen(environment: AppEnvironment(arguments: ["--demo"]))
}
