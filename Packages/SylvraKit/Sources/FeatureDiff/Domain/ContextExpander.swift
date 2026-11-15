import Foundation

/// Reveals unchanged lines above hunks step by step ("+20 lines"), using the file at head.
public enum ContextExpander {
    /// Lines hidden above each hunk (the gap to the previous hunk or the file start).
    public static func hiddenAbove(_ hunks: [Hunk]) -> [Int] {
        var previousEnd = 1
        return hunks.map { hunk in
            defer { previousEnd = hunk.newStart + hunk.newCount }
            return max(hunk.newStart - previousEnd, 0)
        }
    }

    /// Hunks with `revealed[i]` context lines prepended to hunk `i` (clamped to its gap).
    public static func expand(_ hunks: [Hunk], revealed: [Int: Int], headLines: [String]) -> [Hunk] {
        let hidden = hiddenAbove(hunks)
        return hunks.enumerated().map { index, hunk in
            let count = min(revealed[index] ?? 0, hidden[index])
            guard count > 0 else { return hunk }
            let delta = hunk.oldStart - hunk.newStart  // constant for context above the hunk
            let context = ((hunk.newStart - count)..<hunk.newStart).compactMap { number -> DiffLine? in
                guard headLines.indices.contains(number - 1) else { return nil }
                return DiffLine(
                    kind: .context, oldNumber: number + delta, newNumber: number, text: headLines[number - 1])
            }
            return Hunk(
                oldStart: hunk.oldStart - context.count, oldCount: hunk.oldCount + context.count,
                newStart: hunk.newStart - context.count, newCount: hunk.newCount + context.count,
                section: hunk.section, lines: context + hunk.lines)
        }
    }
}
