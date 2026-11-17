import DesignSystem
import SwiftUI
import SylvraCore

/// One entry of the pull request conversation (pure): a comment or review card with reactions and the
/// comment menu, or a slim line for a review without text ("approved these changes").
struct ConversationEntryView: View {
    let entry: ConversationEntry
    let editText: Binding<String>?
    let isWorking: Bool
    let actions: ReviewThreadActions

    var body: some View {
        if entry.isEvent {
            eventLine
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if case .review(let state) = entry.kind {
                    Label(Self.title(of: state), systemImage: Self.symbol(of: state))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Self.tint(of: state))
                }
                ReviewCommentView(comment: entry.comment, editText: editText, isWorking: isWorking, actions: actions)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var eventLine: some View {
        HStack(spacing: 6) {
            if case .review(let state) = entry.kind {
                Image(systemName: Self.symbol(of: state)).foregroundStyle(Self.tint(of: state))
                AvatarView(entry.comment.author, size: 16)
                Text(verbatim: "\(entry.comment.author.displayName) \(Self.event(of: state))").lineLimit(1)
            }
            Text(entry.comment.createdAt, format: .relative(presentation: .named))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 10)
    }

    static func title(of state: ConversationEntry.ReviewState) -> String {
        switch state {
        case .approved: String(localized: "Approved")
        case .changesRequested: String(localized: "Requested changes")
        case .commented: String(localized: "Reviewed")
        case .dismissed: String(localized: "Review dismissed")
        }
    }

    static func event(of state: ConversationEntry.ReviewState) -> String {
        switch state {
        case .approved: String(localized: "approved these changes")
        case .changesRequested: String(localized: "requested changes")
        case .commented: String(localized: "reviewed")
        case .dismissed: String(localized: "had a review dismissed")
        }
    }

    static func symbol(of state: ConversationEntry.ReviewState) -> String {
        switch state {
        case .approved: "checkmark.circle.fill"
        case .changesRequested: "exclamationmark.circle.fill"
        case .commented: "eye.circle"
        case .dismissed: "xmark.circle"
        }
    }

    static func tint(of state: ConversationEntry.ReviewState) -> Color {
        switch state {
        case .approved: .green
        case .changesRequested: .red
        case .commented, .dismissed: .secondary
        }
    }
}

/// The field for a new conversation comment (pure): Markdown with preview and the tone check.
struct ConversationComposerView: View {
    @Binding var text: String
    let isWorking: Bool
    /// Changes when the cursor should go into the field (after *Quote reply*).
    let focusRequest: Int
    let post: () -> Void

    @State private var isPreviewing = false
    @FocusState private var isFocused: Bool

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var toneIssues: [ToneCheck.Issue] { isPreviewing ? [] : ToneCheck.issues(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $isPreviewing) {
                Text("Write").tag(false)
                Text("Preview").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            Group {
                if isPreviewing {
                    MarkdownBodyView(markdown: isEmpty ? "_Nothing to preview_" : text)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                        .padding(8)
                } else {
                    TextEditor(text: $text)
                        .font(.callout)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .frame(minHeight: 60, maxHeight: 220)
                        .padding(4)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Add a comment — Markdown supported")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            if !toneIssues.isEmpty {
                ToneHintView(issues: toneIssues)
            }
            HStack {
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("Comment", action: post)
                    .buttonStyle(.borderedProminent)
                    .tint(SylvraColor.brandPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isEmpty || isWorking)
                    .help("Post this comment on the pull request (⌘↩)")
            }
            .controlSize(.small)
        }
        .onChange(of: focusRequest) {
            isPreviewing = false
            isFocused = true
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    VStack(alignment: .leading, spacing: 12) {
        ForEach(DemoConversationService.sample().entries) { entry in
            ConversationEntryView(entry: entry, editText: nil, isWorking: false, actions: ReviewThreadActions())
        }
        ConversationComposerView(text: $text, isWorking: false, focusRequest: 0, post: {})
    }
    .padding()
    .frame(width: 380)
}
