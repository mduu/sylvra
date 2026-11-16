import SwiftUI

/// Size of AI texts (chat, findings, summary), chosen in Settings → General. macOS ignores Dynamic Type, so
/// AI views use `aiFont` and scale with this setting. Stored under `ai.textSize` in UserDefaults.
public enum AITextSize: String, CaseIterable, Identifiable, Sendable {
    case standard, large, larger, largest

    public static let storageKey = "ai.textSize"

    public var id: String { rawValue }

    public var scale: CGFloat {
        switch self {
        case .standard: 1
        case .large: 1.15
        case .larger: 1.3
        case .largest: 1.5
        }
    }

    public var title: LocalizedStringKey {
        switch self {
        case .standard: "Standard"
        case .large: "Large"
        case .larger: "Larger"
        case .largest: "Largest"
        }
    }
}

extension EnvironmentValues {
    /// Factor for AI texts (see `AITextSize`), set once by the app.
    @Entry public var aiTextScale: CGFloat = 1
}

/// Point sizes of the macOS text styles AI views use, so they can be scaled.
public enum AIFontMetrics {
    public nonisolated static func pointSize(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
    }
}

private struct AIFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design?
    @Environment(\.aiTextScale) private var scale

    func body(content: Content) -> some View {
        content.font(.system(size: (size * scale).rounded(), weight: weight, design: design))
    }
}

extension View {
    /// A text style that grows with the AI text size setting.
    public func aiFont(
        _ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil
    ) -> some View {
        modifier(
            AIFontModifier(
                size: AIFontMetrics.pointSize(of: style), weight: weight ?? (style == .headline ? .bold : nil),
                design: design))
    }

    /// A fixed point size that grows with the AI text size setting.
    public func aiFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(AIFontModifier(size: size, weight: weight, design: design))
    }
}
