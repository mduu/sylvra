import AppKit
import Foundation
import Observation
import UserNotifications

/// Background work the user should see (see specs/architecture.md §11).
public struct ActivityJob: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case aiReview, checkout, refresh

        public var title: String {
            switch self {
            case .aiReview: String(localized: "AI reviews")
            case .checkout: String(localized: "Opening in IDE")
            case .refresh: String(localized: "Refreshing pull requests")
            }
        }
    }

    public let id: String
    public let kind: Kind
    public let title: String

    public init(id: String, kind: Kind, title: String) {
        self.id = id
        self.kind = kind
        self.title = title
    }
}

/// Tracks running jobs and posts a macOS notification when one finishes while Sylvra is in the background.
@MainActor
@Observable
public final class ActivityCenter {
    public private(set) var running: [ActivityJob] = []
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isBusy: Bool { !running.isEmpty }

    public func start(_ job: ActivityJob) {
        guard !running.contains(job) else { return }
        running.append(job)
    }

    /// Ends a job; notifies when the app is not active and notifications are enabled for the job kind.
    public func finish(_ id: String, message: String?) {
        guard let job = running.first(where: { $0.id == id }) else { return }
        running.removeAll { $0.id == id }
        guard let message, !NSApplication.shared.isActive, notificationsEnabled(for: job.kind) else { return }
        Task { await Self.post(title: job.title, body: message) }
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

    private static func post(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
