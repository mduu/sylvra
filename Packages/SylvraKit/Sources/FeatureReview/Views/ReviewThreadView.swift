import DesignSystem
import SwiftUI
import SylvraCore

/// Actions of a thread card, provided by its container.
struct ReviewThreadActions {
    var toggleCollapsed: () -> Void = {}
    var reply: () -> Void = {}
    var setResolved: (Bool) -> Void = { _ in }
    var beginEditing: (ReviewComment) -> Void = { _ in }
    var cancelEditing: (ReviewComment) -> Void = { _ in }
    var saveEdit: (ReviewComment) -> Void = { _ in }
    var delete: (ReviewComment) -> Void = { _ in }
    var open: (URL) -> Void = { _ in }
}

/// A review thread inline in the diff (pure): comments, reply field, resolve.
/// Resolved and outdated threads collapse into a slim line.
struct ReviewThreadView: View {
    let thread: ReviewThread
    let isCollapsed: Bool
    let isWorking: Bool
    @Binding var replyText: String
    /// Edited bodies per comment ID (only comments being edited have an entry).
    let editTexts: [String: Binding<String>]
    let actions: ReviewThreadActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCollapsed {
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(thread.comments) { comment in
                        ReviewCommentView(
                            comment: comment, editText: editTexts[comment.id], isWorking: isWorking,
                            actions: actions)
                    }
                }
                .padding(12)
                footer
            }
        }
        // Lives inside the code surface: a quiet card with a violet edge instead of a separate white box.
        .background(SylvraColor.codeGutter, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SylvraColor.codeHairline))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
                .fill(SylvraColor.brandPrimary.opacity(thread.isResolved ? 0.35 : 0.9))
                .frame(width: 3)
        }
    }

    private var header: some View {
        Button(action: actions.toggleCollapsed) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.secondary)
                if isCollapsed, let first = thread.comments.first {
                    AvatarView(first.author, size: 16)
                    Text(first.author.displayName).fontWeight(.medium).lineLimit(1).fixedSize()
                    Text(Self.preview(of: first.body)).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(Self.lineLabel(thread.location)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if thread.isOutdated { StatusBadge("Outdated", systemImage: "clock.arrow.circlepath", tint: .orange) }
                if thread.isResolved { StatusBadge("Resolved", systemImage: "checkmark.circle", tint: .green) }
                if thread.comments.count > 1 {
                    Label("\(thread.comments.count)", systemImage: "bubble.left.and.bubble.right")
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? Text("Expand thread") : Text("Collapse thread"))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if thread.viewerCanReply {
                TextField("Reply…", text: $replyText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...8)
                    .onSubmit(actions.reply)
            }
            HStack {
                if thread.viewerCanResolve {
                    Button(thread.isResolved ? "Unresolve" : "Resolve") { actions.setResolved(!thread.isResolved) }
                        .disabled(isWorking)
                }
                Spacer()
                if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Reply", action: actions.reply)
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)
                        .transition(.opacity)
                }
            }
            .controlSize(.small)
        }
        .padding([.horizontal, .bottom], 12)
        .animation(.snappy(duration: 0.15), value: replyText.isEmpty)
    }

    static func lineLabel(_ location: CodeLocation) -> String {
        let side = location.side == .left ? String(localized: "old") : String(localized: "new")
        if let start = location.startLine {
            return String(localized: "Lines \(start)–\(location.line) (\(side))")
        }
        return String(localized: "Line \(location.line) (\(side))")
    }

    static func preview(of body: String) -> String {
        body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}

/// One comment of a thread (pure).
struct ReviewCommentView: View {
    let comment: ReviewComment
    let editText: Binding<String>?
    let isWorking: Bool
    let actions: ReviewThreadActions

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(comment.author, size: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if comment.isPending { StatusBadge("Pending", tint: SylvraColor.brandPrimary) }
                    Spacer(minLength: 4)
                    menu
                }
                if let editText {
                    editor(editText)
                } else {
                    MarkdownBodyView(markdown: comment.body)
                }
            }
        }
    }

    private var menu: some View {
        Menu {
            if comment.viewerCanUpdate { Button("Edit") { actions.beginEditing(comment) } }
            if let url = comment.url { Button("Open on GitHub") { actions.open(url) } }
            if comment.viewerCanDelete {
                Divider()
                Button("Delete", role: .destructive) { actions.delete(comment) }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("Comment actions"))
    }

    private func editor(_ text: Binding<String>) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: text)
                .font(.callout)
                .frame(minHeight: 60, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack {
                Button("Cancel") { actions.cancelEditing(comment) }
                Button("Save") { actions.saveEdit(comment) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
            }
            .controlSize(.small)
        }
    }
}

/// Small capsule badge (resolved, outdated, pending).
struct StatusBadge: View {
    let title: LocalizedStringKey
    let systemImage: String?
    let tint: Color

    init(_ title: LocalizedStringKey, systemImage: String? = nil, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(tint.opacity(0.12), in: Capsule())
        .fixedSize()  // never wrap ("Re-solve-d") in narrow lanes
    }
}

#Preview {
    @Previewable @State var reply = ""
    let threads = DemoReviewService.sample().threads
    VStack(spacing: 12) {
        ForEach(threads) { thread in
            ReviewThreadView(
                thread: thread, isCollapsed: thread.isResolved, isWorking: false, replyText: $reply, editTexts: [:],
                actions: ReviewThreadActions())
        }
    }
    .padding()
    .frame(width: 560)
}
