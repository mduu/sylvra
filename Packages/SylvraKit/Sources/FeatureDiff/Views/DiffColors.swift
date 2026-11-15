import AppKit
import SwiftUI

/// Muted diff colors (not brand colors, see specs/ux.md §3.1).
enum DiffColors {
    static let addedBackground = Color.green.opacity(0.12)
    static let removedBackground = Color.red.opacity(0.11)
    static let addedHighlight = Color.green.opacity(0.32)
    static let removedHighlight = Color.red.opacity(0.30)
    static let hunkBackground = Color.secondary.opacity(0.08)
    static let emptyBackground = Color.secondary.opacity(0.04)

    static func background(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: addedBackground
        case .removed: removedBackground
        case .context: .clear
        }
    }

    static func highlight(_ kind: DiffLine.Kind) -> Color {
        kind == .added ? addedHighlight : removedHighlight
    }
}

extension DiffLine {
    /// The line's text with syntax colors and intra-line highlights applied.
    func attributedText(language: SyntaxHighlighter.Language) -> AttributedString {
        let tokens = SyntaxHighlighter.tokens(text, language: language)
        guard !highlights.isEmpty || !tokens.isEmpty else { return AttributedString(text) }
        let string = NSMutableAttributedString(string: text)
        let length = string.length
        func clamp(_ range: Range<Int>) -> NSRange? {
            let lower = max(0, min(range.lowerBound, length))
            let upper = max(lower, min(range.upperBound, length))
            return upper > lower ? NSRange(location: lower, length: upper - lower) : nil
        }
        for token in tokens {
            if let range = clamp(token.range) {
                string.addAttribute(.foregroundColor, value: SyntaxColors.color(token.kind), range: range)
            }
        }
        for highlight in highlights {
            if let range = clamp(highlight) {
                string.addAttribute(.backgroundColor, value: NSColor(DiffColors.highlight(kind)), range: range)
            }
        }
        return (try? AttributedString(string, including: \.appKit)) ?? AttributedString(text)
    }
}

/// Token colors that harmonize with the violet/gold brand (light and dark).
enum SyntaxColors {
    static func color(_ kind: SyntaxHighlighter.TokenKind) -> NSColor {
        switch kind {
        case .keyword: dynamic(light: 0x6C48C6, dark: 0xC9B5FF)
        case .type: dynamic(light: 0x0F7C74, dark: 0x7FD8D0)
        case .string: dynamic(light: 0xB4532A, dark: 0xF2A68C)
        case .number: dynamic(light: 0x9A6B12, dark: 0xF7DC86)
        case .comment: dynamic(light: 0x7A7290, dark: 0x8E82B0)
        case .attribute: dynamic(light: 0xA63A7A, dark: 0xF09AD0)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

extension EnvironmentValues {
    /// Language of the file being rendered (set by `DiffFileBodyView`).
    @Entry var syntaxLanguage: SyntaxHighlighter.Language = .plain
}
