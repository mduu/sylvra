import DesignSystem
import SwiftUI
import SylvraCore

/// Comments of one section of the Comments tab (pure). Code comments jump to their line in the diff.
struct DiscussionListView: View {
    let items: [DiscussionItem]
    var showInCode: ((String, Int?) -> Void)?
    var open: (URL?) -> Void = { _ in }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            if items.isEmpty {
                Text("No comments here").foregroundStyle(.secondary).padding(.top, 4)
            }
            ForEach(items) { item in
                DiscussionRowView(item: item, showInCode: showInCode, open: open)
            }
        }
    }
}

/// One comment or code thread (pure).
struct DiscussionRowView: View {
    let item: DiscussionItem
    var showInCode: ((String, Int?) -> Void)?
    var open: (URL?) -> Void = { _ in }
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AvatarView(item.author, size: 18)
                Text(item.author.displayName).fontWeight(.semibold).lineLimit(1)
                Text(item.date, format: .relative(presentation: .named)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if item.url != nil {
                    Button("Open on GitHub", systemImage: "arrow.up.right.square") { open(item.url) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Open on GitHub")
                }
            }
            .font(.caption)
            placeLine
            Text(Self.markdown(item.body))
                .font(.callout)
                .lineLimit(isExpanded ? nil : 4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !item.replies.isEmpty || item.body.count > 240 {
                Button(isExpanded ? "Less" : moreTitle) { withAnimation(.snappy) { isExpanded.toggle() } }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if isExpanded {
                ForEach(Array(item.replies.enumerated()), id: \.offset) { _, reply in
                    replyView(reply)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .opacity(item.isResolved ? 0.6 : 1)
    }

    private var moreTitle: String {
        item.replies.isEmpty
            ? String(localized: "More") : String(localized: "Show \(item.replies.count) replies")
    }

    /// Where the comment belongs; code comments get a jump into the diff.
    @ViewBuilder private var placeLine: some View {
        switch item.place {
        case .conversation:
            Label("Conversation", systemImage: "bubble.left").font(.caption).foregroundStyle(.secondary)
        case .review:
            Label("Review", systemImage: "checkmark.bubble").font(.caption).foregroundStyle(.secondary)
        case .code(let path, let line, let isResolved):
            HStack(spacing: 6) {
                if let showInCode {
                    Button {
                        showInCode(path, line)
                    } label: {
                        Label(Self.location(path, line), systemImage: "chevron.left.forwardslash.chevron.right")
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .buttonStyle(.link)
                    .help(line == nil ? "Show the file (the commented code changed since)" : "Show in the diff")
                } else {
                    Label(Self.location(path, line), systemImage: "chevron.left.forwardslash.chevron.right")
                        .lineLimit(1)
                }
                if isResolved {
                    Text("Resolved").font(.caption2.weight(.semibold)).padding(.horizontal, 5)
                        .background(.quaternary, in: Capsule())
                }
                if line == nil {
                    Text("Outdated").font(.caption2.weight(.semibold)).padding(.horizontal, 5)
                        .background(.quaternary, in: Capsule())
                }
            }
            .font(.caption.monospaced())
        }
    }

    private func replyView(_ reply: DiscussionItem.Reply) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                AvatarView(reply.author, size: 16)
                Text(reply.author.displayName).fontWeight(.semibold)
                Text(reply.date, format: .relative(presentation: .named)).foregroundStyle(.secondary)
            }
            .font(.caption)
            Text(Self.markdown(reply.body)).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 2) }
    }

    static func location(_ path: String, _ line: Int?) -> String {
        line.map { "\(path):\($0)" } ?? path
    }

    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

#Preview {
    ScrollView {
        DiscussionListView(
            items: [
                DiscussionItem(
                    id: "1", place: .code(path: "Sources/Billing/InvoiceService.swift", line: 9, isResolved: false),
                    author: UserRef(login: "jmeier", name: "Jonas Meier"),
                    body: "Rounding each line can drift from the total. Round **once** at the end?",
                    date: .now.addingTimeInterval(-18_000),
                    replies: [
                        .init(
                            author: UserRef(login: "lkeller", name: "Lena Keller"),
                            body: "Accounting wants per-line rounding.", date: .now.addingTimeInterval(-10_800))
                    ]),
                DiscussionItem(
                    id: "2", place: .conversation, author: UserRef(login: "mduu", name: "Marc Dürst"),
                    body: "Looks good overall, two small things inline.", date: .now.addingTimeInterval(-3_600)),
            ], showInCode: { _, _ in }
        )
        .padding()
    }
    .frame(width: 380, height: 420)
}
