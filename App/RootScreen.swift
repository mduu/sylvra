import FeatureAIReview
import FeatureDiff
import FeatureInbox
import FeatureOpenInIDE
import FeaturePullRequest
import SwiftUI
import SylvraCore

/// Main window layout: inbox · pull request · diff, with the AI inspector on the right.
/// Composes feature slices — slices themselves never import each other.
struct RootScreen: View {
    let environment: AppEnvironment
    @State private var selection: PullRequestSummary?
    @State private var isInspectorPresented: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility

    init(environment: AppEnvironment) {
        self.environment = environment
        _isInspectorPresented = State(initialValue: environment.showsInspector)
        _columnVisibility = State(initialValue: environment.startsFocused ? .doubleColumn : .all)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            InboxScreen(model: environment.inbox, selection: $selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290)
        } content: {
            PullRequestScreen(model: environment.pullRequest, pullRequest: selection) {
                DiffFileNavigatorPanel(model: environment.diff)
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            DiffScreen(
                model: environment.diff,
                pullRequestID: selection?.id,
                headSHA: environment.pullRequest.detail.flatMap { $0.summary.id == selection?.id ? $0.headSHA : nil }
            )
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
        .overlay(alignment: .bottom) {
            OpenInIDEStatusToast(status: environment.openInIDE.status)
                .padding(.bottom, 16)
                .animation(.snappy, value: environment.openInIDE.status)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                OpenInIDEToolbarPanel(model: environment.openInIDE, pullRequestID: selection?.id)
            }
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
