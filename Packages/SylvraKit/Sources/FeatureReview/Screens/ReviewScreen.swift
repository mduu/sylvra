import DesignSystem
import SwiftUI
import SylvraCore

/// Review layer around the diff (container): loads the threads of the selected PR, presents the submit sheet
/// and errors. *Submit review* sits in the window toolbar (`SubmitReviewToolbarButton`).
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

/// *Submit review* for the window toolbar (container); hidden until the review state is loaded.
public struct SubmitReviewToolbarButton: View {
    private let model: ReviewScreenModel
    private let pullRequestID: PullRequestID?

    public init(model: ReviewScreenModel, pullRequestID: PullRequestID?) {
        self.model = model
        self.pullRequestID = pullRequestID
    }

    public var body: some View {
        if pullRequestID != nil, model.snapshot != nil {
            SubmitReviewButton(
                pendingCount: model.pendingCount, hasPendingReview: model.hasPendingReview,
                isComposing: model.draft != nil
            ) {
                model.isSubmitSheetPresented = true
            }
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
