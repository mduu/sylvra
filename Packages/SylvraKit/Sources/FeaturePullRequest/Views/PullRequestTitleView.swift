import DesignSystem
import SwiftUI
import SylvraCore

/// Window title (pure): the repository and the pull request number as buttons to GitHub, then the title.
public struct PullRequestTitleView: View {
    let pullRequest: PullRequestSummary?
    let open: (URL) -> Void

    /// Constant width: a toolbar item that changes width can loop AppKit's constraint pass.
    public static let width: CGFloat = 380

    public init(pullRequest: PullRequestSummary?, open: @escaping (URL) -> Void) {
        self.pullRequest = pullRequest
        self.open = open
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let pullRequest {
                chip(pullRequest.id.repository, url: pullRequest.repositoryWebURL)
                    .help("Open \(pullRequest.id.owner)/\(pullRequest.id.repository) on GitHub")
                chip("#\(pullRequest.id.number)", url: pullRequest.webURL)
                    .help("Open the pull request on GitHub")
                Text(verbatim: pullRequest.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(pullRequest.title)
            } else {
                Text(verbatim: "Sylvra").fontWeight(.semibold)
            }
        }
        .font(.callout)
        .frame(width: Self.width, alignment: .leading)
    }

    private func chip(_ title: String, url: URL?) -> some View {
        Button {
            if let url { open(url) }
        } label: {
            Text(verbatim: title).fontWeight(.semibold).lineLimit(1)
        }
        .buttonStyle(.chip)
        .disabled(url == nil)
        .fixedSize()
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        PullRequestTitleView(
            pullRequest: PullRequestSummary(
                id: PullRequestID(owner: "acme", repository: "billing", number: 1234),
                title: "Add invoice export with per-line rounding", author: UserRef(login: "lkeller"),
                createdAt: .now, updatedAt: .now, additions: 182, deletions: 41, headRefName: "feat",
                baseRefName: "main"),
            open: { _ in })
        PullRequestTitleView(pullRequest: nil, open: { _ in })
    }
    .padding()
}
