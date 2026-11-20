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
    /// The screens connected now (cached: asking `NSScreen` on every resize tick is too slow).
    @ObservationIgnored private var connected: DisplaySetup
    /// Widths and frames saved after dragging pauses (UserDefaults writes per frame made resizing stutter).
    @ObservationIgnored private var pendingWidths: [ColumnLayout.Column: CGFloat] = [:]
    @ObservationIgnored private var pendingFrames: [String: NSRect] = [:]
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// Column widths reported before this moment come from the split view, not from the reviewer: while the
    /// window is placed at launch, restored, resized or moved to other screens it squeezes the columns (often
    /// down to their minimum), and those widths were saved as if chosen.
    @ObservationIgnored private var acceptsWidthsAfter = Date.now.addingTimeInterval(2)
    @ObservationIgnored private var windowSizes: [String: CGSize] = [:]
    /// Demo launches (screenshots) share the reviewer's settings: they change nothing there.
    @ObservationIgnored private let isDemo = CommandLine.arguments.contains("--demo")
    @ObservationIgnored private var widths: [ColumnLayout.Column: CGFloat] = [:]
    @ObservationIgnored private let memory = DisplayLayoutMemory()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingChange: Task<Void, Never>?
    /// Windows whose frame was restored for the current setup (before that their frames aren't saved).
    @ObservationIgnored private var restoredWindows: Set<String> = []

    private init() {
        let current = DisplaySetup.current
        setup = current
        connected = current
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
        observers.append(
            center.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.flushPendingSaves() }
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
        guard !isDemo, isSettled, column.range.contains(width), Date.now > acceptsWidthsAfter,
            !NSApplication.shared.windows.contains(where: \.inLiveResize)
        else { return }
        pendingWidths[column] = width.rounded()
        scheduleSave()
    }

    private func loadWidths() {
        for column in ColumnLayout.Column.allCases {
            let stored = memory.number(column.memoryName, for: setup).map { CGFloat($0) } ?? column.defaultWidth
            widths[column] = min(max(stored, column.range.lowerBound), column.range.upperBound)
        }
    }

    // MARK: Window layout

    func saveLayoutMode(_ mode: String) {
        guard !isDemo, isSettled, !isLayoutModeFromLaunchArgument else { return }
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
        guard let name = Self.frameName(of: window) else { return }
        // A new window size squeezes or widens the columns: not a width the reviewer chose.
        if windowSizes.updateValue(window.frame.size, forKey: name) != window.frame.size {
            ignoreWidths(for: 0.8)
        }
        guard !isDemo, restoredWindows.contains(name), window.isVisible, isSettled,
            !window.styleMask.contains(.fullScreen)
        else { return }
        pendingFrames[name] = window.frame
        scheduleSave()
    }

    private func ignoreWidths(for seconds: TimeInterval) {
        acceptsWidthsAfter = max(acceptsWidthsAfter, Date.now.addingTimeInterval(seconds))
        // Widths measured just before belong to the old size too.
        pendingWidths = [:]
    }

    // MARK: Saving

    /// Saves once the drag or live resize pauses.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flushPendingSaves()
        }
    }

    private func flushPendingSaves() {
        pendingSave?.cancel()
        pendingSave = nil
        // Only for the setup the values were measured in (checked live: macOS may move windows before it
        // reports the screen change).
        if isSettled, DisplaySetup.current == setup {
            for (column, width) in pendingWidths {
                memory.setNumber(Double(width), column.memoryName, for: setup)
            }
            for (name, frame) in pendingFrames { memory.setText(NSStringFromRect(frame), name, for: setup) }
        }
        pendingWidths = [:]
        pendingFrames = [:]
    }

    /// The first time a window is shown: SwiftUI has placed it by then, so the remembered frame wins.
    private func windowAppeared(_ window: NSWindow) {
        guard let name = Self.frameName(of: window), window.isVisible, isSettled,
            restoredWindows.insert(name).inserted
        else { return }
        restoreFrame(of: window, name: name)
    }

    private func restoreFrame(of window: NSWindow, name: String) {
        ignoreWidths(for: 1.5)
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
    private var isSettled: Bool { connected == setup }

    private func screensChanged() {
        connected = DisplaySetup.current
        // Values measured while macOS rearranges belong to no setup.
        pendingWidths = [:]
        pendingFrames = [:]
        pendingChange?.cancel()
        // macOS sends several notifications per change; act once the screens are stable.
        pendingChange = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.apply(DisplaySetup.current)
        }
    }

    private func apply(_ new: DisplaySetup) {
        connected = new
        guard new != setup else { return }
        setup = new
        ignoreWidths(for: 2)
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
