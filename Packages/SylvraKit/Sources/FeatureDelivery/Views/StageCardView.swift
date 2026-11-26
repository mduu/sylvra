import DesignSystem
import SwiftUI

/// What GitHub reports for one stage: its jobs, what failed, and what the reviewer can do (pure).
struct StageCardView: View {
    let stage: DeliveryStage
    var isApproving = false
    var approvalError: String?
    /// Approves the waiting deployment (`nil`: not possible for the signed-in user).
    var approve: (() -> Void)?
    var askAI: (() -> Void)?
    let open: (URL?) -> Void
    var now = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if stage.state == .needsApproval { approval }
            if !stage.jobs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(stage.jobs) { job in
                        DeliveryJobRowView(job: job) { open(job.url) }
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    open(stage.url)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.right.square")
                }
                .disabled(stage.url == nil)
                if let askAI {
                    Button(action: askAI) { Label("Ask AI about this", systemImage: "sparkles") }
                        .tint(SylvraColor.brandPrimary)
                }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SylvraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(stage.state.tint.opacity(0.35), lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: stage.state.symbol).foregroundStyle(stage.state.tint).font(.callout.weight(.bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(stage.name).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(stage.state.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(stage.state.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(stage.state.tint.opacity(0.12), in: Capsule())
        }
    }

    /// "Build workflow · 4 min 20 s · finished 14:32".
    private var subtitle: String {
        var parts: [String] = []
        if let workflow = stage.workflow, workflow != stage.name { parts.append(workflow) }
        if stage.workflow == nil, stage.kind == .environment {
            parts.append(String(localized: "Reported as a deployment"))
        }
        if let duration = stage.duration, stage.state.isFinished {
            parts.append(deliveryDurationText(duration))
        } else if let startedAt = stage.startedAt, stage.state == .running {
            parts.append(String(localized: "for \(deliveryDurationText(now.timeIntervalSince(startedAt)))"))
        }
        if let finishedAt = stage.finishedAt {
            parts.append(finishedAt.formatted(date: .omitted, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var approval: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                approve == nil
                    ? "This deployment waits for an approval by one of the environment's reviewers."
                    : "This deployment waits for your approval."
            )
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            if let approve {
                HStack(spacing: 8) {
                    Button("Approve Deployment…", action: approve)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isApproving)
                    if isApproving { ProgressView().controlSize(.small) }
                }
            }
            if let approvalError {
                Label(approvalError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(SylvraColor.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One job with its duration; a failed job shows the failed steps and what it reported (pure).
struct DeliveryJobRowView: View {
    let job: DeliveryJob
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: job.state.symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(job.state.tint)
                    .frame(width: 14)
                    .accessibilityLabel(job.state.title)
                Text(job.name).lineLimit(1)
                Spacer(minLength: 4)
                Text(job.duration.map(deliveryDurationText) ?? job.state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(action: open) { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
                    .disabled(job.url == nil)
                    .help("Open job on GitHub")
            }
            if !job.failedSteps.isEmpty || !job.errors.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(job.failedSteps, id: \.self) { step in
                        Text("Failed step: \(step)").font(.caption.weight(.medium))
                    }
                    ForEach(job.errors, id: \.self) { error in
                        Text(error)
                            .font(.caption.monospaced())
                            .lineLimit(6)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SylvraColor.statusCritical.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 1)
    }
}

#Preview {
    let failed = DeliveryStage(
        id: "test", name: "test", kind: .environment, workflow: "Deploy", state: .failed,
        jobs: [
            DeliveryJob(id: "1", name: "Deploy test", state: .succeeded, startedAt: .now - 300, finishedAt: .now - 200),
            DeliveryJob(
                id: "2", name: "Migrate database", state: .failed, startedAt: .now - 200, finishedAt: .now - 150,
                failedSteps: ["Run migrations"],
                errors: ["Process completed with exit code 1.", "relation \"invoices\" already exists"]),
        ], startedAt: .now - 300, finishedAt: .now - 150, url: URL(string: "https://github.com"))
    let waiting = DeliveryStage(
        id: "prod", name: "prod", kind: .environment, workflow: "Deploy", state: .needsApproval,
        approval: .init(workflowRunID: "r", environmentID: "e", viewerCanApprove: true))
    return VStack(spacing: 12) {
        StageCardView(stage: failed, askAI: {}, open: { _ in })
        StageCardView(stage: waiting, approve: {}, open: { _ in })
    }
    .padding()
    .frame(width: 360)
}
