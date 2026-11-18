import DesignSystem
import SwiftUI
import SylvraCore

/// What is new since the user's last comment: commits and comments by others, newest first (pure).
/// Each entry opens on GitHub.
struct NewActivityView: View {
    let activity: NewActivity
    var open: (URL) -> Void = { _ in }

    static let commitLimit = 5
    static let commentLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("New since your last comment · \(activity.since, format: .relative(presentation: .named))")
            } icon: {
                Image(systemName: "circle.fill").font(.system(size: 7))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(SylvraColor.brandPrimary)
            if !activity.commits.isEmpty {
                Text(Self.count(activity.commits.count, "commit"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(activity.commits.prefix(Self.commitLimit)) { commitRow($0) }
                more(activity.commits.count - Self.commitLimit)
            }
            if !activity.comments.isEmpty {
                Text(Self.count(activity.comments.count, "comment"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, activity.commits.isEmpty ? 0 : 4)
                ForEach(activity.comments.prefix(Self.commentLimit)) { commentRow($0) }
                more(activity.comments.count - Self.commentLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commitRow(_ commit: Commit) -> some View {
        entry(url: commit.url) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: String(commit.sha.prefix(7)))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(verbatim: commit.subject)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(commit.author.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .help("Open the commit on GitHub")
    }

    private func commentRow(_ comment: NewActivity.Comment) -> some View {
        entry(url: comment.url) {
            HStack(alignment: .top, spacing: 8) {
                AvatarView(comment.author, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(comment.author.displayName).fontWeight(.semibold)
                        Text(Self.placeText(comment)).foregroundStyle(.secondary)
                        Text(comment.date, format: .relative(presentation: .named)).foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .lineLimit(1)
                    if !comment.excerpt.isEmpty {
                        Text(verbatim: comment.excerpt)
                            .font(.callout)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .help("Open the comment on GitHub")
    }

    /// A row that opens `url` on click; plain text without one.
    @ViewBuilder
    private func entry(url: URL?, @ViewBuilder label: () -> some View) -> some View {
        if let url {
            Button {
                open(url)
            } label: {
                label().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            label()
        }
    }

    @ViewBuilder
    private func more(_ count: Int) -> some View {
        if count > 0 {
            Text("\(count) more").font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// "1 new commit", "3 new comments" (inflection markup isn't applied to runtime strings everywhere).
    nonisolated static func count(_ count: Int, _ kind: String) -> String {
        switch (kind, count) {
        case ("commit", 1): String(localized: "1 new commit")
        case ("commit", _): String(localized: "\(count) new commits")
        case (_, 1): String(localized: "1 new comment")
        default: String(localized: "\(count) new comments")
        }
    }

    nonisolated static func placeText(_ comment: NewActivity.Comment) -> String {
        switch comment.place {
        case .conversation: return String(localized: "commented")
        case .review: return String(localized: "reviewed")
        case .code(let path, let line, _):
            let file = (path as NSString).lastPathComponent
            let place = line.map { "\(file):\($0)" } ?? file
            return comment.isReply
                ? String(localized: "replied on \(place)") : String(localized: "commented on \(place)")
        }
    }
}

#Preview {
    let lena = UserRef(login: "lkeller", name: "Lena Keller")
    let jonas = UserRef(login: "jbrunner", name: "Jonas Brunner")
    NewActivityView(
        activity: NewActivity(
            since: .now.addingTimeInterval(-86_400),
            commits: [
                Commit(
                    sha: "3be7d12aa", subject: "Quote names with commas in CSV export", author: lena,
                    authoredAt: .now.addingTimeInterval(-7200)),
                Commit(
                    sha: "9c01f3e42", subject: "Round VAT per line", author: lena,
                    authoredAt: .now.addingTimeInterval(-10_800)),
            ],
            comments: [
                NewActivity.Comment(
                    id: "1", author: jonas,
                    place: .code(
                        path: "Sources/Billing/PriceRules.swift", line: 58,
                        isResolved: false),
                    isReply: true, excerpt: "Fixed in the latest commit, can you take another look?",
                    date: .now.addingTimeInterval(-3600), url: URL(string: "https://github.com")),
                NewActivity.Comment(
                    id: "2", author: lena, place: .conversation, isReply: false,
                    excerpt: "Addressed all comments, ready for another round.",
                    date: .now.addingTimeInterval(-1800), url: nil),
            ])
    )
    .padding()
    .frame(width: 420)
}
