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
    /// The line's text with intra-line highlights applied.
    var attributedText: AttributedString {
        guard !highlights.isEmpty else { return AttributedString(text) }
        let utf16 = Array(text.utf16)
        var result = AttributedString()
        var cursor = 0
        func piece(_ range: Range<Int>) -> AttributedString {
            let clamped = max(0, min(range.lowerBound, utf16.count))..<max(0, min(range.upperBound, utf16.count))
            return AttributedString(String(utf16CodeUnits: Array(utf16[clamped]), count: clamped.count))
        }
        for range in highlights where range.lowerBound >= cursor {
            result += piece(cursor..<range.lowerBound)
            var highlighted = piece(range)
            highlighted.backgroundColor = DiffColors.highlight(kind)
            result += highlighted
            cursor = range.upperBound
        }
        result += piece(cursor..<utf16.count)
        return result
    }
}
