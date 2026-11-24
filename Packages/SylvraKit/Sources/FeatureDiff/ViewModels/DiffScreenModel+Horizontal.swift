import AppKit
import Foundation

extension DiffScreenModel {
    /// Width of one character of the diff's code font (monospaced 12.5 pt).
    static let codeCharacterWidth: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }()

    /// Characters of the longest line currently shown (tabs count as four).
    var longestShownLine: Int {
        var hasher = Hasher()
        hasher.combine(shownFiles.map(\.path))
        hasher.combine(scope.rawValue)
        hasher.combine(selectedCommit?.sha)
        hasher.combine(expandedPaths)
        hasher.combine(collapsedPaths)
        hasher.combine(fullFileHunks.keys.sorted())
        hasher.combine(revealedContext)
        let key = hasher.finalize()
        if let cache = longestLineCache, cache.key == key { return cache.length }
        let length =
            shownFiles.filter { !isCollapsed($0) }.lazy
            .flatMap { self.hunks(for: $0) }
            .flatMap(\.lines)
            .map { Self.displayLength(of: $0.text) }
            .max() ?? 0
        longestLineCache = (key, length)
        return length
    }

    /// Width the code of one row gets: the diff minus gutters, change bar and marker (per half side by side).
    nonisolated static func codeWidth(diffWidth: CGFloat, layout: Layout) -> CGFloat {
        switch layout {
        case .inline: diffWidth - inlineGutterWidth - 21
        case .sideBySide: (diffWidth - 44) / 2 - halfGutterWidth - 11
        }
    }

    /// The current scroll limit for a diff of `diffWidth`.
    public func maxHorizontalOffset(diffWidth: CGFloat) -> CGFloat {
        Self.maxHorizontalOffset(
            longestLine: longestShownLine, characterWidth: Self.codeCharacterWidth,
            codeWidth: Self.codeWidth(diffWidth: diffWidth, layout: layout))
    }

    nonisolated static func displayLength(of text: String) -> Int {
        text.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    /// How far the code can scroll: the longest line plus a little room, minus the visible code width.
    nonisolated static func maxHorizontalOffset(longestLine: Int, characterWidth: CGFloat, codeWidth: CGFloat)
        -> CGFloat
    {
        max(CGFloat(longestLine) * characterWidth + 32 - codeWidth, 0)
    }

    /// Scrolls the code sideways by `delta` points, kept within the longest line.
    public func scrollHorizontally(by delta: CGFloat, diffWidth: CGFloat) {
        let limit = maxHorizontalOffset(diffWidth: diffWidth)
        let target = min(max(horizontalOffset + delta, 0), limit)
        if target != horizontalOffset { horizontalOffset = target }
    }
}
