import AppKit
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
    /// The graph's share of the height below the headline (dragged with the handle; the graph never takes more
    /// than it needs, and the details keep at least `minimumDetails`).
    @AppStorage("delivery.graphShare") private var graphShare = 0.5
    private static let minimumDetails: CGFloat = 260
    private static let minimumGraph: CGFloat = 150
    /// Tools to allow for AI checks, waiting for the user's confirmation; then the stage is checked again.
    @State private var toolsToAllow: ToolsToAllow?

    struct ToolsToAllow: Identifiable {
        let tools: [String]
        /// The stages to check again once the tools are allowed.
        let stageIDs: [String]
        var id: String { (tools + stageIDs).joined(separator: ",") }
    }

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
        .confirmationDialog(
            "Allow these tools for AI checks?", isPresented: toolsBinding, presenting: toolsToAllow
        ) { request in
            Button("Allow and Check Again") {
                model.allowForChecks(request.tools)
                if let id = pullRequestID { for stageID in request.stageIDs { model.startVerifying(stageID, of: id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(
                "\(request.tools.map(ToolName.short).joined(separator: ", "))\n\nSylvra's AI checks may then call "
                    + "them without asking, in every repository. Allow only tools that read. Your other Claude "
                    + "sessions keep their own rules; the options (…) let you stop allowing them.")
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

    private var toolsBinding: Binding<Bool> {
        Binding(get: { toolsToAllow != nil }, set: { if !$0 { toolsToAllow = nil } })
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
                editNotes: model.canVerify ? { isEditingNotes = true } : nil,
                allowedTools: model.allowedCheckTools,
                stopAllowing: { model.stopAllowingForChecks($0) }
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
                stagesView(delivery, id)
            }
        }
    }

    /// The graph and, below it, the details of what is selected in it; a handle between them sets the split.
    private func stagesView(_ delivery: Delivery, _ id: PullRequestID) -> some View {
        let columns = model.aiColumns(for: id)
        let cardHeight = AICheckCardView.height(columns: columns)
        let natural =
            max(WorkflowGraphLayout(stages: delivery.stages).size.height, columns.isEmpty ? 0 : cardHeight) + 12
        return GeometryReader { proxy in
            let available = proxy.size.height
            let wanted = max(Self.minimumGraph, min(available - Self.minimumDetails, available * graphShare))
            let graphHeight = min(natural, wanted)
            VStack(spacing: 0) {
                graphView(delivery, id, columns: columns, cardHeight: cardHeight)
                    .frame(height: graphHeight)
                SplitHandle()
                    .gesture(
                        DragGesture(coordinateSpace: .named("deliverySplit"))
                            .onChanged { value in
                                graphShare = min(0.85, max(0.15, Double(value.location.y / max(1, available))))
                            })
                detailsView(delivery, id)
            }
            .coordinateSpace(.named("deliverySplit"))
        }
    }

    @ViewBuilder private func graphView(
        _ delivery: Delivery, _ id: PullRequestID, columns: [AICheckColumn], cardHeight: CGFloat
    ) -> some View {
        let stage = model.shownStage(for: id)
        let item = model.shownItem(for: id)
        let showsAI = model.isShowingAICheck(for: id)
        WorkflowGraphView(
            stages: delivery.stages,
            selectedBandID: showsAI ? stage.map { DeliveryModel.aiPrefix + $0.id } : stage?.id,
            selectedBoxID: item.flatMap { if case .job(let job) = $0, !showsAI { job } else { nil } },
            selectStage: { stage in withAnimation(.snappy) { model.selectStage(stage.id, of: id) } },
            selectJob: { job in withAnimation(.snappy) { model.selectJob(job.id, of: id) } },
            card: columns.isEmpty
                ? nil : card(columns, selectedStage: showsAI ? stage : nil, item: item, delivery: delivery, id),
            cardHeight: cardHeight
        )
    }

    @ViewBuilder private func detailsView(_ delivery: Delivery, _ id: PullRequestID) -> some View {
        let item = model.shownItem(for: id)
        if let stage = model.shownStage(for: id) {
            StageDetailsView(
                stage: stage, showsAICheck: model.isShowingAICheck(for: id), item: item,
                verification: model.verification(of: stage, in: id),
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
            loadLog: { number in Task { await model.loadLog(number, of: id) } },
            showAICheck: model.aiColumns(for: id).contains { $0.stage.id == stage.id }
                ? { withAnimation(.snappy) { model.selectAICheck(stage.id, of: id) } } : nil,
            deniedTools: check.map(model.stillDenied) ?? [],
            allowDeniedTools: {
                let tools = check.map(model.stillDenied) ?? []
                guard !tools.isEmpty else { return }
                toolsToAllow = ToolsToAllow(tools: tools, stageIDs: [stage.id])
            })
    }

    /// The details show a job without a log yet (the first item of a stage is chosen, not clicked).
    private func loadLogIfNeeded(_ item: DeliveryItem?, stage: DeliveryStage, id: PullRequestID) {
        guard case .job(let jobID) = item, let job = stage.jobs.first(where: { $0.id == jobID }), job.hasLog,
            let number = job.jobID, model.logs[number] == nil
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

extension DeliveryScreen {
    /// The AI check's verdict card at the end of the graph.
    fileprivate func card(
        _ columns: [AICheckColumn], selectedStage: DeliveryStage?, item: DeliveryItem?, delivery: Delivery,
        _ id: PullRequestID
    ) -> AICheckCardView {
        let blocked = columns.compactMap(\.result).flatMap(model.stillDenied)
        var unique: [String] = []
        for tool in blocked where !unique.contains(tool) { unique.append(tool) }
        let blockedStages = columns.filter { $0.result.map(model.stillDenied)?.isEmpty == false }.map(\.stage.id)
        return AICheckCardView(
            columns: columns, selectedStageID: selectedStage?.id,
            selectedCheck: item.flatMap { if case .check(let title) = $0 { title } else { nil } },
            blockedTools: unique.map(ToolName.short),
            actions: AICheckCardActions(
                select: { stage, title in
                    withAnimation(.snappy) { model.selectAICheck(stage.id, item: title.map { .check($0) }, of: id) }
                },
                verify: model.canVerify ? { stage in model.startVerifying(stage.id, of: id) } : nil,
                stop: { stage in model.stopVerifying(stage.id, of: id) },
                verifyAll: model.canVerify
                    ? {
                        for column in columns where column.isCheckable && !column.isRunning {
                            model.startVerifying(column.stage.id, of: id)
                        }
                    } : nil,
                allowBlockedTools: unique.isEmpty
                    ? nil : { toolsToAllow = ToolsToAllow(tools: unique, stageIDs: blockedStages) }))
    }
}

/// The grip between the graph and the details: drag to give one more room.
private struct SplitHandle: View {
    @State private var isHovering = false

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(isHovering ? 0.6 : 0.3))
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .help("Drag to share the height between the graph and the details")
            .accessibilityLabel("Resize the graph and the details")
    }
}
