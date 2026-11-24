import Foundation
import Testing

@testable import FeatureActivity

/// Running jobs show since when they run; finished AI reviews and checkouts how long they took.
@MainActor
struct FinishedActivityTests {
    @Test func keepsTheStartAndListsFinishedReviews() throws {
        let center = ActivityCenter(defaults: try #require(UserDefaults(suiteName: "activity-\(UUID().uuidString)")))
        // No macOS notification from a test bundle.
        center.setNotificationsEnabled(false, for: .aiReview)
        let start = Date(timeIntervalSince1970: 1000)
        center.start(ActivityJob(id: "ai-review", kind: .aiReview, title: "AI review", startedAt: start))
        center.start(ActivityJob(id: "ai-review", kind: .aiReview, title: "AI review", detail: "1 of 2 agents"))
        #expect(center.running.first?.startedAt == start)
        center.finish("ai-review", message: "7 findings", at: start.addingTimeInterval(161))
        #expect(center.finished.first?.duration == 161)
        #expect(center.finished.first?.message == "7 findings")
        // Quick jobs don't fill the list.
        center.start(ActivityJob(id: "refresh", kind: .refresh, title: "Refreshing"))
        center.finish("refresh", message: nil)
        #expect(center.finished.count == 1)
        #expect(ActivityJobRow.format(161) == "2:41")
    }
}
