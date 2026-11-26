import DesignSystem
import SwiftUI
import SylvraCore

/// A merged pull request's way to production in the main area, instead of the diff (container): the headline,
/// the workflow graph (scrolls sideways), and the selected stage's details joined to it — jobs and logs, the
/// AI check with its evidence. Reloads while shown, follows in the background, approves a waiting deployment.
/// `askAI` opens a chat about a stage (`nil` hides it); `openSession` starts an interactive Claude Code session
/// with a prompt, in Sylvra's terminal or (`true`) the external one (`nil` hides it).
public struct DeliveryScreen: View {
    @Bindable private var model: DeliveryModel
    private let pullRequestID: PullRequestID?
    private let askAI: ((String) -> Void)?
    private let openSession: ((String, _ external: Bool) -> Void)?
    @Environment(\.openURL) private var openURL
    @State private var stageToApprove: DeliveryStage?
    @State private var isEditingNotes = false

    public init(
        model: DeliveryModel, pullRequestID: PullRequestID?, askAI: ((String) -> Void)? = nil,
        openSession: ((String, _ external: Bool) -> Void)? = nil
    ) {
        self.model = model
        self.pullRequestID = pullRequestID
        self.askAI = askAI
        self.openSession = openSession
    }

    public var body: some View {
        Group {
            if let id = pullRequestID, let delivery = model.delivery(for: id) {
                content(delivery, id)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SylvraColor.surfacePrimary)
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
        .sheet(isPresented: $isEditingNotes) {
            if let id = pullRequestID {
                MonitoringNotesSheet(repository: "\(id.owner)/\(id.repository)", notes: model.monitoringNotes(for: id))
                {
                    model.setMonitoringNotes($0, for: id)
                }
            }
        }
    }

    private var approvalBinding: Binding<Bool> {
        Binding(get: { stageToApprove != nil }, set: { if !$0 { stageToApprove = nil } })
    }

    @ViewBuilder private func content(_ delivery: Delivery, _ id: PullRequestID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DeliveryHeadlineView(
                delivery: delivery, isFollowing: model.isFollowing(id),
                toggleFollowing: { model.isFollowing(id) ? model.unfollow(id) : model.follow(id) },
                verifiesAutomatically: model.canVerify ? $model.verifiesAutomatically : nil,
                editNotes: model.canVerify ? { isEditingNotes = true } : nil
            )
            .padding(.horizontal, 20)
            .padding(.top, 14)
            if delivery.stages.isEmpty {
                Text(
                    delivery.isFinished()
                        ? "GitHub knows no workflow run and no deployment for the merge commit."
                        : "No workflow run for the merge commit yet. Sylvra keeps looking."
                )
                .foregroundStyle(.secondary)
                .padding(20)
            } else {
                let stage = model.shownStage(for: id)
                let item = model.shownItem(for: id)
                WorkflowGraphView(
                    stages: delivery.stages, selectedStageID: stage?.id,
                    selectedJobID: item.flatMap { if case .job(let job) = $0 { job } else { nil } },
                    verdicts: verdicts(delivery, id),
                    selectStage: { stage in withAnimation(.snappy) { model.selectStage(stage.id, of: id) } },
                    selectJob: { job in withAnimation(.snappy) { model.selectJob(job.id, of: id) } }
                )
                .frame(height: WorkflowGraphLayout(stages: delivery.stages).size.height + 12)
                if let stage {
                    StageDetailsView(
                        stage: stage, item: item, verification: model.verification(of: stage, in: id),
                        isVerifying: model.isVerifying(stage, in: id),
                        verificationError: model.verificationError(of: stage, in: id), isApproving: model.isApproving,
                        approvalError: model.approvalError, logs: model.logs,
                        actions: actions(for: stage, in: delivery, id)
                    )
                    .padding([.horizontal, .bottom], 14)
                    .onChange(of: stage) { _, stage in reloadRunningLog(stage, item: model.shownItem(for: id), id: id) }
                    .task(id: item) { loadLogIfNeeded(item, stage: stage, id: id) }
                }
            }
        }
    }

    private func verdicts(_ delivery: Delivery, _ id: PullRequestID) -> [String: StageVerification.Verdict] {
        var result: [String: StageVerification.Verdict] = [:]
        for stage in delivery.stages {
            if let verdict = model.verification(of: stage, in: id)?.verdict { result[stage.id] = verdict }
        }
        return result
    }

    private func actions(for stage: DeliveryStage, in delivery: Delivery, _ id: PullRequestID) -> StageDetailsActions {
        let isCheckable = stage.state == .failed || (stage.state == .succeeded && stage.kind == .environment)
        let check = model.verification(of: stage, in: id)
        return StageDetailsActions(
            select: { item in withAnimation(.snappy) { model.select(item, of: id) } },
            open: { if let url = $0 { openURL(url) } },
            approve: stage.approval?.viewerCanApprove == true ? { stageToApprove = stage } : nil,
            verify: model.canVerify && isCheckable ? { model.startVerifying(stage.id, of: id) } : nil,
            stopVerifying: { model.stopVerifying(stage.id, of: id) },
            askAI: askAI.map { ask in { ask(DeliveryQuestion.about(stage, of: delivery, verification: check)) } },
            openSession: openSession.map { open in
                { external in open(DeliveryQuestion.session(about: stage, of: delivery, verification: check), external)
                }
            },
            loadLog: { number in Task { await model.loadLog(number, of: id) } })
    }

    /// The details show a job without a log yet (the first item of a stage is chosen, not clicked).
    private func loadLogIfNeeded(_ item: DeliveryItem?, stage: DeliveryStage, id: PullRequestID) {
        guard case .job(let jobID) = item, let number = stage.jobs.first(where: { $0.id == jobID })?.jobID,
            model.logs[number] == nil
        else { return }
        Task { await model.loadLog(number, of: id) }
    }

    /// A running job's log grows: reloaded with the delivery.
    private func reloadRunningLog(_ stage: DeliveryStage, item: DeliveryItem?, id: PullRequestID) {
        guard case .job(let jobID) = item, let job = stage.jobs.first(where: { $0.id == jobID }),
            job.state == .running || job.state == .failed, let number = job.jobID
        else { return }
        Task { await model.loadLog(number, of: id) }
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
            ContentUnavailableView(
                "Not merged yet", systemImage: "shippingbox", description: Text("The delivery starts with the merge."))
        default:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    let id = PullRequestID(owner: "acme", repository: "billing", number: 812)
    DeliveryScreen(
        model: DeliveryModel(loader: DemoDeliveryLoader(), verifier: DemoDeliveryVerifier()), pullRequestID: id,
        askAI: { _ in }, openSession: { _, _ in }
    )
    .frame(width: 1200, height: 760)
}
