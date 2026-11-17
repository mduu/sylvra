import DesignSystem
import SwiftUI
import SylvraCore

/// The pull request conversation (container): comments and reviews oldest first like on GitHub, with
/// reactions, *Quote reply*, editing and a field for a new comment. Reloads every minute while shown.
public struct ConversationPanel: View {
    @Bindable private var model: ConversationModel
    private let pullRequestID: PullRequestID?
    /// Called after the reviewer posted or deleted a comment (e.g. to update the comment count).
    private let didChange: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var entryToDelete: ConversationEntry?

    private static let composerID = "conversation-composer"

    public init(model: ConversationModel, pullRequestID: PullRequestID?, didChange: @escaping () -> Void = {}) {
        self.model = model
        self.pullRequestID = pullRequestID
        self.didChange = didChange
    }

    public var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                header
                content
                if model.conversation != nil {
                    ConversationComposerView(
                        text: $model.draft, isWorking: model.isWorking, focusRequest: model.composerFocusRequest,
                        post: post
                    )
                    .id(Self.composerID)
                    .padding(.top, 4)
                }
            }
            .onChange(of: model.composerFocusRequest) {
                withAnimation(.snappy) { proxy.scrollTo(Self.composerID, anchor: .bottom) }
            }
        }
        .animation(.snappy, value: model.entries)
        .task(id: pullRequestID) {
            await model.load(pullRequestID)
            await model.keepRefreshing()
        }
        .confirmationDialog(
            "Delete this comment?", isPresented: deleteBinding, presenting: entryToDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                Task {
                    await model.delete(entry)
                    didChange()
                }
            }
        } message: { _ in
            Text("It is removed from the pull request on GitHub.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let updated = model.lastUpdated {
                Text("Updated \(updated, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.mini) }
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing)
                .help("Load new comments (also happens every minute on its own)")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.loadState {
        case .loading where model.conversation == nil:
            ProgressView().frame(maxWidth: .infinity)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Couldn't load the conversation", systemImage: "exclamationmark.triangle")
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Try again") { Task { await model.refresh() } }
            }
        default:
            if model.entries.isEmpty {
                Text("No comments yet").foregroundStyle(.secondary)
            }
            ForEach(model.entries) { entry in
                ConversationEntryView(
                    entry: entry, editText: editBinding(for: entry), isWorking: model.isWorking,
                    actions: actions(for: entry))
            }
        }
    }

    private func actions(for entry: ConversationEntry) -> ReviewThreadActions {
        ReviewThreadActions(
            beginEditing: { _ in model.beginEditing(entry) },
            cancelEditing: { _ in model.cancelEditing(entry) },
            saveEdit: { _ in Task { await model.saveEdit(of: entry) } },
            delete: { _ in entryToDelete = entry },
            react: { reaction, _ in Task { await model.toggleReaction(reaction, on: entry) } },
            open: { openURL($0) },
            quoteReply: entry.comment.body.isEmpty ? nil : { _ in model.quoteReply(to: entry) },
            canDelete: { _ in entry.canDelete }
        )
    }

    private func editBinding(for entry: ConversationEntry) -> Binding<String>? {
        guard model.editDrafts[entry.id] != nil else { return nil }
        return Binding(get: { model.editDrafts[entry.id] ?? "" }, set: { model.editDrafts[entry.id] = $0 })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } })
    }

    private func post() {
        Task {
            await model.post()
            didChange()
        }
    }
}

#Preview {
    ScrollView {
        ConversationPanel(
            model: ConversationModel(service: DemoConversationService()),
            pullRequestID: PullRequestID(owner: "acme", repository: "billing", number: 1234)
        )
        .padding()
    }
    .frame(width: 380, height: 640)
}
