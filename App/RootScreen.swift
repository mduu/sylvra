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
            PullRequestScreen(model: environment.pullRequest, pullRequest: selection)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            DiffScreen()
        }
        .navigationTitle(Text(verbatim: selection.map { "\($0.id.repository) #\($0.id.number)" } ?? "Sylvra"))
        .navigationSubtitle(Text(verbatim: selection?.title ?? ""))
        .inspector(isPresented: $isInspectorPresented) {
            FindingsInspectorScreen()
                .inspectorColumnWidth(min: 260, ideal: 300)
        }
        .onChange(of: environment.inbox.snapshot) {
            guard selection == nil, let wanted = environment.initialSelection else { return }
            selection = environment.inbox.snapshot.sections.values.joined().first { $0.id.description == wanted }
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
