import DesignSystem
import SwiftUI

/// Banner above the diff: new pushes (refresh) and changes since the reviewer's last review (pure).
struct ReviewProgressBar: View {
    let progress: ReviewProgress?
    let hasNewCommits: Bool
    let isShowingSinceReview: Bool
    var showSinceReview: () -> Void = {}
    var showAll: () -> Void = {}
    var refresh: () -> Void = {}

    var body: some View {
        VStack(spacing: 6) {
            if hasNewCommits {
                bar(
                    icon: "arrow.triangle.2.circlepath", tint: SylvraColor.accentGold,
                    text: Text("New commits were pushed to this pull request.")
                ) {
                    Button("Refresh", action: refresh).buttonStyle(.borderedProminent).tint(SylvraColor.brandPrimary)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let progress, progress.hasChangesSinceReview || isShowingSinceReview {
                bar(icon: "clock.arrow.circlepath", tint: SylvraColor.brandPrimary, text: sinceText(progress)) {
                    if isShowingSinceReview {
                        Button("Show all changes", action: showAll)
                    } else {
                        Button("Show only these", action: showSinceReview)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private func sinceText(_ progress: ReviewProgress) -> Text {
        let when = progress.lastReviewedAt.map { Text($0, format: .relative(presentation: .named)) } ?? Text("earlier")
        return isShowingSinceReview
            ? Text("Only changes since your last review (\(when))")
            : Text("Changed since your last review (\(when))")
    }

    private func bar(icon: String, tint: Color, text: Text, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            text.font(.callout).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            actions().controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // Opaque: the diff scrolls underneath the banner, and code shining through made it hard to read.
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(SylvraColor.surfaceElevated)
                .overlay(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.12)))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(tint.opacity(0.3)))
    }
}

#Preview("Review progress") {
    VStack {
        ReviewProgressBar(
            progress: ReviewProgress(
                headSHA: "b", lastReviewedSHA: "a", lastReviewedAt: .now.addingTimeInterval(-90_000)),
            hasNewCommits: true, isShowingSinceReview: false)
        ReviewProgressBar(
            progress: ReviewProgress(
                headSHA: "b", lastReviewedSHA: "a", lastReviewedAt: .now.addingTimeInterval(-3_600)),
            hasNewCommits: false, isShowingSinceReview: true)
    }
    .frame(width: 640)
}
