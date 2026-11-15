import SwiftUI
import SylvraCore

/// Review threads and the comment composer below one diff line (container).
/// Placed into the diff through `DiffScreen`'s `lineAccessory` slot by the app; renders nothing for lines
/// without threads or draft.
public struct ReviewThreadsPanel: View {
    @Bindable private var model: ReviewScreenModel
    private let location: CodeLocation
    @Environment(\.openURL) private var openURL

    public init(model: ReviewScreenModel, location: CodeLocation) {
        self.model = model
        self.location = location
    }

    public var body: some View {
        let threads = model.threads(at: location)
        let hasDraft = model.isDraftAnchored(at: location)
        if !threads.isEmpty || hasDraft {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(threads) { thread in
                    ReviewThreadView(
                        thread: thread,
                        isCollapsed: model.isCollapsed(thread),
                        isWorking: model.isWorking,
                        replyText: replyBinding(thread),
                        editTexts: editBindings(thread),
                        actions: actions(thread)
                    )
                    .animation(.snappy, value: model.isCollapsed(thread))
                }
                if hasDraft { composer }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var composer: some View {
        CommentComposerView(
            location: model.draft?.location ?? location,
            text: Binding(get: { model.draft?.body ?? "" }, set: { model.draft?.body = $0 }),
            hasPendingReview: model.hasPendingReview,
            isWorking: model.isWorking,
            insertSuggestion: model.insertSuggestion,
            addToReview: { Task { await model.addDraftToReview() } },
            commentNow: { Task { await model.postDraftNow() } },
            cancel: { withAnimation(.snappy) { model.cancelDraft() } }
        )
    }

    private func replyBinding(_ thread: ReviewThread) -> Binding<String> {
        Binding(get: { model.replyDrafts[thread.id] ?? "" }, set: { model.replyDrafts[thread.id] = $0 })
    }

    private func editBindings(_ thread: ReviewThread) -> [String: Binding<String>] {
        var bindings: [String: Binding<String>] = [:]
        for comment in thread.comments where model.editDrafts[comment.id] != nil {
            bindings[comment.id] = Binding(
                get: { model.editDrafts[comment.id] ?? "" }, set: { model.editDrafts[comment.id] = $0 })
        }
        return bindings
    }

    private func actions(_ thread: ReviewThread) -> ReviewThreadActions {
        ReviewThreadActions(
            toggleCollapsed: { withAnimation(.snappy) { model.toggleCollapsed(thread) } },
            reply: { Task { await model.reply(to: thread) } },
            setResolved: { resolved in Task { await model.setResolved(resolved, thread: thread) } },
            beginEditing: model.beginEditing,
            cancelEditing: model.cancelEditing,
            saveEdit: { comment in Task { await model.saveEdit(of: comment) } },
            delete: { comment in Task { await model.delete(comment) } },
            open: { openURL($0) }
        )
    }
}

#Preview {
    let model = ReviewScreenModel(service: DemoReviewService())
    ScrollView {
        ReviewThreadsPanel(
            model: model, location: CodeLocation(path: "Sources/Billing/InvoiceService.swift", line: 9, side: .right))
    }
    .task { await model.load(PullRequestID(owner: "acme", repository: "billing", number: 1234)) }
    .frame(width: 700, height: 400)
}
