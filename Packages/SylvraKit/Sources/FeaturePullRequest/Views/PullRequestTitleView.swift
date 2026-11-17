import DesignSystem
import SwiftUI
import SylvraCore

/// Window title (pure): the repository and the pull request number as buttons to GitHub, then the title on up
/// to two lines. The rest of the area behaves like a title bar: drag moves the window, a double-click zooms it.
public struct PullRequestTitleView: View {
    let pullRequest: PullRequestSummary?
    let width: CGFloat
    let open: (URL) -> Void
    let doubleClick: () -> Void

    /// Minimum widths for narrow and wide windows. The item also grows into the free toolbar space (like the
    /// system title it replaces), which keeps the buttons at the trailing edge on wide screens; its minimum
    /// only changes with the window size band, never while AppKit lays out the toolbar.
    public static let narrowWidth: CGFloat = 400
    public static let wideWidth: CGFloat = 640

    public init(
        pullRequest: PullRequestSummary?, width: CGFloat = narrowWidth, open: @escaping (URL) -> Void,
        doubleClick: @escaping () -> Void = {}
    ) {
        self.pullRequest = pullRequest
        self.width = width
        self.open = open
        self.doubleClick = doubleClick
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
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(pullRequest.title)
            } else {
                Text(verbatim: "Sylvra").fontWeight(.semibold)
            }
        }
        .font(.callout)
        .frame(minWidth: width, idealWidth: width, maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity)
        // Click-through to the title bar: the chips are buttons, everything else moves or zooms the window.
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .onTapGesture(count: 2, perform: doubleClick)
        .allowsWindowActivationEvents(true)
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
