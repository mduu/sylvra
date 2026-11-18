import DesignSystem
import SwiftUI
import SylvraCore

/// "Why you're involved": where the user was mentioned, whether they took part and what is new since (pure).
struct InvolvementCardView: View {
    let involvement: Involvement
    /// What others did since the user's last comment (`nil`: nothing, or not known).
    var newActivity: NewActivity?
    var open: (URL) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Why you're involved", systemImage: "at")
                .font(.callout.weight(.semibold))
                .foregroundStyle(SylvraColor.accentGold)
            ForEach(involvement.mentions.prefix(5)) { mention in
                mentionRow(mention)
            }
            if involvement.mentions.count > 5 {
                Text("\(involvement.mentions.count - 5) more mentions").font(.caption).foregroundStyle(.secondary)
            }
            if involvement.ownCommentCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                    Text("You commented ^[\(involvement.ownCommentCount) time](inflect: true)")
                    if let last = involvement.lastOwnCommentAt {
                        Text("· last \(last, format: .relative(presentation: .named))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if involvement.activity.isWaitingOnOthers {
                    Label("Nothing new since — waiting on others", systemImage: "hourglass")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else if let newActivity {
                    Divider().padding(.vertical, 2)
                    NewActivityView(activity: newActivity, open: open)
                } else if involvement.activity.hasNewActivity {
                    Label("New activity since your last comment", systemImage: "circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SylvraColor.brandPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SylvraColor.accentGold.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func mentionRow(_ mention: Mention) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(mention.author, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(mention.author.displayName).fontWeight(.semibold)
                    Text(Self.placeText(mention.place)).foregroundStyle(.secondary)
                    Text(mention.date, format: .relative(presentation: .named)).foregroundStyle(.tertiary)
                }
                .font(.caption)
                .lineLimit(2)
                Text(highlighted(mention.excerpt))
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = mention.url {
                    Button("Open on GitHub") { open(url) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }

    private func highlighted(_ excerpt: String) -> AttributedString {
        var text = AttributedString(excerpt)
        guard let login = involvement.login else { return text }
        var searchStart = text.startIndex
        while let range = text[searchStart...].range(of: "@" + login, options: .caseInsensitive) {
            text[range].foregroundColor = SylvraColor.accentGold
            text[range].font = .callout.weight(.semibold)
            searchStart = range.upperBound
        }
        return text
    }

    static func placeText(_ place: Mention.Place) -> String {
        switch place {
        case .description: String(localized: "mentioned you in the description")
        case .comment: String(localized: "mentioned you in a comment")
        case .review: String(localized: "mentioned you in a review")
        case .codeComment(let path, let line):
            if let line {
                String(localized: "mentioned you on \((path as NSString).lastPathComponent):\(line)")
            } else {
                String(localized: "mentioned you on \((path as NSString).lastPathComponent)")
            }
        }
    }
}

#Preview {
    InvolvementCardView(
        involvement: Involvement(
            login: "mduu",
            mentions: [
                Mention(
                    place: .codeComment(path: "Sources/Billing/InvoiceService.swift", line: 42),
                    author: UserRef(login: "lkeller", name: "Lena Keller"), date: .now.addingTimeInterval(-7200),
                    excerpt: "@mduu could you double-check the rounding here? You changed it last time.",
                    url: URL(string: "https://github.com")),
                Mention(
                    place: .comment, author: UserRef(login: "twagner", name: "Tim Wagner"),
                    date: .now.addingTimeInterval(-90_000), excerpt: "cc @mduu for the export part", url: nil),
            ], ownCommentCount: 2, lastOwnCommentAt: .now.addingTimeInterval(-3600))
    )
    .padding()
    .frame(width: 420)
}
