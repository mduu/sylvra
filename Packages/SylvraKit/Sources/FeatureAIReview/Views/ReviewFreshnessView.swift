import DesignSystem
import SwiftUI
import SylvraCore

/// Which state of the pull request the AI review saw (pure): a clear hint with *Run again* when new commits
/// arrived since, otherwise when it ran and a quiet *Run again*.
struct ReviewFreshnessView: View {
    let isOutdated: Bool
    let reviewedAt: Date?
    /// How long the review took and what it used.
    var duration: TimeInterval?
    var tokens: TokenUsage?
    var isEnabled = true
    let runAgain: () -> Void

    var body: some View {
        if isOutdated {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New commits since this review").aiFont(.caption, weight: .semibold)
                    Text("Findings may point at code that changed.").aiFont(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("Run again", action: runAgain)
                    .buttonStyle(.borderedProminent)
                    .tint(SylvraColor.brandPrimary)
                    .controlSize(.small)
                    .disabled(!isEnabled)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(spacing: 6) {
                if let reviewedAt {
                    Text("Reviewed \(reviewedAt, format: .relative(presentation: .named))")
                        .aiFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let cost = costText {
                    Text(verbatim: "· " + cost)
                        .aiFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(tokens?.breakdown ?? "")
                }
                Spacer(minLength: 4)
                Button("Run again", systemImage: "arrow.clockwise", action: runAgain)
                    .buttonStyle(.borderless)
                    .aiFont(.caption)
                    .disabled(!isEnabled)
                    .help("Review the pull request again with the current diff (⌘⇧R)")
            }
        }
    }
}

extension ReviewFreshnessView {
    /// `took 2:41 · 380k tokens`
    var costText: String? {
        let parts = [
            duration.map { String(localized: "took \(ElapsedTime.format($0))") }, tokens.map(\.label),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Below the finished steps: how long the whole review ran and the tokens all its steps used (pure).
struct ReviewTotalView: View {
    let duration: TimeInterval?
    let tokens: TokenUsage?

    var body: some View {
        if duration != nil || tokens != nil {
            HStack(spacing: 8) {
                Image(systemName: "sum").foregroundStyle(.secondary)
                Text("Total").aiFont(.caption, weight: .semibold)
                Spacer()
                if let tokens {
                    Text(verbatim: TokenUsage.abbreviated(tokens.total))
                        .aiFont(.caption, weight: .semibold)
                        .monospacedDigit()
                        .help(tokens.breakdown)
                }
                if let duration {
                    Text(verbatim: ElapsedTime.format(duration)).aiFont(.caption, weight: .semibold).monospacedDigit()
                }
            }
            .padding(.top, 4)
            .overlay(alignment: .top) { Divider() }
            .accessibilityElement(children: .combine)
        }
    }
}

/// How long the running review has been going, counting up (pure).
struct ReviewRunningTimeView: View {
    let started: Date

    var body: some View {
        TimelineView(.periodic(from: started, by: 1)) { context in
            Label {
                Text("Running for \(ElapsedTime.format(context.date.timeIntervalSince(started)))")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "timer")
            }
            .aiFont(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ReviewFreshnessView(isOutdated: true, reviewedAt: .now.addingTimeInterval(-7200)) {}
        ReviewFreshnessView(
            isOutdated: false, reviewedAt: .now.addingTimeInterval(-600), duration: 161,
            tokens: TokenUsage(input: 12_000, cacheRead: 340_000, output: 9_000)
        ) {}
        ReviewRunningTimeView(started: .now.addingTimeInterval(-72))
    }
    .padding()
    .frame(width: 340)
}

/// One review runs at a time: says which pull request it is for, shows it or replaces it with this one (pure).
struct OtherReviewRunningView: View {
    let pullRequest: PullRequestID
    let finished: Int
    let total: Int
    var show: (() -> Void)?
    let reviewHere: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Reviewing \(pullRequest.repository) #\(pullRequest.number)")
                    .aiFont(.caption, weight: .semibold)
                    .lineLimit(1)
                if total > 0 {
                    Text("\(finished) of \(total) agents").aiFont(.caption).foregroundStyle(.secondary)
                }
            }
            Text("One AI review runs at a time.").aiFont(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if let show { Button("Show", action: show).buttonStyle(.borderless) }
                Button("Stop It and Review This One", action: reviewHere)
                    .buttonStyle(.borderless)
                    .help("Cancels the running review and starts one for this pull request")
            }
            .aiFont(.caption)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SylvraColor.brandPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Another review running") {
    OtherReviewRunningView(
        pullRequest: PullRequestID(owner: "acme", repository: "billing", number: 881), finished: 2, total: 3,
        show: {}, reviewHere: {}
    )
    .padding()
    .frame(width: 320)
}
