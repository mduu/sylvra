import AppKit
import Observation
import Platform

/// Remembers the window layout, column widths and window frames per screen combination (laptop only, 34",
/// 49", two 27"…) and restores them when the screens change or at launch.
///
/// While macOS rearranges windows after a screen change, the columns and windows report sizes that the
/// reviewer didn't choose; nothing is saved until the new setup has been applied.
@MainActor @Observable
final class DisplaySetupMonitor {
    static let shared = DisplaySetupMonitor()

    /// The setup whose layout is on screen.
    private(set) var setup: DisplaySetup
    @ObservationIgnored private var widths: [ColumnLayout.Column: CGFloat] = [:]
    @ObservationIgnored private let memory = DisplayLayoutMemory()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingChange: Task<Void, Never>?
    /// Windows whose frame was restored for the current setup (before that their frames aren't saved).
    @ObservationIgnored private var restoredWindows: Set<String> = []

    private init() {
        setup = DisplaySetup.current
        loadWidths()
    }

    func start() {
        guard observers.isEmpty else { return }
        restoreLayoutMode()
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            })
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let window = note.object as? NSWindow else { return }
                    MainActor.assumeIsolated { self?.windowChanged(window) }
                })
        }
        // Becoming visible (occlusion) or key: SwiftUI has placed the window by then.
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let window = note.object as? NSWindow else { return }
                    MainActor.assumeIsolated { self?.windowAppeared(window) }
                })
        }
    }

    // MARK: Columns

    /// The width a column starts with in the current setup.
    func width(_ column: ColumnLayout.Column) -> CGFloat {
        widths[column] ?? column.defaultWidth
    }

    func saveWidth(_ width: CGFloat, for column: ColumnLayout.Column) {
        guard isSettled, column.range.contains(width) else { return }
        memory.setNumber(Double(width.rounded()), column.memoryName, for: setup)
    }

    private func loadWidths() {
        for column in ColumnLayout.Column.allCases {
            let stored = memory.number(column.memoryName, for: setup).map { CGFloat($0) } ?? column.defaultWidth
            widths[column] = min(max(stored, column.range.lowerBound), column.range.upperBound)
        }
    }

    // MARK: Window layout

    func saveLayoutMode(_ mode: String) {
        guard isSettled, !isLayoutModeFromLaunchArgument else { return }
        memory.setText(mode, "mode", for: setup)
    }

    private func restoreLayoutMode() {
        guard !isLayoutModeFromLaunchArgument, let mode = memory.text("mode", for: setup),
            WindowLayout(rawValue: mode) != nil
        else { return }
        defaults.set(mode, forKey: WindowLayout.storageKey)
    }

    private var isLayoutModeFromLaunchArgument: Bool {
        defaults.volatileDomain(forName: UserDefaults.argumentDomain)[WindowLayout.storageKey] != nil
    }

    // MARK: Window frames

    /// Saves a moved or resized window's frame once its frame for this setup has been restored.
    private func windowChanged(_ window: NSWindow) {
        guard let name = Self.frameName(of: window), restoredWindows.contains(name), window.isVisible, isSettled,
            !window.styleMask.contains(.fullScreen)
        else { return }
        memory.setText(NSStringFromRect(window.frame), name, for: setup)
    }

    /// The first time a window is shown: SwiftUI has placed it by then, so the remembered frame wins.
    private func windowAppeared(_ window: NSWindow) {
        guard let name = Self.frameName(of: window), window.isVisible, isSettled,
            restoredWindows.insert(name).inserted
        else { return }
        restoreFrame(of: window, name: name)
    }

    private func restoreFrame(of window: NSWindow, name: String) {
        guard let stored = memory.text(name, for: setup) else { return }
        let frame = NSRectFromString(stored)
        // Only where it is fully reachable (a screen arrangement can change without changing the setup).
        guard frame.width > 200, frame.height > 200,
            NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -8, dy: -8).contains(frame) }),
            frame != window.frame
        else { return }
        window.setFrame(frame, display: true, animate: false)
    }

    /// The main and the review window; other windows (settings, log) keep AppKit's own frame memory.
    private static func frameName(of window: NSWindow) -> String? {
        guard let id = window.identifier?.rawValue else { return nil }
        if id.hasPrefix(RootScreen.reviewWindowID) { return "frame.review" }
        if id.hasPrefix("main") { return "frame.main" }
        return nil
    }

    // MARK: Screen changes

    /// The applied setup is still the connected one (false while macOS rearranges after a change).
    private var isSettled: Bool { DisplaySetup.current == setup }

    private func screensChanged() {
        pendingChange?.cancel()
        // macOS sends several notifications per change; act once the screens are stable.
        pendingChange = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.apply(DisplaySetup.current)
        }
    }

    private func apply(_ new: DisplaySetup) {
        guard new != setup else { return }
        setup = new
        loadWidths()
        restoreLayoutMode()
        restoredWindows = []
        for window in NSApplication.shared.windows where window.isVisible {
            if let name = Self.frameName(of: window) {
                restoredWindows.insert(name)
                restoreFrame(of: window, name: name)
            }
        }
    }
}
