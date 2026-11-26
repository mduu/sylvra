import DesignSystem
import SwiftUI
import SylvraCore

/// The Delivery tab of a merged pull request (container): the pipeline from GitHub, reloaded while shown, a
/// card for the selected stage, following in the background and approving a waiting deployment.
/// `askAI` opens a chat about a stage (`nil` hides *Ask AI about this*).
public struct DeliveryPanel: View {
    @Bindable private var model: DeliveryModel
    private let pullRequestID: PullRequestID?
    private let askAI: ((String) -> Void)?
    @Environment(\.openURL) private var openURL
    @State private var stageToApprove: DeliveryStage?

    public init(model: DeliveryModel, pullRequestID: PullRequestID?, askAI: ((String) -> Void)? = nil) {
        self.model = model
        self.pullRequestID = pullRequestID
        self.askAI = askAI
    }

    public var body: some View {
        Group {
            if let id = pullRequestID, let delivery = model.delivery(for: id) {
                content(delivery, id)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: pullRequestID) {
            await model.load(pullRequestID)
            await model.keepRefreshing(pullRequestID)
        }
        .confirmationDialog(
            "Approve the deployment to \(stageToApprove?.name ?? "")?", isPresented: approvalBinding,
            presenting: stageToApprove
        ) { stage in
            Button("Approve Deployment") {
                guard let id = pullRequestID else { return }
                Task { await model.approve(stage, of: id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("GitHub starts the deployment right away.")
        }
    }

    private var approvalBinding: Binding<Bool> {
        Binding(get: { stageToApprove != nil }, set: { if !$0 { stageToApprove = nil } })
    }

    @ViewBuilder private func content(_ delivery: Delivery, _ id: PullRequestID) -> some View {
        DeliveryHeadlineView(
            delivery: delivery, isFollowing: model.isFollowing(id),
            toggleFollowing: { model.isFollowing(id) ? model.unfollow(id) : model.follow(id) })
        if delivery.stages.isEmpty {
            Text(
                delivery.isFinished()
                    ? "GitHub knows no workflow run and no deployment for the merge commit."
                    : "No workflow run for the merge commit yet. Sylvra keeps looking."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            let shown = model.shownStage(for: id)
            PipelineStripView(stages: delivery.stages, selectedID: shown?.id) { stage in
                withAnimation(.snappy) { model.selectedStage[id] = stage.id }
            }
            if let shown {
                StageCardView(
                    stage: shown, isApproving: model.isApproving, approvalError: model.approvalError,
                    approve: shown.approval?.viewerCanApprove == true ? { stageToApprove = shown } : nil,
                    askAI: askAI.map { ask in { ask(DeliveryQuestion.about(shown, of: delivery)) } },
                    open: { if let url = $0 { openURL(url) } }
                )
                .id(shown.id)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var placeholder: some View {
        switch model.loadState {
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load the delivery", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load(pullRequestID) } }
            }
        case .loaded:
            Text("The delivery starts once the pull request is merged.").foregroundStyle(.secondary)
        default:
            ProgressView().frame(maxWidth: .infinity)
        }
    }
}

/// The delivery in one line, with the switch for following it in the background (pure).
struct DeliveryHeadlineView: View {
    let delivery: Delivery
    let isFollowing: Bool
    let toggleFollowing: () -> Void
    var now = Date.now

    var body: some View {
        let state = delivery.overallState(at: now)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: state.symbol).foregroundStyle(state.tint).font(.callout.weight(.bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(delivery.headline(at: now)).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !delivery.isFinished(at: now) || isFollowing {
                Button(action: toggleFollowing) {
                    Image(systemName: isFollowing ? "bell.fill" : "bell")
                        .foregroundStyle(isFollowing ? SylvraColor.brandPrimary : .secondary)
                }
                .buttonStyle(.borderless)
                .help(
                    isFollowing
                        ? "Sylvra follows this delivery and notifies you per stage. Click to stop."
                        : "Follow this delivery: a notification when a stage is done, fails or needs approval"
                )
                .accessibilityLabel(isFollowing ? "Stop following the delivery" : "Follow the delivery")
            }
        }
    }

    private var subtitle: String {
        let commit = String(delivery.mergeCommitSHA.prefix(7))
        guard let mergedAt = delivery.mergedAt else { return commit }
        return String(localized: "Merged \(mergedAt.formatted(.relative(presentation: .named))) · \(commit)")
    }
}

/// The question *Ask AI about this* sends for a stage: what GitHub reports, as text.
enum DeliveryQuestion {
    static func about(_ stage: DeliveryStage, of delivery: Delivery) -> String {
        var lines = [
            "This pull request was merged (merge commit \(delivery.mergeCommitSHA.prefix(10))). "
                + "Its delivery stage \"\(stage.name)\" is: \(stage.state.rawValue).",
            "All stages: " + delivery.stages.map { "\($0.name) (\($0.state.rawValue))" }.joined(separator: " → "),
        ]
        for job in stage.jobs {
            var line = "- Job \"\(job.name)\": \(job.state.rawValue)"
            if !job.failedSteps.isEmpty { line += "; failed steps: " + job.failedSteps.joined(separator: ", ") }
            lines.append(line)
            lines += job.errors.map { "  error: \($0.prefix(400))" }
        }
        lines.append(
            stage.state == .failed
                ? "What most likely went wrong, is it related to this pull request's change, and what should I do next?"
                : "What does this stage do for this change, and is there anything I should watch out for?")
        return lines.joined(separator: "\n")
    }
}

#Preview {
    let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)
    DeliveryPanel(model: DeliveryModel(loader: DemoDeliveryLoader()), pullRequestID: id, askAI: { _ in })
        .padding()
        .frame(width: 360, height: 520, alignment: .top)
}
