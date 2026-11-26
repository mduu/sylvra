import DesignSystem
import SwiftUI

/// The delivery in one line, with the switch for following it in the background (pure).
struct DeliveryHeadlineView: View {
    let delivery: Delivery
    let isFollowing: Bool
    let toggleFollowing: () -> Void
    /// Followed deliveries are checked by the agent without a click (`nil`: no agent).
    var verifiesAutomatically: Binding<Bool>?
    var editNotes: (() -> Void)?
    var now = Date.now

    var body: some View {
        let state = delivery.overallState(at: now)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: state.symbol).foregroundStyle(state.tint).font(.callout.weight(.bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(delivery.headline(at: now)).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !delivery.isFinished(at: now) || isFollowing {
                Button(action: toggleFollowing) {
                    Image(systemName: isFollowing ? "bell.fill" : "bell")
                        .foregroundStyle(isFollowing ? SylvraColor.brandPrimary : .secondary)
                }
                .buttonStyle(.borderless)
                .help(
                    isFollowing
                        ? "Sylvra follows this delivery and notifies you per stage. Click to stop."
                        : "Follow this delivery: a notification when a stage is done, fails or needs approval"
                )
                .accessibilityLabel(isFollowing ? "Stop following the delivery" : "Follow the delivery")
            }
            if let verifiesAutomatically {
                Menu {
                    Toggle("Check Followed Deliveries with AI", isOn: verifiesAutomatically)
                    if let editNotes { Button("Monitoring Notes for This Repository…", action: editNotes) }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("AI check: options")
            }
        }
    }

    private var subtitle: String {
        let commit = String(delivery.mergeCommitSHA.prefix(7))
        guard let mergedAt = delivery.mergedAt else { return commit }
        return String(localized: "Merged \(mergedAt.formatted(.relative(presentation: .named))) · \(commit)")
    }
}
