import CoreGraphics

/// What turning the scroll wheel (or swiping on the trackpad) does in a terminal (pure).
///
/// SwiftTerm only moves its scrollback, which is empty while a full-screen program (an editor, a pager,
/// Claude Code) has the alternate screen. Like Terminal.app, the wheel then goes to the program: as wheel
/// events when it asked for the mouse, otherwise as arrow keys.
enum TerminalWheelAction: Equatable {
    /// Move the scrollback; positive is up.
    case scrollback(lines: Int)
    /// Report wheel clicks to the program.
    case mouseWheel(up: Bool, count: Int)
    /// Send arrow keys to the program.
    case arrowKeys(up: Bool, count: Int)

    /// `lines` is positive for up; `nil` when nothing is to be done.
    init?(lines: Int, mouseReporting: Bool, alternateScreen: Bool) {
        guard lines != 0 else { return nil }
        let up = lines > 0
        let count = abs(lines)
        if mouseReporting {
            self = .mouseWheel(up: up, count: count)
        } else if alternateScreen {
            self = .arrowKeys(up: up, count: count)
        } else {
            self = .scrollback(lines: lines)
        }
    }
}

/// Turns scroll deltas into whole lines, keeping the rest of a smooth trackpad swipe for the next event (pure).
struct TerminalWheelAccumulator {
    private var remainder: CGFloat = 0

    /// - Parameters:
    ///   - delta: the event's `scrollingDeltaY` (points for precise deltas, lines otherwise); positive is up.
    ///   - precise: whether the delta is in points (trackpad, Magic Mouse).
    ///   - lineHeight: the height of one terminal row in points.
    mutating func lines(for delta: CGFloat, precise: Bool, lineHeight: CGFloat) -> Int {
        let step = precise ? delta / max(lineHeight, 1) : delta
        // A new direction drops what is left of the old one.
        if step * remainder < 0 { remainder = 0 }
        remainder += step
        let lines = Int(remainder.rounded(.towardZero))
        remainder -= CGFloat(lines)
        return lines
    }
}
