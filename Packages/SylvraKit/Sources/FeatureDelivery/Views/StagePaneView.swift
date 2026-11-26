import DesignSystem
import SwiftUI

/// The right side of a stage's details (pure): what the selected row stands for, with a path saying where it
/// belongs ("dev › AI check › New errors").
struct StagePaneView: View {
    let stage: DeliveryStage
    let item: DeliveryItem?
    let verification: StageVerification?
    let logs: [Int: LogState]
    let actions: StageDetailsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch item {
            case .job(let id):
                if let job = stage.jobs.first(where: { $0.id == id }) { jobPane(job) }
            case .check(let title):
                if let check = verification?.checks.first(where: { $0.title == title }) {
                    CheckEvidenceView(check: check, path: path(String(localized: "AI check")))
                }
            case .notChecked:
                pathView(path(String(localized: "AI check")), title: String(localized: "Not checked"))
                ForEach(verification?.notChecked ?? [], id: \.self) { point in
                    Label(point, systemImage: "questionmark.circle").aiFont(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .activity:
                pathView(path(String(localized: "AI check")), title: String(localized: "What the agent did"))
                Text("Every tool call of the check, in order. The agent only reads.")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array((verification?.activity ?? []).enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .trailing)
                                Text(step).font(.caption.monospaced()).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            case nil:
                Text("Select a job or a check.").foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func path(_ part: String) -> String { "\(stage.name) › \(part)" }

    private func pathView(_ path: String, title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(path) ›").font(.caption).foregroundStyle(.secondary)
            Text(title).font(.headline)
        }
    }

    @ViewBuilder private func jobPane(_ job: DeliveryJob) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(stage.name) › job ›").font(.caption).foregroundStyle(.secondary)
            Text(job.name).font(.headline)
            Text(job.state.title).font(.caption.weight(.medium)).foregroundStyle(job.state.tint)
            Spacer(minLength: 4)
            Button("Open on GitHub") { actions.open(job.url) }.buttonStyle(.link).font(.caption)
                .disabled(job.url == nil)
        }
        if !job.steps.isEmpty { StepStripView(steps: job.steps) }
        if !job.errors.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(job.errors, id: \.self) { error in
                    Text(error).font(.caption.monospaced()).foregroundStyle(SylvraColor.statusCritical)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if let number = job.jobID {
            switch logs[number] {
            case .loaded(let log):
                JobLogView(log: log)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption)
                    .foregroundStyle(SylvraColor.statusCritical)
                Button("Try Again") { actions.loadLog(number) }.controlSize(.small)
            case .loading, nil:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        } else {
            Text("GitHub keeps no log for this job.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A job's steps as a strip of segments: done, running, waiting, failed (pure).
private struct StepStripView: View {
    let steps: [JobStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(steps, id: \.number) { step in
                    Capsule()
                        .fill(color(step.state))
                        .frame(height: 5)
                        .help("\(step.number). \(step.name) — \(step.state.title)")
                }
            }
            if let current = steps.first(where: { $0.state == .running || $0.state == .failed }) {
                Text("Step \(current.number) of \(steps.count): \(current.name)")
                    .font(.caption).foregroundStyle(current.state.tint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ state: StageState) -> Color {
        switch state {
        case .waiting, .skipped, .cancelled: Color.secondary.opacity(0.3)
        default: state.tint
        }
    }
}

/// A log excerpt in a code box; *Show all* opens the rest (pure but for that switch).
struct JobLogView: View {
    let log: JobLog
    @State private var showsAll = false

    var body: some View {
        let lines = showsAll ? log.lines[...] : log.lines[log.excerpt]
        VStack(alignment: .leading, spacing: 6) {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(line.time).foregroundStyle(.tertiary)
                            Text(line.text)
                                .foregroundStyle(color(line.kind))
                                .fontWeight(line.kind == .heading ? .semibold : .regular)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
                .padding(10)
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SylvraColor.codeSurface, in: RoundedRectangle(cornerRadius: 6))
            if log.hiddenCount > 0 {
                Button(showsAll ? "Show Excerpt" : "Show All \(log.lines.count) Lines") {
                    withAnimation(.snappy) { showsAll.toggle() }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private func color(_ kind: JobLog.Line.Kind) -> Color {
        switch kind {
        case .plain: .primary
        case .heading: SylvraColor.brandPrimary
        case .error: SylvraColor.statusCritical
        case .warning: SylvraColor.statusWarning
        }
    }
}

/// A check of the AI check with its evidence: the query, the figures before and after, the telling lines.
/// AI content: marked with the AI accent (pure).
struct CheckEvidenceView: View {
    let check: StageVerification.Check
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(path) ›").font(.caption).foregroundStyle(.secondary)
                Image(systemName: check.outcome.symbol).foregroundStyle(check.outcome.tint)
                Text(check.title).font(.headline)
                Spacer(minLength: 4)
                if let evidence = check.evidence {
                    Text(evidence).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text(check.finding).aiFont(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if let query = check.query, !query.isEmpty {
                Text(query)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SylvraColor.codeSurface, in: RoundedRectangle(cornerRadius: 6))
            }
            if check.before != nil || check.after != nil {
                HStack(spacing: 0) {
                    figure(String(localized: "Before the deployment"), check.before)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.horizontal, 12)
                    figure(String(localized: "Since"), check.after)
                }
            }
            if !check.excerpt.isEmpty {
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(check.excerpt.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11, design: .monospaced)).lineLimit(1).fixedSize()
                        }
                    }
                    .padding(10)
                    .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(SylvraColor.codeSurface, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(AIAccent.lineGradient(opacity: 0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AIAccent.border.opacity(0.35)))
    }

    private func figure(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "–").font(.title3.weight(.semibold).monospacedDigit())
        }
    }
}

#Preview {
    let delivery = DemoDeliveryLoader.delivery(for: .init(owner: "acme", repository: "billing", number: 812))
    let stage = delivery.stages[1]
    let check = DemoDeliveryVerifier.verification(for: stage)
    StagePaneView(
        stage: stage, item: .check("Effect of the change"), verification: check, logs: [:],
        actions: StageDetailsActions(select: { _ in }, open: { _ in }, loadLog: { _ in })
    )
    .frame(width: 700, height: 420)
}
