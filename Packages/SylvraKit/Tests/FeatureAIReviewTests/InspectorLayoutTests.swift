import Testing

@testable import FeatureAIReview

struct InspectorLayoutTests {
    /// Regression: the focused chat field's ring was clipped on the left by the scroll view.
    @Test func scrollContentLeavesRoomForFocusRings() {
        #expect(FindingsInspectorScreen.focusRingInset >= 3)
    }
}
