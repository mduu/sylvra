import DesignSystem
import SwiftUI

extension StageVerification.Verdict {
    var symbol: String {
        switch self {
        case .healthy: "checkmark.seal.fill"
        case .problems: "exclamationmark.triangle.fill"
        case .unchecked: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .healthy: .green
        case .problems: SylvraColor.statusCritical
        case .unchecked: .secondary
        }
    }
}

extension StageVerification.Check.Outcome {
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .problem: "xmark.octagon.fill"
        case .unchecked: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .ok: .green
        case .problem: SylvraColor.statusCritical
        case .unchecked: .secondary
        }
    }
}

/// What the stage card passes down for the AI check of its stage.
struct VerificationState {
    var result: StageVerification?
    var isRunning = false
    var error: String?
    /// Starts (or repeats) the check; `nil`: no agent, or the stage cannot be checked yet.
    var verify: (() -> Void)?
    /// Opens an interactive agent session about the stage.
    var openSession: (() -> Void)?
}

/// The AI check of a stage: verdict, what was looked at with its evidence, and what could not be checked
/// (pure). AI content: marked with the AI accent.
struct VerificationView: View {
    let state: VerificationState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("AI check", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AIAccent.border)
                if let result = state.result {
                    Text(
                        result.isSecondLook
                            ? "second look \(result.checkedAt.formatted(date: .omitted, time: .shortened))"
                            : result.checkedAt.formatted(date: .omitted, time: .shortened)
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if state.isRunning {
                    ProgressView().controlSize(.mini)
                    Text("Checking…").font(.caption).foregroundStyle(.secondary)
                } else if let verify = state.verify {
                    Button(state.result == nil ? "Check with AI" : "Check Again", action: verify)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            if let result = state.result { content(result) }
            if let error = state.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(SylvraColor.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.result == nil, state.error == nil, !state.isRunning {
                Text("Checks in logs and monitoring whether the stage deployed and what the change does there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let openSession = state.openSession, state.result != nil {
                Button(action: openSession) { Label("Open Claude Session", systemImage: "terminal") }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("An interactive Claude Code session in the terminal with this stage and its check as context")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIAccent.lineGradient(opacity: 0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AIAccent.border.opacity(0.4)))
    }

    @ViewBuilder private func content(_ result: StageVerification) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: result.verdict.symbol).foregroundStyle(result.verdict.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.verdict.title).aiFont(.callout, weight: .semibold)
                Text(result.summary).aiFont(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        if !result.intent.isEmpty {
            Text("Change: \(result.intent)")
                .aiFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(result.checks) { check in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: check.outcome.symbol)
                    .font(.caption)
                    .foregroundStyle(check.outcome.tint)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.title).aiFont(.callout, weight: .medium)
                    Text(check.finding).aiFont(.callout).fixedSize(horizontal: false, vertical: true)
                    if let evidence = check.evidence, !evidence.isEmpty {
                        Text(evidence)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .textSelection(.enabled)
        }
        if !result.notChecked.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Not checked").aiFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                ForEach(result.notChecked, id: \.self) { point in
                    Text("· \(point)").aiFont(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    let stage = DeliveryStage(id: "prod", name: "prod", kind: .environment, workflow: "Deploy", state: .succeeded)
    return VStack(spacing: 12) {
        VerificationView(
            state: .init(result: DemoDeliveryVerifier.verification(for: stage), verify: {}, openSession: {}))
        VerificationView(state: .init(isRunning: true))
        VerificationView(state: .init(error: "Claude Code is not installed", verify: {}))
    }
    .padding()
    .frame(width: 360)
}
