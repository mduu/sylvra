import SwiftUI

/// The AI accent, reserved exclusively for AI-generated content (see specs/ux.md §3.1).
public enum AIAccent {
    public static let colors: [Color] = [
        Color(red: 0.70, green: 0.60, blue: 0.95),
        Color(red: 0.43, green: 0.47, blue: 0.94),
        Color(red: 0.35, green: 0.78, blue: 0.78),
    ]

    /// Horizontal gradient that fades out slowly to the right (line highlights): the colors stay visible
    /// across most of the line and a trace remains at the end.
    public static func lineGradient(opacity: Double) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: colors[0].opacity(opacity), location: 0),
                .init(color: colors[1].opacity(opacity * 0.8), location: 0.5),
                .init(color: colors[2].opacity(opacity * 0.55), location: 0.85),
                .init(color: colors[2].opacity(opacity * 0.3), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
    }

    /// Border gradient for the selected finding (with a touch of gold).
    public static var border: LinearGradient {
        LinearGradient(
            colors: [SylvraColor.accentGold] + colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Border of the box around an AI finding's lines in the diff: violet on the left, teal on the right;
    /// the selected finding starts in gold.
    public static func boxBorder(isSelected: Bool) -> LinearGradient {
        LinearGradient(
            colors: isSelected ? [SylvraColor.accentGold] + colors : colors, startPoint: .leading,
            endPoint: .trailing)
    }

    /// Card background tint.
    public static var cardBackground: LinearGradient {
        LinearGradient(
            colors: [colors[0].opacity(0.16), colors[2].opacity(0.06)], startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }
}
