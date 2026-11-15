import AppKit
import Foundation
import OSLog
import SwiftTerm

/// Keeps one PTY terminal view per session alive, independent of the SwiftUI hierarchy,
/// so sessions survive switching tabs, pull requests and hiding the panel.
@MainActor
final class TerminalViewStore: TerminalProcessHosting {
    private var views: [TerminalSession.ID: LocalProcessTerminalView] = [:]
    private var delegates: [TerminalSession.ID: SessionDelegate] = [:]
    private let logger = Logger(subsystem: "app.sylvra", category: "terminal")

    /// The session's terminal view; the shell is started on first access.
    func view(for session: TerminalSession, in model: TerminalModel) -> LocalProcessTerminalView {
        if let view = views[session.id] { return view }
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 240))
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let delegate = SessionDelegate(id: session.id, model: model)
        view.processDelegate = delegate
        views[session.id] = view
        delegates[session.id] = delegate

        let launch = ShellLaunch.make(
            shell: model.shell, command: session.command, baseEnvironment: ProcessInfo.processInfo.environment)
        logger.info("Starting terminal session with \(launch.executable, privacy: .public)")
        view.startProcess(
            executable: launch.executable, args: launch.arguments, environment: launch.environment,
            execName: launch.execName, currentDirectory: session.directory.path)
        return view
    }

    func terminate(_ id: TerminalSession.ID) {
        guard let view = views.removeValue(forKey: id) else { return }
        delegates[id] = nil
        if view.process.running { view.terminate() }
        view.removeFromSuperview()
    }
}

/// Forwards SwiftTerm callbacks (title changes, process exit) to the model.
@MainActor
private final class SessionDelegate: LocalProcessTerminalViewDelegate {
    private let id: TerminalSession.ID
    private weak var model: TerminalModel?

    init(id: TerminalSession.ID, model: TerminalModel) {
        self.id = id
        self.model = model
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        model?.updateTitle(title, of: id)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        model?.markExited(id, code: exitCode)
    }
}
