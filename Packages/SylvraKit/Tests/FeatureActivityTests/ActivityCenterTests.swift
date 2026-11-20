import Foundation
import Testing

@testable import FeatureActivity

@MainActor
struct ActivityCenterTests {
    private func center() -> ActivityCenter {
        ActivityCenter(defaults: UserDefaults(suiteName: "sylvra-activity-\(UUID().uuidString)")!)
    }

    @Test func tracksRunningJobs() {
        let center = center()
        let job = ActivityJob(id: "ai#1", kind: .aiReview, title: "AI review")
        center.start(job)
        center.start(job)
        #expect(center.running == [job])
        #expect(center.isBusy)
        center.finish("ai#1", message: nil)
        #expect(!center.isBusy)
    }

    @Test func startingARunningJobAgainUpdatesIt() {
        let center = center()
        center.start(ActivityJob(id: "ai-review", kind: .aiReview, title: "AI review · billing #1"))
        center.start(
            ActivityJob(id: "ai-review", kind: .aiReview, title: "AI review · billing #1", detail: "1 of 2 agents"))
        #expect(center.running.count == 1)
        #expect(center.running.first?.detail == "1 of 2 agents")
    }

    @Test func notificationDefaults() {
        let center = center()
        #expect(center.notificationsEnabled(for: .aiReview))
        #expect(!center.notificationsEnabled(for: .refresh))
        center.setNotificationsEnabled(false, for: .aiReview)
        #expect(!center.notificationsEnabled(for: .aiReview))
    }
}
