import AppKit
import DesignSystem
import SwiftUI

/// Muted diff colors (not brand colors, see specs/ux.md §3.1).
enum DiffColors {
    static var added: Color { SylvraColor.diffAdded }
    static var removed: Color { SylvraColor.diffRemoved }
    static let emptyBackground = Color.secondary.opacity(0.04)

    static func accent(_ kind: DiffLine.Kind) -> Color? {
        switch kind {
        case .added: added
        case .removed: removed
        case .context: nil
        }
    }

    /// Soft gradient for changed lines: strongest at the gutter edge, fading into the code.
    static func background(_ kind: DiffLine.Kind) -> AnyShapeStyle {
        guard let accent = accent(kind) else { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    .init(color: accent.opacity(0.20), location: 0),
                    .init(color: accent.opacity(0.09), location: 0.35),
                    .init(color: accent.opacity(0.06), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing))
    }

    static func highlight(_ kind: DiffLine.Kind) -> Color {
        (kind == .added ? added : removed).opacity(0.38)
    }
}

extension DiffLine {
    /// The line's text with syntax colors and intra-line highlights applied.
    @MainActor
    func attributedText(language: SyntaxHighlighter.Language) -> AttributedString {
        AttributedTextCache.shared.text(for: self, language: language)
    }

    /// Uncached rendering (tokenising + highlights).
    func renderAttributedText(language: SyntaxHighlighter.Language) -> AttributedString {
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
                string.addAttribute(
                    .font, value: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold), range: range)
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
    /// The diff column is wide enough for threads under their own side-by-side half.
    @Entry var diffIsWide = true
    /// Find in diff: the query (≥ 2 characters) and the anchor of the current match.
    @Entry var diffSearchQuery = ""
    @Entry var diffCurrentMatch: String?
    /// Selects an AI finding when its highlight is clicked (set by the app, see `DiffScreenModel.selectFinding`).
    @Entry var diffSelectFinding: ((String) -> Void)?
}

/// Remembers rendered lines so scrolling and re-renders don't re-tokenise (bounded LRU-ish cache).
@MainActor
final class AttributedTextCache {
    static let shared = AttributedTextCache()
    private struct Key: Hashable {
        let line: DiffLine
        let language: SyntaxHighlighter.Language
    }

    private var storage: [Key: AttributedString] = [:]
    private let limit = 20_000

    func text(for line: DiffLine, language: SyntaxHighlighter.Language) -> AttributedString {
        let key = Key(line: line, language: language)
        if let cached = storage[key] { return cached }
        let text = line.renderAttributedText(language: language)
        if storage.count >= limit { storage.removeAll(keepingCapacity: true) }
        storage[key] = text
        return text
    }
}
