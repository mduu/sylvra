import AppKit
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
    public var isPresented = false {
        didSet { clearAttention() }
    }
    public private(set) var sessions: [TerminalSession] = [] {
        didSet { saveClaudeSessions() }
    }
    public var selectedID: TerminalSession.ID? {
        didSet { clearAttention() }
    }
    /// A tab that is not in view rang the bell; `appIsActive` says whether Sylvra is the active app (wired by the
    /// app: a notification when it is not).
    @ObservationIgnored public var onAttention: ((TerminalSession, _ appIsActive: Bool) -> Void)?
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
        sessions = restoredClaudeSessions()
        selectedID = sessions.first?.id
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
        get {
            access(keyPath: \.externalTerminal)
            let configured = defaults.string(forKey: TerminalPreferences.externalTerminalKey) ?? ""
            return configured.isEmpty ? .terminal : .named(configured)
        }
        set {
            withMutation(keyPath: \.externalTerminal) {
                defaults.set(newValue.bundleIdentifier, forKey: TerminalPreferences.externalTerminalKey)
            }
        }
    }

    /// The known terminal apps that are installed, plus the configured one (to choose from in the panel).
    public var installedExternalTerminals: [ExternalTerminal] {
        let installed = ExternalTerminal.presets.filter { isInstalled($0.bundleIdentifier) }
        return installed.contains(externalTerminal) ? installed : installed + [externalTerminal]
    }

    @ObservationIgnored var isInstalled: (String) -> Bool = { bundleIdentifier in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    // MARK: Tabs

    /// Opens and selects a new tab (and shows the panel). `command` runs first, then an interactive shell.
    @discardableResult
    public func openTab(
        title: String? = nil, directory: URL? = nil, command: String? = nil, isClaude: Bool = false
    ) -> TerminalSession.ID {
        let session = TerminalSession(
            title: title ?? defaultTitle, directory: directory ?? defaultDirectory, command: command,
            isClaude: isClaude)
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
        // Claude Code names its tab; a `claude` started by hand is remembered too.
        if trimmed.localizedCaseInsensitiveContains("claude") { sessions[index].isClaude = true }
    }

    /// The bell of a session: a dot on its tab unless the user looks at it, and the app is told.
    func ringBell(_ id: TerminalSession.ID, appIsActive: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let inView = isPresented && selectedID == id && appIsActive
        guard !inView else { return }
        sessions[index].needsAttention = true
        onAttention?(sessions[index], appIsActive)
    }

    /// The tab in view needs no dot.
    private func clearAttention() {
        guard isPresented, let index = sessions.firstIndex(where: { $0.id == selectedID }),
            sessions[index].needsAttention
        else { return }
        sessions[index].needsAttention = false
    }

    func markExited(_ id: TerminalSession.ID, code: Int32?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].hasExited = true
        sessions[index].exitCode = code
    }

    // MARK: Claude sessions across restarts

    static let claudeSessionsKey = "terminal.claudeSessions"

    /// Continues a Claude session from before the restart in its directory (`claude --continue`), in its tab's place.
    public func resume(_ id: TerminalSession.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].isRestored else { return }
        let old = sessions[index]
        guard FileManager.default.fileExists(atPath: old.directory.path) else {
            errorMessage = String(localized: "The folder of this session is gone: \(old.directory.path)")
            return
        }
        let session = TerminalSession(
            title: old.title, directory: old.directory, command: "claude --continue", isClaude: true)
        sessions[index] = session
        selectedID = session.id
        isPresented = true
    }

    private func saveClaudeSessions() {
        let saved = sessions.filter(\.isClaude).map { SavedClaudeSession(title: $0.title, directory: $0.directory) }
        defaults.set(try? JSONEncoder().encode(saved), forKey: Self.claudeSessionsKey)
    }

    private func restoredClaudeSessions() -> [TerminalSession] {
        guard let data = defaults.data(forKey: Self.claudeSessionsKey),
            let saved = try? JSONDecoder().decode([SavedClaudeSession].self, from: data)
        else { return [] }
        return saved.map { saved in
            var session = TerminalSession(title: saved.title, directory: saved.directory, isClaude: true)
            session.isRestored = true
            session.hasExited = true
            return session
        }
    }

    // MARK: External terminal

    /// Opens a folder or a script in the configured external terminal (a `.command` file runs there).
    public func openInExternalTerminal(_ item: URL) async {
        let app = externalTerminal
        do {
            try await opener.open(item, bundleIdentifier: app.bundleIdentifier)
        } catch {
            errorMessage = String(localized: "Could not open \(app.name): \(error.localizedDescription)")
        }
    }

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
