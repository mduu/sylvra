import Foundation
import SylvraCore
import UserNotifications

/// Shows Sylvra's notifications also while the app is in front and opens the pull request a clicked
/// notification is about.
public final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let pullRequestKey = "pullRequest"

    /// Opens a pull request (set once by the app at launch, called on the main actor).
    @MainActor public var open: ((PullRequestID) -> Void)?

    public override init() {
        super.init()
    }

    /// Becomes the delegate of the notification center.
    @MainActor public func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let text = response.notification.request.content.userInfo[Self.pullRequestKey] as? String,
            let id = PullRequestID(text)
        else { return }
        await MainActor.run { open?(id) }
    }
}
