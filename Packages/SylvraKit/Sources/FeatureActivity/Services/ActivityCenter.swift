import AppKit
import Foundation
import Observation
import SylvraCore
import UserNotifications

/// Background work the user should see (see specs/architecture.md §11).
public struct ActivityJob: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case aiReview, checkout, refresh, replies
        /// Reviews and comments on the user's own pull requests; their checks finishing.
        case ownFeedback, ownChecks
        /// A merged pull request on its way to production.
        case delivery

        public var title: String {
            switch self {
            case .aiReview: String(localized: "AI reviews")
            case .checkout: String(localized: "Opening in IDE")
            case .refresh: String(localized: "Refreshing pull requests")
            case .replies: String(localized: "Replies after your comments")
            case .ownFeedback: String(localized: "Reviews and comments on your pull requests")
            case .ownChecks: String(localized: "Checks finished on your pull requests")
            case .delivery: String(localized: "Deployments of merged pull requests")
            }
        }
    }

    public let id: String
    public let kind: Kind
    public let title: String
    /// How far it got, e.g. "2 of 3 agents".
    public var detail: String?
    /// The pull request it works on: the activity list opens it.
    public var pullRequest: PullRequestID?
    /// When it started (kept when the job is updated).
    public var startedAt: Date

    public init(
        id: String, kind: Kind, title: String, detail: String? = nil, pullRequest: PullRequestID? = nil,
        startedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.pullRequest = pullRequest
        self.startedAt = startedAt
    }
}

/// A job that ended, with how long it ran.
public struct FinishedActivity: Identifiable, Hashable, Sendable {
    public let job: ActivityJob
    public let endedAt: Date
    /// What came out of it ("7 findings").
    public let message: String?

    public var id: String { "\(job.id)@\(endedAt.timeIntervalSince1970)" }
    public var duration: TimeInterval { endedAt.timeIntervalSince(job.startedAt) }
}

/// Tracks running jobs and posts a macOS notification when one finishes while Sylvra is in the background.
@MainActor
@Observable
public final class ActivityCenter {
    public private(set) var running: [ActivityJob] = []
    /// The latest finished jobs, newest first (only those that take a while: AI reviews and checkouts).
    public private(set) var finished: [FinishedActivity] = []
    static let finishedLimit = 5
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isBusy: Bool { !running.isEmpty }

    /// Starts a job, or updates the running job with the same ID (title, progress).
    public func start(_ job: ActivityJob) {
        if let index = running.firstIndex(where: { $0.id == job.id }) {
            var updated = job
            updated.startedAt = running[index].startedAt
            if running[index] != updated { running[index] = updated }
        } else {
            running.append(job)
        }
    }

    /// Ends a job; notifies when the app is not active and notifications are enabled for the job kind.
    public func finish(_ id: String, message: String?, at now: Date = .now) {
        guard let job = running.first(where: { $0.id == id }) else { return }
        running.removeAll { $0.id == id }
        if job.kind == .aiReview || job.kind == .checkout {
            finished.insert(FinishedActivity(job: job, endedAt: now, message: message), at: 0)
            finished = Array(finished.prefix(Self.finishedLimit))
        }
        guard let message, !NSApplication.shared.isActive, notificationsEnabled(for: job.kind) else { return }
        Task { await Self.post(title: job.title, body: message) }
    }

    /// Someone acted on pull requests after the reviewer's last comment: one notification per pull request,
    /// also while Sylvra is in front (the reviewer may be looking at another pull request). A click opens it.
    public func notifyNewActivity(on pullRequests: [PullRequestSummary]) {
        guard notificationsEnabled(for: .replies) else { return }
        for pullRequest in pullRequests.prefix(5) {
            let title = String(localized: "New activity on \(pullRequest.id.repository) #\(pullRequest.id.number)")
            Task {
                await Self.post(
                    title: title, body: pullRequest.title, identifier: "activity-\(pullRequest.id)",
                    pullRequest: pullRequest.id.description)
            }
        }
    }

    /// Something happened on a pull request (a review, a finished check): one notification per pull request
    /// and kind, also while Sylvra is in front. A click opens the pull request.
    public func notify(_ kind: ActivityJob.Kind, about pullRequest: PullRequestSummary, message: String) {
        notify(kind, about: pullRequest.id, title: pullRequest.title, message: message)
    }

    /// The same for a pull request known by its ID and title only.
    public func notify(_ kind: ActivityJob.Kind, about id: PullRequestID, title: String, message: String) {
        guard notificationsEnabled(for: kind) else { return }
        Task {
            await Self.post(
                title: "\(id.repository) #\(id.number): \(message)", body: title,
                identifier: "\(kind.rawValue)-\(id)-\(message)", pullRequest: id.description)
        }
    }

    // MARK: Settings

    public func notificationsEnabled(for kind: ActivityJob.Kind) -> Bool {
        defaults.object(forKey: Self.key(kind)) as? Bool ?? (kind != .refresh)
    }

    public func setNotificationsEnabled(_ enabled: Bool, for kind: ActivityJob.Kind) {
        defaults.set(enabled, forKey: Self.key(kind))
        if enabled {
            Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        }
    }

    private static func key(_ kind: ActivityJob.Kind) -> String { "notifications.\(kind.rawValue)" }

    private static func post(
        title: String, body: String, identifier: String = UUID().uuidString, pullRequest: String? = nil
    ) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let pullRequest { content.userInfo = [NotificationRouter.pullRequestKey: pullRequest] }
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}
