import AppKit
import Foundation
import OSLog
import Platform
@preconcurrency import SwiftTerm

/// Keeps one PTY terminal view per session alive, independent of the SwiftUI hierarchy,
/// so sessions survive switching tabs, pull requests and hiding the panel.
@MainActor
final class TerminalViewStore: TerminalProcessHosting {
    private var views: [TerminalSession.ID: LocalProcessTerminalView] = [:]
    private var delegates: [TerminalSession.ID: SessionDelegate] = [:]
    private let logger = SylvraLog.logger("terminal")

    /// The session's terminal view; the shell is started on first access.
    func view(for session: TerminalSession, in model: TerminalModel) -> LocalProcessTerminalView {
        if let view = views[session.id] { return view }
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 240))
        view.font = TerminalFonts.preferred(
            size: TerminalPreferences.fontSize(UserDefaults.standard.double(forKey: TerminalPreferences.fontSizeKey)))
        Self.configure(view)
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

    /// Scrollback and keyboard for every session. Left Option is Meta (⌥B, ⌥F, ⌥⏎ for Claude Code and shells);
    /// right Option types what the layout puts on the key — `@ [ ] { } |` on Swiss and German keyboards. Arrows,
    /// Backspace and Enter stay Meta on both sides.
    static func configure(_ view: TerminalView) {
        view.changeScrollback(ShellLaunch.scrollback)
        view.optionAsMetaKey = true
        view.optionAsMetaSide = .left
        view.optionAsMetaKeyForFunctionalKeys = true
    }

    func terminate(_ id: TerminalSession.ID) {
        guard let view = views.removeValue(forKey: id) else { return }
        delegates[id] = nil
        if view.process.running { view.terminate() }
        view.removeFromSuperview()
    }
}

/// Forwards SwiftTerm callbacks (title changes, process exit) to the model.
/// SwiftTerm delivers them on the main queue but its protocol is not actor-annotated, hence the hop.
@MainActor
private final class SessionDelegate: LocalProcessTerminalViewDelegate {
    private let id: TerminalSession.ID
    private weak var model: TerminalModel?

    init(id: TerminalSession.ID, model: TerminalModel) {
        self.id = id
        self.model = model
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in self.model?.updateTitle(title, of: self.id) }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in self.model?.markExited(self.id, code: exitCode) }
    }
}

@MainActor
enum TerminalFonts {
    /// Prefers an installed Nerd Font (prompt themes use its powerline glyphs), else the system monospaced font.
    static func preferred(size: CGFloat) -> NSFont {
        if let family = nerdFontFamily,
            let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
        {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Looked up once: scanning all font families on every size change is slow.
    private static let nerdFontFamily: String? = {
        let families = NSFontManager.shared.availableFontFamilies.filter { $0.contains("Nerd Font Mono") }
        let preferred = ["JetBrainsMono", "MesloLG", "Hack", "FiraCode", "SauceCodePro", "CaskaydiaCove"]
        return preferred.lazy.compactMap { name in families.first { $0.hasPrefix(name) } }.first ?? families.first
    }()
}
