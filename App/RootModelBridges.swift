import FeatureAIReview
import FeatureActivity
import FeatureDelivery
import FeatureDiff
import FeatureOpenInIDE
import SwiftUI
import SylvraCore

/// Keeps the feature models in step (commits → diff, AI results → diff highlights, jobs → activity, …).
///
/// A zero-size view with its own observation: these `onChange` values were read in `RootScreen.body`, so
/// each change (a selected file or finding, an IDE status, an inbox refresh) re-evaluated the whole window,
/// the diff with every row included.
struct RootModelBridges: View {
    let root: RootScreen

    private var environment: AppEnvironment { root.environment }
    private var role: WindowRole { root.role }
    private var layout: WindowLayout { root.layout }
    private var selection: PullRequestSummary? { root.selection }
    private var aiReadingOrder: [ReadingStep] { root.aiReadingOrder }
    private var aiHighlights: [LineHighlight] { root.aiHighlights }
    private var selectedID: PullRequestID? {
        get { root.selectedID }
        nonmutating set { root.selectedID = newValue }
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: environment.pullRequest.detail?.commits, initial: true) { _, commits in
                // Commit-by-commit review needs the PR's commits (oldest first, as GitHub lists them).
                root.applyCommits(commits)
            }
            .onChange(of: environment.diff.selectedPath) { _, path in
                environment.chat.context.file = path
            }
            .onChange(of: environment.diff.navigatorRevealToken) {
                // A click on a file header in the diff shows the file in the Files tab of the PR column.
                guard role == .main else { return }
                withAnimation(.snappy) {
                    environment.pullRequest.tab = .files
                    root.isInboxListed = false
                }
            }
            .onChange(of: environment.aiReview.selectedFindingID) { _, id in
                environment.chat.context.finding =
                    environment.aiReview.findings(for: selection?.id)
                    .first { $0.id == id }?.title
            }
            .onChange(of: aiReadingOrder, initial: true) { _, order in
                withAnimation(.snappy) { environment.diff.readingOrder = order }
            }
            .onChange(of: aiHighlights) { _, highlights in
                withAnimation(.snappy) { environment.diff.lineHighlights = highlights }
            }
            .onChange(of: environment.aiReview.preparation) {
                if environment.aiReview.runState == .running { environment.activity.start(aiReviewJob) }
            }
            .onChange(of: environment.aiReview.progress) {
                // The overview shows how far the review got; the inspector has the agents in detail.
                if environment.aiReview.runState == .running { environment.activity.start(aiReviewJob) }
            }
            .onChange(of: environment.aiReview.runState) { _, state in
                let id = "ai-review"
                switch state {
                case .running:
                    environment.activity.start(aiReviewJob)
                case .done:
                    let review = environment.aiReview
                    let count = review.visibleFindings(for: review.runningPullRequest).count
                    var message = String(localized: "Review finished — \(count) findings")
                    if let tokens = review.runningPullRequest.flatMap({ review.results[$0]?.tokens }) {
                        message += " · " + tokens.label
                    }
                    environment.activity.finish(id, message: message)
                case .failed(let message):
                    environment.activity.finish(id, message: message)
                case .idle:
                    environment.activity.finish(id, message: nil)
                }
            }
            .onChange(of: environment.openInIDE.status) { _, status in
                if case .working(let message) = status {
                    environment.activity.start(ActivityJob(id: "checkout", kind: .checkout, title: message))
                } else {
                    environment.activity.finish("checkout", message: nil)
                }
            }
            .onChange(of: deliveryJobs, initial: true) { old, jobs in
                guard role == .main else { return }
                for job in old where !jobs.contains(where: { $0.id == job.id }) {
                    environment.activity.finish(job.id, message: nil)
                }
                for job in jobs { environment.activity.start(job) }
            }
            // Initial too: an inbox restored from the cache is there before this view observes it.
            .onChange(of: environment.inbox.snapshot, initial: true) {
                guard selectedID == nil, let wanted = environment.initialSelection else { return }
                selectedID =
                    environment.inbox.snapshot.sections.values.joined().first { $0.id.description == wanted }?.id
            }
    }
}

extension RootModelBridges {
    /// One job per followed delivery: "Delivery · billing #881" with its headline; opens that pull request.
    fileprivate var deliveryJobs: [ActivityJob] {
        environment.delivery.followed.map { id in
            ActivityJob(
                id: "delivery-\(id)", kind: .delivery,
                title: String(localized: "Delivery · \(id.repository) #\(id.number)"),
                detail: environment.delivery.verifying.contains { $0.hasPrefix("\(id)|") }
                    ? String(localized: "AI check running") : environment.delivery.delivery(for: id)?.headline(),
                pullRequest: id,
                // Stable, or every reload would count as a new job.
                startedAt: environment.delivery.delivery(for: id)?.mergedAt ?? .distantPast)
        }
    }

    /// "AI review · billing #881" with the agents done so far; opens that pull request.
    fileprivate var aiReviewJob: ActivityJob {
        let review = environment.aiReview
        let pullRequest = review.runningPullRequest
        let title =
            pullRequest.map { String(localized: "AI review · \($0.repository) #\($0.number)") }
            ?? String(localized: "AI review")
        let isCombining = review.progress.contains { $0.id == ReviewEngine.consolidationID && $0.state == .running }
        let detail =
            review.progress.isEmpty
            ? review.preparation
            : isCombining
                ? String(localized: "Combining the models' findings")
                : String(localized: "\(review.finishedAgentCount) of \(review.agentProgress.count) agents")
        return ActivityJob(id: "ai-review", kind: .aiReview, title: title, detail: detail, pullRequest: pullRequest)
    }
}

/// The Open in IDE status toast, observing the status itself.
struct RootOpenInIDEToast: View {
    let model: OpenInIDEModel

    var body: some View {
        OpenInIDEStatusToast(status: model.status)
            .padding(.bottom, 16)
            .animation(.snappy, value: model.status)
    }
}
