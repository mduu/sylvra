import AppKit
@preconcurrency import SwiftTerm

/// Handles the scroll wheel over Sylvra's terminals (SwiftTerm's own handling cannot be overridden): scrollback,
/// or — while a full-screen program runs — wheel events or arrow keys for it. See `TerminalWheelAction`.
@MainActor
final class TerminalScrollMonitor {
    private var monitor: Any?
    private var wheel = TerminalWheelAccumulator()
    private let views: () -> [TerminalView]

    init(views: @escaping () -> [TerminalView]) {
        self.views = views
    }

    func install() {
        guard monitor == nil else { return }
        // Local monitors run on the main thread.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let view = views().first(where: { Self.isUnderPointer($0, event) }) else { return false }
        let terminal = view.getTerminal()
        let rows = max(terminal.rows, 1)
        let lines = wheel.lines(
            for: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
            lineHeight: view.bounds.height / CGFloat(rows))
        let action = TerminalWheelAction(
            lines: lines, mouseReporting: view.allowMouseReporting && terminal.mouseMode != .off,
            alternateScreen: terminal.isCurrentBufferAlternate)
        switch action {
        case .scrollback(let lines):
            if lines > 0 { view.scrollUp(lines: lines) } else { view.scrollDown(lines: -lines) }
        case .mouseWheel(let up, let count):
            let point = view.convert(event.locationInWindow, from: nil)
            let col = min(max(Int(point.x / view.bounds.width * CGFloat(terminal.cols)), 0), terminal.cols - 1)
            let row = min(max(Int((view.bounds.height - point.y) / view.bounds.height * CGFloat(rows)), 0), rows - 1)
            let flags = terminal.encodeButton(
                button: up ? 4 : 5, release: false, shift: event.modifierFlags.contains(.shift),
                meta: event.modifierFlags.contains(.option), control: event.modifierFlags.contains(.control))
            for _ in 0..<count { terminal.sendEvent(buttonFlags: flags, x: col, y: row) }
        case .arrowKeys(let up, let count):
            let key =
                terminal.applicationCursor
                ? (up ? EscapeSequences.moveUpApp : EscapeSequences.moveDownApp)
                : (up ? EscapeSequences.moveUpNormal : EscapeSequences.moveDownNormal)
            for _ in 0..<count { view.send(key) }
        case nil:
            break
        }
        return true
    }

    private static func isUnderPointer(_ view: TerminalView, _ event: NSEvent) -> Bool {
        guard let window = view.window, window == event.window, !view.isHiddenOrHasHiddenAncestor else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }
}
