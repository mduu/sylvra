import DesignSystem
import SwiftUI

/// Concentric rings of what is left (pure): outermost first. Plenty left shows the AI gradient, 20 % or less
/// orange, under 10 % red; an unknown value (`nil`) shows only the empty track.
public struct UsageRingsView: View {
    let remaining: [Double?]
    var lineWidth: CGFloat = 3
    var gap: CGFloat = 1.5

    public init(remaining: [Double?], lineWidth: CGFloat = 3, gap: CGFloat = 1.5) {
        self.remaining = remaining
        self.lineWidth = lineWidth
        self.gap = gap
    }

    public var body: some View {
        ZStack {
            ForEach(Array(remaining.enumerated()), id: \.offset) { index, value in
                let inset = CGFloat(index) * (lineWidth + gap) + lineWidth / 2
                Circle()
                    .inset(by: inset)
                    .stroke(SylvraColor.brandPrimary.opacity(0.16), lineWidth: lineWidth)
                if let value {
                    Circle()
                        .inset(by: inset)
                        .trim(from: 0, to: max(value, 0.005))
                        .stroke(Self.style(for: value), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .animation(.snappy, value: remaining)
    }

    static func style(for remaining: Double) -> AnyShapeStyle {
        switch ClaudeUsage.Level(remaining: remaining) {
        case .plenty: AnyShapeStyle(AIAccent.prominentFill)
        case .low: AnyShapeStyle(SylvraColor.statusWarning)
        case .critical: AnyShapeStyle(SylvraColor.statusCritical)
        }
    }

    static func color(for remaining: Double) -> Color {
        switch ClaudeUsage.Level(remaining: remaining) {
        case .plenty: SylvraColor.brandPrimary
        case .low: SylvraColor.statusWarning
        case .critical: SylvraColor.statusCritical
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        UsageRingsView(remaining: [0.82, 0.59, 0.76]).frame(width: 22, height: 22)
        UsageRingsView(remaining: [0.74, 0.17, 0.55], lineWidth: 6, gap: 3).frame(width: 64, height: 64)
        UsageRingsView(remaining: [0.41, 0.06, nil], lineWidth: 6, gap: 3).frame(width: 64, height: 64)
    }
    .padding()
}
