import DesignSystem
import SwiftUI

/// What the details of a stage need from the screen (closures out).
struct StageDetailsActions {
    var select: (DeliveryItem) -> Void
    var open: (URL?) -> Void
    /// Approves the waiting deployment (`nil`: not possible for the signed-in user).
    var approve: (() -> Void)?
    /// Starts (or repeats) the AI check (`nil`: no agent, or nothing to check yet).
    var verify: (() -> Void)?
    var stopVerifying: (() -> Void)?
    var askAI: (() -> Void)?
    /// `true`: in the external terminal app.
    var openSession: ((Bool) -> Void)?
    var loadLog: (Int) -> Void
}

/// The selected stage's details (pure): on the left its jobs, the AI check and its checks; on the right what
/// the selected row shows — a job's log, a check's evidence, what the agent did. The selected row and the pane
/// share their colour and meet without a gap, so they read as one.
struct StageDetailsView: View {
    let stage: DeliveryStage
    let item: DeliveryItem?
    let verification: StageVerification?
    var isVerifying = false
    var verificationError: String?
    var isApproving = false
    var approvalError: String?
    var logs: [Int: LogState] = [:]
    let actions: StageDetailsActions

    static let paneColor = SylvraColor.surfaceSelected

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                StageListView(
                    stage: stage, item: item, verification: verification, isVerifying: isVerifying,
                    verificationError: verificationError, isApproving: isApproving, approvalError: approvalError,
                    actions: actions)
            }
            .frame(width: 360)
            .scrollIndicators(.never)
            StagePaneView(stage: stage, item: item, verification: verification, logs: logs, actions: actions)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Self.paneColor)
        }
        .background(SylvraColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SylvraColor.brandPrimary.opacity(0.7), lineWidth: 1.5))
    }
}

/// The left side: header, approval, jobs, AI check rows, actions (pure).
private struct StageListView: View {
    let stage: DeliveryStage
    let item: DeliveryItem?
    let verification: StageVerification?
    let isVerifying: Bool
    let verificationError: String?
    let isApproving: Bool
    let approvalError: String?
    let actions: StageDetailsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            if stage.state == .needsApproval { approval }
            if !stage.jobs.isEmpty { sectionTitle("Jobs") }
            ForEach(stage.jobs) { job in
                row(.job(job.id), symbol: job.state.symbol, tint: job.state.tint) {
                    Text(job.name).lineLimit(1)
                } trailing: {
                    Text(job.duration.map(deliveryDurationText) ?? job.state.title)
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            aiCheck
            buttons.padding(.top, 12)
        }
        .padding(.leading, 12)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(stage.name).font(.title3.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Button("Open on GitHub") { actions.open(stage.url) }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(stage.url == nil)
        }
        .padding(.trailing, 12)
        .padding(.bottom, 6)
    }

    private var subtitle: String {
        var parts = [stage.state.title]
        if let finished = stage.finishedAt { parts.append(finished.formatted(date: .omitted, time: .shortened)) }
        if stage.workflow == nil, stage.kind == .environment {
            parts.append(String(localized: "reported as a deployment"))
        }
        return parts.joined(separator: " · ")
    }

    private var approval: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                actions.approve == nil
                    ? "This deployment waits for an approval by one of the environment's reviewers."
                    : "This deployment waits for your approval."
            )
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            if let approve = actions.approve {
                HStack(spacing: 8) {
                    Button("Approve Deployment…", action: approve)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isApproving)
                    if isApproving { ProgressView().controlSize(.small) }
                }
            }
            if let approvalError { errorLabel(approvalError) }
        }
        .padding(10)
        .background(SylvraColor.statusWarning.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.trailing, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var aiCheck: some View {
        if actions.verify != nil || verification != nil || isVerifying {
            HStack(spacing: 6) {
                Label("AI check", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AIAccent.border)
                if let verification {
                    Text(verification.verdict.title).font(.caption.weight(.semibold))
                        .foregroundStyle(verification.verdict.tint)
                    Text(verification.checkedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if isVerifying {
                    ProgressView().controlSize(.mini)
                    Text("Checking…").font(.caption).foregroundStyle(.secondary)
                    if let stop = actions.stopVerifying {
                        Button("Stop", action: stop).buttonStyle(.link).font(.caption)
                            .help("Stop the AI check (the agent is terminated)")
                    }
                } else if let verify = actions.verify {
                    Button(verification == nil ? "Check with AI" : "Check Again", action: verify)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .padding(.top, 14)
            .padding(.trailing, 12)
            .padding(.bottom, 2)
            if let verification {
                Text(verification.summary)
                    .aiFont(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 12)
                if !verification.intent.isEmpty {
                    Text("Change: \(verification.intent)")
                        .aiFont(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 12)
                        .padding(.bottom, 4)
                }
                ForEach(verification.checks) { check in
                    row(.check(check.title), symbol: check.outcome.symbol, tint: check.outcome.tint) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(check.title).font(.callout.weight(.medium))
                            Text(check.finding).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                if !verification.notChecked.isEmpty {
                    row(.notChecked, symbol: "questionmark.circle", tint: .secondary) {
                        Text("Not checked · \(verification.notChecked.count)").lineLimit(1)
                    }
                }
                if !verification.activity.isEmpty {
                    row(.activity, symbol: "list.bullet.rectangle", tint: .secondary) {
                        Text("What the agent did")
                    } trailing: {
                        Text("\(verification.activity.count) steps · read-only").font(.caption).foregroundStyle(
                            .secondary)
                    }
                }
            } else if !isVerifying, verificationError == nil {
                Text("Checks in logs and monitoring whether the stage deployed and what the change does there.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 12)
            }
            if let verificationError { errorLabel(verificationError).padding(.trailing, 12) }
        }
    }

    /// The stage failed or the AI check found problems: fixing is one click away.
    private var hasProblem: Bool { stage.state == .failed || verification?.verdict == .problems }

    private var buttons: some View {
        HStack(spacing: 8) {
            if let askAI = actions.askAI {
                Button(action: askAI) { Label("Ask AI about this", systemImage: "sparkles") }
                    .controlSize(.small)
            }
            if let openSession = actions.openSession {
                let menu = Menu {
                    Button("In Sylvra's Terminal", systemImage: "terminal") { openSession(false) }
                    Button("In the External Terminal", systemImage: "macwindow") { openSession(true) }
                } label: {
                    Label(hasProblem ? "Fix with Claude Code" : "Open Claude Session", systemImage: "terminal")
                } primaryAction: {
                    openSession(false)
                }
                .controlSize(.small)
                .fixedSize()
                .help("An interactive Claude Code session with this stage, its errors and the AI check as context")
                if hasProblem { menu.buttonStyle(.borderedProminent) } else { menu }
            }
        }
        .padding(.trailing, 12)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
            .padding(.top, 6).padding(.bottom, 2)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(SylvraColor.statusCritical)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A selectable row: when selected it takes the pane's colour and runs to the pane's edge.
    private func row<Content: View, Trailing: View>(
        _ target: DeliveryItem, symbol: String, tint: Color, @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        let isSelected = target == item
        return Button {
            actions.select(target)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(tint).frame(width: 14)
                content()
                Spacer(minLength: 4)
                trailing()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? SylvraColor.brandPrimary : .clear)
            }
            .padding(.vertical, 6)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? StageDetailsView.paneColor : .clear,
                in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
