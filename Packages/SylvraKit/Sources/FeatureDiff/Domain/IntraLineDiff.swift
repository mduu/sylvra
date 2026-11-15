import Foundation

/// Word-level changes between paired removed/added lines (see specs/ux.md §7.2).
public enum IntraLineDiff {
    /// Pairs each run of removed lines with the following run of added lines and marks the changed tokens.
    static func annotate(_ hunk: Hunk) -> Hunk {
        var lines = hunk.lines
        var index = 0
        while index < lines.count {
            guard lines[index].kind == .removed else {
                index += 1
                continue
            }
            let removedStart = index
            while index < lines.count, lines[index].kind == .removed { index += 1 }
            let addedStart = index
            while index < lines.count, lines[index].kind == .added { index += 1 }
            let pairs = min(addedStart - removedStart, index - addedStart)
            for offset in 0..<pairs {
                let (old, new) = highlights(
                    old: lines[removedStart + offset].text, new: lines[addedStart + offset].text)
                lines[removedStart + offset].highlights = old
                lines[addedStart + offset].highlights = new
            }
        }
        var result = hunk
        result.lines = lines
        return result
    }

    /// Changed character ranges (UTF-16 offsets) of `old` and `new`.
    /// Lines that are completely different get no highlight (the whole line is changed anyway).
    public static func highlights(old: String, new: String) -> (old: [Range<Int>], new: [Range<Int>]) {
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)
        guard oldTokens.count * newTokens.count <= 250_000 else { return ([], []) }

        let common = longestCommonSubsequence(oldTokens.map(\.text), newTokens.map(\.text))
        let oldChanged = changedRanges(oldTokens, keep: common.old)
        let newChanged = changedRanges(newTokens, keep: common.new)

        let unchangedShare = Double(common.old.count) / Double(max(oldTokens.count, newTokens.count, 1))
        if unchangedShare < 0.3 { return ([], []) }
        return (oldChanged, newChanged)
    }

    struct Token {
        let text: Substring
        let range: Range<Int>
    }

    /// Splits into identifiers/numbers, whitespace runs and single punctuation characters.
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var offset = 0
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            var end = text.index(after: index)
            let isWord = character.isLetter || character.isNumber || character == "_"
            if isWord || character.isWhitespace {
                while end < text.endIndex {
                    let next = text[end]
                    let sameClass = isWord ? (next.isLetter || next.isNumber || next == "_") : next.isWhitespace
                    guard sameClass else { break }
                    end = text.index(after: end)
                }
            }
            let substring = text[index..<end]
            let length = substring.utf16.count
            tokens.append(Token(text: substring, range: offset..<(offset + length)))
            offset += length
            index = end
        }
        return tokens
    }

    private static func longestCommonSubsequence(_ lhs: [Substring], _ rhs: [Substring]) -> (
        old: Set<Int>, new: Set<Int>
    ) {
        let rows = lhs.count
        let columns = rhs.count
        var table = [[Int]](repeating: [Int](repeating: 0, count: columns + 1), count: rows + 1)
        for row in stride(from: rows - 1, through: 0, by: -1) {
            for column in stride(from: columns - 1, through: 0, by: -1) {
                table[row][column] =
                    lhs[row] == rhs[column]
                    ? table[row + 1][column + 1] + 1 : max(table[row + 1][column], table[row][column + 1])
            }
        }
        var old = Set<Int>()
        var new = Set<Int>()
        var row = 0
        var column = 0
        while row < rows, column < columns {
            if lhs[row] == rhs[column] {
                old.insert(row)
                new.insert(column)
                row += 1
                column += 1
            } else if table[row + 1][column] >= table[row][column + 1] {
                row += 1
            } else {
                column += 1
            }
        }
        return (old, new)
    }

    /// Merges adjacent changed tokens into ranges.
    private static func changedRanges(_ tokens: [Token], keep: Set<Int>) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for (index, token) in tokens.enumerated() where !keep.contains(index) {
            if let last = ranges.last, last.upperBound == token.range.lowerBound {
                ranges[ranges.count - 1] = last.lowerBound..<token.range.upperBound
            } else {
                ranges.append(token.range)
            }
        }
        return ranges
    }
}
