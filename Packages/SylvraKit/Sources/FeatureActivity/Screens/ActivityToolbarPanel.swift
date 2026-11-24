import DesignSystem
import SwiftUI
import SylvraCore

/// Toolbar activity indicator with a popover listing running jobs (container).
public struct ActivityToolbarPanel: View {
    private let center: ActivityCenter
    private let open: ((PullRequestID) -> Void)?
    @State private var isShowingPopover = false

    /// - Parameter open: shows a job's pull request (its details, e.g. the AI review's agents, are there).
    public init(center: ActivityCenter, open: ((PullRequestID) -> Void)? = nil) {
        self.center = center
        self.open = open
    }

    public var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            ActivityIndicatorView(isBusy: center.isBusy)
        }
        .help(
            center.isBusy
                ? center.running.map(\.title).joined(separator: ", ") : String(localized: "No background work")
        )
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Background activity").font(.headline)
                if center.running.isEmpty {
                    Text("Nothing running.").foregroundStyle(.secondary)
                }
                ForEach(center.running) { job in
                    ActivityJobRow(job: job, open: job.pullRequest.flatMap { id in open.map { open in { open(id) } } })
                    {
                        isShowingPopover = false
                    }
                }
                if !center.finished.isEmpty {
                    Divider()
                    Text("Recently finished").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(center.finished) { activity in
                        FinishedActivityRow(
                            activity: activity,
                            open: activity.job.pullRequest.flatMap { id in open.map { open in { open(id) } } }
                        ) {
                            isShowingPopover = false
                        }
                    }
                }
            }
            .padding()
            .frame(minWidth: 240, alignment: .leading)
        }
    }
}

/// One running job; a job on a pull request opens it (pure).
struct ActivityJobRow: View {
    let job: ActivityJob
    var open: (() -> Void)?
    var didOpen: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.title).lineLimit(1)
                if let detail = job.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            TimelineView(.periodic(from: job.startedAt, by: 1)) { context in
                Text(verbatim: Self.format(context.date.timeIntervalSince(job.startedAt)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .help("Running since \(job.startedAt.formatted(date: .omitted, time: .shortened))")
            if let open {
                Button("Show", systemImage: "arrow.forward.circle") {
                    open()
                    didOpen()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show this pull request")
            }
        }
    }
}

extension ActivityJobRow {
    /// `0:42`, `2:41`, `1:05:12`
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}

/// A job that ended: how long it ran and when (pure).
struct FinishedActivityRow: View {
    let activity: FinishedActivity
    var open: (() -> Void)?
    var didOpen: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.job.title).lineLimit(1)
                Text(
                    "Took \(ActivityJobRow.format(activity.duration)) · \(activity.endedAt, format: .relative(presentation: .named))"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                if let message = activity.message {
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let open {
                Button("Show", systemImage: "arrow.forward.circle") {
                    open()
                    didOpen()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show this pull request")
            }
        }
    }
}

#Preview("Finished row") {
    FinishedActivityRow(
        activity: FinishedActivity(
            job: ActivityJob(
                id: "ai-review", kind: .aiReview, title: "AI review · billing #881",
                startedAt: .now.addingTimeInterval(-400)),
            endedAt: .now.addingTimeInterval(-240), message: "7 findings"),
        open: {}
    )
    .padding()
    .frame(width: 300)
}

#Preview("Job row") {
    ActivityJobRow(
        job: ActivityJob(
            id: "ai-review", kind: .aiReview, title: "AI review · billing #881", detail: "2 of 3 agents",
            pullRequest: PullRequestID(owner: "acme", repository: "billing", number: 881)),
        open: {}
    )
    .padding()
    .frame(width: 280)
}

/// A calm ring that turns into a rotating gold arc while work is running (pure).
struct ActivityIndicatorView: View {
    let isBusy: Bool
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.3), lineWidth: 2.5)
            if isBusy {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(SylvraColor.accentGold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { rotation = 360 }
                    }
            }
        }
        .frame(width: 15, height: 15)
        .accessibilityLabel(Text(isBusy ? "Working" : "Idle"))
    }
}

/// Notification toggles per job type (pure container for the settings window).
public struct NotificationSettingsView: View {
    private let center: ActivityCenter
    @State private var refreshToken = 0

    public init(center: ActivityCenter) {
        self.center = center
    }

    public var body: some View {
        Form {
            Section {
                ForEach(ActivityJob.Kind.allCases, id: \.self) { kind in
                    Toggle(
                        kind.title,
                        isOn: Binding(
                            get: {
                                _ = refreshToken; return center.notificationsEnabled(for: kind)
                            },
                            set: {
                                center.setNotificationsEnabled($0, for: kind)
                                refreshToken += 1
                            }))
                }
            } footer: {
                Text("Sylvra notifies you when background work finishes while the app is not in front.")
            }
        }
        .formStyle(.grouped)
    }
}
