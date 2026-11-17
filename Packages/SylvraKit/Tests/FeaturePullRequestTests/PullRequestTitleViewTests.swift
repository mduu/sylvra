import Testing

@testable import FeaturePullRequest

@MainActor
struct PullRequestTitleViewTests {
    /// Regression: the title was cut off at a fixed 380 pt; wide windows give it far more room.
    @Test func titleGetsMoreRoomInWideWindows() {
        #expect(PullRequestTitleView.narrowWidth >= 380)
        #expect(PullRequestTitleView.wideWidth >= PullRequestTitleView.narrowWidth + 200)
    }
}
