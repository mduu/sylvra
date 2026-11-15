import Foundation
import Observation

/// Owns the terminal processes of the sessions (PTY views in the app, fakes in tests).
@MainActor
public protocol TerminalProcessHosting: AnyObject {
    /// Ends the session's process and releases its view.
    func terminate(_ id: TerminalSession.ID)
}

/// Opens a folder in an external terminal app.
@MainActor
public protocol ExternalTerminalOpening {
    func open(_ directory: URL, bundleIdentifier: String) async throws
}

/// Tabs of the terminal panel. Sessions live here, so they survive switching pull requests
/// and hiding the panel. The app decides where new tabs start (`defaultDirectory`).
@MainActor
@Observable
public final class TerminalModel {
    public var isPresented = false
    public private(set) var sessions: [TerminalSession] = []
    public var selectedID: TerminalSession.ID?
    /// Working directory of new tabs without an explicit directory (the PR worktree or home).
    public var defaultDirectory: URL
    /// Title of new tabs without an explicit title.
    public var defaultTitle: String
    /// Error shown to the user (e.g. the external terminal app is missing).
    public var errorMessage: String?

    @ObservationIgnored let host: any TerminalProcessHosting
    @ObservationIgnored private let opener: any ExternalTerminalOpening
    @ObservationIgnored private let defaults: UserDefaults

    public init(
        defaultDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        host: (any TerminalProcessHosting)? = nil,
        opener: any ExternalTerminalOpening = ExternalTerminalLauncher(),
        defaults: UserDefaults = .standard
    ) {
        self.defaultDirectory = defaultDirectory
        defaultTitle = (defaultDirectory.path as NSString).abbreviatingWithTildeInPath
        self.host = host ?? TerminalViewStore()
        self.opener = opener
        self.defaults = defaults
    }

    public var selectedSession: TerminalSession? {
        sessions.first { $0.id == selectedID }
    }

    // MARK: Settings

    /// Configured shell, or the user's login shell.
    public var shell: String {
        let configured = defaults.string(forKey: TerminalPreferences.shellKey) ?? ""
        return configured.isEmpty ? ShellLaunch.loginShell() : configured
    }

    public var externalTerminal: ExternalTerminal {
        let configured = defaults.string(forKey: TerminalPreferences.externalTerminalKey) ?? ""
        return configured.isEmpty ? .terminal : .named(configured)
    }

    // MARK: Tabs

    /// Opens and selects a new tab (and shows the panel). `command` runs first, then an interactive shell.
    @discardableResult
    public func openTab(title: String? = nil, directory: URL? = nil, command: String? = nil) -> TerminalSession.ID {
        let session = TerminalSession(
            title: title ?? defaultTitle, directory: directory ?? defaultDirectory, command: command)
        sessions.append(session)
        selectedID = session.id
        isPresented = true
        return session.id
    }

    /// Closes a tab and ends its process; selects the neighbour and hides the panel after the last tab.
    public func closeTab(_ id: TerminalSession.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: index)
        host.terminate(id)
        if selectedID == id {
            selectedID = sessions.indices.contains(index) ? sessions[index].id : sessions.last?.id
        }
        if sessions.isEmpty { isPresented = false }
    }

    /// Shows or hides the panel; showing an empty panel opens a first tab.
    public func toggle() {
        if isPresented {
            isPresented = false
        } else {
            show()
        }
    }

    /// Shows the panel with at least one tab.
    public func show() {
        isPresented = true
        if sessions.isEmpty { openTab() }
        if selectedSession == nil { selectedID = sessions.first?.id }
    }

    func updateTitle(_ title: String, of id: TerminalSession.ID) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = trimmed
    }

    func markExited(_ id: TerminalSession.ID, code: Int32?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].hasExited = true
        sessions[index].exitCode = code
    }

    // MARK: External terminal

    /// Opens the selected tab's directory (or the default directory) in the configured external terminal.
    public func openInExternalTerminal() async {
        let app = externalTerminal
        do {
            try await opener.open(
                selectedSession?.directory ?? defaultDirectory, bundleIdentifier: app.bundleIdentifier)
        } catch {
            errorMessage = String(localized: "Could not open \(app.name): \(error.localizedDescription)")
        }
    }
}
