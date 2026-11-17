import DesignSystem
import SwiftUI
import SylvraCore

/// The pull request info in the middle of the window toolbar (pure): repository and number as buttons to
/// GitHub with the title, below it the branch, approvals and checks (each status jumps to its tab). The rest
/// of the box behaves like a title bar: drag moves the window, a double-click zooms it.
public struct PullRequestTitleView: View {
    let pullRequest: PullRequestSummary?
    /// Details of the same pull request, for the status line (`nil` while loading or for another PR).
    let detail: PullRequestDetail?
    let width: CGFloat
    let open: (URL) -> Void
    let showTab: (PullRequestScreenModel.Tab) -> Void
    let doubleClick: () -> Void

    /// Width without a window size yet.
    public static let narrowWidth: CGFloat = 400
    /// Box widths by window width: wider windows give the title more room. Constant within a step: a toolbar
    /// item that changes width while AppKit lays out the toolbar can loop its constraint pass.
    static let widthSteps: [(minWindowWidth: CGFloat, width: CGFloat)] = [
        (0, 400), (1760, 560), (2000, 720), (2300, 880),
    ]
    /// A window must be this far into another step before the box changes (no flicker while resizing).
    static let hysteresis: CGFloat = 40

    /// The box width for a window width, keeping `current` near the step boundaries.
    public static func width(forWindowWidth window: CGFloat, current: CGFloat) -> CGFloat {
        let plain = widthSteps.last { window >= $0.minWindowWidth }?.width ?? narrowWidth
        guard plain != current, let step = widthSteps.firstIndex(where: { $0.width == current }) else { return plain }
        let lower = widthSteps[step].minWindowWidth - hysteresis
        let upper = step + 1 < widthSteps.count ? widthSteps[step + 1].minWindowWidth + hysteresis : .infinity
        return window >= lower && window < upper ? current : plain
    }

    public init(
        pullRequest: PullRequestSummary?, detail: PullRequestDetail? = nil, width: CGFloat = narrowWidth,
        open: @escaping (URL) -> Void, showTab: @escaping (PullRequestScreenModel.Tab) -> Void = { _ in },
        doubleClick: @escaping () -> Void = {}
    ) {
        self.pullRequest = pullRequest
        self.detail = detail.flatMap { $0.summary.id == pullRequest?.id ? $0 : nil }
        self.width = width
        self.open = open
        self.showTab = showTab
        self.doubleClick = doubleClick
    }

    public var body: some View {
        VStack(spacing: 2) {
            if let pullRequest {
                HStack(spacing: 6) {
                    chip(pullRequest.id.repository, url: pullRequest.repositoryWebURL)
                        .help("Open \(pullRequest.id.owner)/\(pullRequest.id.repository) on GitHub")
                    chip("#\(pullRequest.id.number)", url: pullRequest.webURL)
                        .help("Open the pull request on GitHub")
                    Text(verbatim: pullRequest.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(pullRequest.title)
                }
                .font(.callout)
                statusLine(pullRequest)
            } else {
                Text(verbatim: "Sylvra").font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        // Own glass with gently rounded corners instead of the toolbar's capsule; behind the content, so the
        // chips keep their fill.
        .background {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        // Click-through to the title bar: the chips and statuses are buttons, the rest moves or zooms the window.
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .onTapGesture(count: 2, perform: doubleClick)
        .allowsWindowActivationEvents(true)
    }

    private func statusLine(_ pullRequest: PullRequestSummary) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(pullRequest.headRefName) → \(pullRequest.baseRefName)")
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
                .help("\(pullRequest.headRefName) into \(pullRequest.baseRefName)")
            if let detail {
                if let approvals = Self.approvals(detail.approvalStatus) {
                    status(approvals.text, symbol: approvals.symbol, tint: approvals.tint) { showTab(.overview) }
                        .help("Approvals — show the reviewers")
                }
                if let checks = Self.checks(detail) {
                    status(checks.text, symbol: checks.symbol, tint: checks.tint) { showTab(.checks) }
                        .help("Checks — show them")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func status(_ text: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Not a `Label`: inside the toolbar it would show only the symbol.
            HStack(spacing: 3) {
                Image(systemName: symbol)
                Text(text)
            }
            .foregroundStyle(tint)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .fixedSize()
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

    struct Status: Equatable {
        let text: String
        let symbol: String
        let tint: Color
    }

    /// "1 of 2 approvals", "Approved", "Changes requested" or "Review required" (`nil`: nothing to say).
    static func approvals(_ status: ApprovalStatus) -> Status? {
        if status.isSatisfied {
            return Status(text: String(localized: "Approved"), symbol: "checkmark.seal.fill", tint: .green)
        }
        if !status.changesRequestedBy.isEmpty {
            return Status(text: String(localized: "Changes requested"), symbol: "exclamationmark.circle", tint: .red)
        }
        if let required = status.requiredApprovals, required > 0 {
            return Status(
                text: String(localized: "\(status.approvedBy.count) of \(required) approvals"),
                symbol: "person.badge.clock", tint: .orange)
        }
        if status.reviewDecision == .reviewRequired {
            return Status(text: String(localized: "Review required"), symbol: "person.badge.clock", tint: .orange)
        }
        return nil
    }

    /// Failing, running or passed checks (`nil`: no checks).
    static func checks(_ detail: PullRequestDetail) -> Status? {
        guard !detail.checks.isEmpty else { return nil }
        let failing = detail.checks.count { $0.state == .failure || $0.state == .error }
        if failing > 0 {
            return Status(
                text: failing == 1
                    ? String(localized: "1 check failing") : String(localized: "\(failing) checks failing"),
                symbol: "exclamationmark.triangle.fill", tint: .red)
        }
        if detail.checks.contains(where: { $0.state == .pending }) {
            return Status(text: String(localized: "Checks running"), symbol: "clock", tint: .secondary)
        }
        return Status(text: String(localized: "Checks passed"), symbol: "checkmark.circle", tint: .green)
    }
}

#Preview {
    let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)
    let detail = DemoPullRequestDetailLoader.detail(for: id)
    VStack(spacing: 12) {
        PullRequestTitleView(pullRequest: detail.summary, detail: detail, width: 560) { _ in
        }
        PullRequestTitleView(pullRequest: nil) { _ in }
    }
    .frame(height: 120)
    .padding()
}
