import DesignSystem
import SwiftUI

extension StageState {
    var symbol: String {
        switch self {
        case .waiting: "clock"
        case .needsApproval: "hand.raised.fill"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark"
        case .failed: "xmark"
        case .cancelled: "slash.circle"
        case .skipped: "arrow.uturn.right"
        }
    }

    var tint: Color {
        switch self {
        case .waiting, .skipped, .cancelled: .secondary
        case .needsApproval: SylvraColor.statusWarning
        case .running: SylvraColor.brandPrimary
        case .succeeded: .green
        case .failed: SylvraColor.statusCritical
        }
    }
}

/// "3 min 20 s", for stage and job durations.
func deliveryDurationText(_ duration: TimeInterval) -> String {
    Duration.seconds(duration.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))
}
