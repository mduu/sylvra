import DesignSystem
import SwiftUI
import SylvraCore

/// Review layer around the diff (container): loads the threads of the selected PR, shows the pending
/// review counter and *Submit review* in the toolbar, presents the submit sheet and errors.
/// `content` is the diff, provided by the app (slices don't import each other).
public struct ReviewScreen<Content: View>: View {
    @Bindable private var model: ReviewScreenModel
    private let pullRequestID: PullRequestID?
    private let content: Content

    public init(model: ReviewScreenModel, pullRequestID: PullRequestID?, @ViewBuilder content: () -> Content) {
        self.model = model
        self.pullRequestID = pullRequestID
        self.content = content()
    }

    public var body: some View {
        content
            .task(id: pullRequestID) {
                await model.load(pullRequestID)
                // Replies by others appear without reopening the pull request.
                await model.keepRefreshingThreads()
            }
            .toolbar {
                if pullRequestID != nil, model.snapshot != nil {
                    ToolbarItem(placement: .primaryAction) {
                        SubmitReviewButton(
                            pendingCount: model.pendingCount, hasPendingReview: model.hasPendingReview,
                            isComposing: model.draft != nil
                        ) {
                            model.isSubmitSheetPresented = true
                        }
                    }
                }
            }
            .sheet(isPresented: $model.isSubmitSheetPresented) {
                SubmitReviewSheet(model: model)
            }
            .alert(
                "Review action failed",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
    }
}

/// Toolbar button with the pending comment counter (pure).
struct SubmitReviewButton: View {
    let pendingCount: Int
    let hasPendingReview: Bool
    /// While a comment is being written, ⌘↩ belongs to the composer.
    var isComposing = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Submit review")
                if pendingCount > 0 {
                    Text(verbatim: "\(pendingCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(SylvraColor.brandPrimary, in: Capsule())
                        .contentTransition(.numericText())
                }
            }
        }
        .keyboardShortcut(isComposing ? nil : KeyboardShortcut(.return, modifiers: .command))
        .help(hasPendingReview ? "Submit your pending review (⌘↩)" : "Review this pull request (⌘↩)")
        .accessibilityLabel(Text("Submit review, \(pendingCount) pending comments"))
        .animation(.snappy, value: pendingCount)
    }
}

#Preview {
    SubmitReviewButton(pendingCount: 3, hasPendingReview: true) {}
        .padding()
}
