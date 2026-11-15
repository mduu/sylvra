import SwiftUI
import SylvraCore

/// Small CI indicator (✓, ✕, ●).
public struct CheckStateBadge: View {
    private let state: CheckState

    public init(_ state: CheckState) {
        self.state = state
    }

    public var body: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .accessibilityLabel(Text(label))
                .help(label)
        }
    }

    private var symbol: String? {
        switch state {
        case .success: "checkmark"
        case .failure, .error: "xmark"
        case .pending, .expected: "circle.dotted"
        case .none: nil
        }
    }

    private var color: Color {
        switch state {
        case .success: .green
        case .failure, .error: .red
        default: SylvraColor.accentGold
        }
    }

    private var label: String {
        switch state {
        case .success: String(localized: "Checks passed")
        case .failure, .error: String(localized: "Checks failing")
        case .pending, .expected: String(localized: "Checks running")
        case .none: ""
        }
    }
}
