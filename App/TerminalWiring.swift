import AppKit
import DesignSystem
import FeatureActivity
import FeatureCustomTools
import FeatureDiff
import FeatureOpenInIDE
import FeatureTerminal
import SwiftUI
import SylvraCore

/// Wires the terminal, custom tools, diff navigator and checkout slices together (composition root only).
@MainActor
enum TerminalWiring {
    /// Where a terminal for `id` starts: the review worktree if it exists, else the home directory.
    static func directory(for id: PullRequestID?) -> URL {
        if let id {
            let worktree = CheckoutService().worktreePath(for: id)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: worktree.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return worktree
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func title(for id: PullRequestID?) -> String {
        id.map { "\($0.repository) #\($0.number)" } ?? "~"
    }

    /// Runs a custom tool for the pull request (and optionally a file or folder of it) in a new terminal tab.
    static func run(
        _ tool: CustomTool, on item: NavigatorItem?, pullRequest id: PullRequestID, environment: AppEnvironment
    ) async {
        do {
            let worktree = try await checkout(for: id, environment: environment)
            let detail = environment.pullRequest.detail.flatMap { $0.summary.id == id ? $0 : nil }
            let file: String?
            let folder: String?
            switch item {
            case .file(let path): (file, folder) = (path, nil)
            case .folder(let path): (file, folder) = (nil, path)
            case nil: (file, folder) = (nil, nil)
            }
            let context = ToolContext(
                worktree: worktree, file: file, folder: folder, prNumber: id.number, headSHA: detail?.headSHA,
                baseSHA: detail?.baseSHA)
            let command = try CommandTemplate.expand(tool.command, context: context)
            environment.terminal.openTab(title: tool.name, directory: worktree, command: command)
        } catch {
            environment.terminal.errorMessage = String(
                localized: "Could not run “\(tool.name)”: \(error.localizedDescription)")
        }
    }

    /// The existing review worktree, or a freshly prepared one (demo mode uses the home directory).
    static func checkout(for id: PullRequestID, environment: AppEnvironment) async throws -> URL {
        let existing = directory(for: id)
        if existing != FileManager.default.homeDirectoryForCurrentUser || environment.isDemo { return existing }
        let job = "tool-worktree"
        environment.activity.start(
            ActivityJob(id: job, kind: .checkout, title: String(localized: "Preparing review worktree…")))
        defer { environment.activity.finish(job, message: nil) }
        return try await CheckoutService().prepareWorktree(
            for: id, purpose: .ide, branch: environment.inbox.summary(for: id)?.headRefName)
    }
}

/// Places the terminal panel below `content` and keeps its start directory in sync with the selection.
struct TerminalSplit<Content: View>: View {
    let environment: AppEnvironment
    let selection: PullRequestSummary?
    @ViewBuilder let content: Content

    @State private var terminalHeight: CGFloat = 260

    private var isPanelPresented: Bool {
        environment.terminal.isPresented || environment.bottomPanel.showsCommands
    }

    // A plain VStack with a drag handle instead of `VSplitView`: an AppKit split view inside the
    // NavigationSplitView detail made the window's constraint pass loop and crash with all columns visible.
    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxHeight: .infinity)
            if isPanelPresented {
                PanelResizeHandle(height: $terminalHeight)
                Group {
                    if environment.bottomPanel.showsCommands {
                        CommandLogPanel {
                            BottomPanelSwitch(
                                title: "Terminal", systemImage: "terminal", help: "Show the terminal (⌃`)"
                            ) {
                                environment.bottomPanel.showsCommands = false
                                environment.terminal.show()
                            }
                            Button("Close", systemImage: "xmark") { environment.bottomPanel.showsCommands = false }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Hide the commands (⌥⌘K)")
                        }
                    } else {
                        TerminalPanel(model: environment.terminal) {
                            PullRequestToolsMenu(environment: environment, pullRequest: selection?.id)
                            BottomPanelSwitch(
                                title: "Commands", systemImage: "list.bullet.rectangle",
                                help: "GitHub requests and commands Sylvra ran (⌥⌘K)"
                            ) { environment.bottomPanel.showsCommands = true }
                        }
                    }
                }
                .frame(height: terminalHeight)
                // A slide-in from the bottom made Metal API validation fail (draw with zero instances).
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: isPanelPresented)
        .animation(.snappy, value: environment.bottomPanel.showsCommands)
        // Errors while the panel is hidden (e.g. a tool from a context menu); the panel shows its own otherwise.
        .alert(
            "Terminal",
            isPresented: Binding(
                get: { environment.terminal.errorMessage != nil && !environment.terminal.isPresented },
                set: { if !$0 { environment.terminal.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { environment.terminal.errorMessage = nil }
        } message: {
            Text(environment.terminal.errorMessage ?? "")
        }
        .onAppear {
            // A tab out of view rang its bell (Claude Code waiting): a dot on the tab; in the background also a
            // notification.
            let activity = environment.activity
            environment.terminal.onAttention = { session, appIsActive in
                if !appIsActive { activity.notifyTerminal(title: session.title) }
            }
        }
        .onChange(of: selection?.id, initial: true) { _, id in
            environment.terminal.defaultDirectory = TerminalWiring.directory(for: id)
            environment.terminal.defaultTitle = TerminalWiring.title(for: id)
        }
    }
}

extension View {
    /// Places the terminal panel below this view (bridges FeatureTerminal into the main window).
    /// `isEnabled` false leaves the view as is (another window hosts the panel).
    @ViewBuilder
    func terminalPanel(_ environment: AppEnvironment, selection: PullRequestSummary?, isEnabled: Bool) -> some View {
        if isEnabled {
            TerminalSplit(environment: environment, selection: selection) { self }
        } else {
            self
        }
    }
}

/// Pull request scoped custom tools (terminal panel header).
struct PullRequestToolsMenu: View {
    let environment: AppEnvironment
    let pullRequest: PullRequestID?

    var body: some View {
        Menu {
            CustomToolsMenuItems(tools: environment.customTools.tools(for: .pullRequest)) { tool in
                guard let pullRequest else { return }
                Task { await TerminalWiring.run(tool, on: nil, pullRequest: pullRequest, environment: environment) }
            }
        } label: {
            Image(systemName: "wrench.and.screwdriver")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(pullRequest == nil || environment.customTools.tools(for: .pullRequest).isEmpty)
        .help("Run a tool for this pull request")
        .accessibilityLabel("Tools")
    }
}

/// "Tools ▸ …" items for file and folder rows of the diff navigator.
struct NavigatorToolsMenu: View {
    let environment: AppEnvironment
    let item: NavigatorItem
    let pullRequest: PullRequestID?

    var body: some View {
        let tools = environment.customTools.tools(for: scope)
        if let pullRequest, !tools.isEmpty {
            Divider()
            CustomToolsMenu(tools: tools) { tool in
                Task { await TerminalWiring.run(tool, on: item, pullRequest: pullRequest, environment: environment) }
            }
        }
    }

    private var scope: CustomTool.Scope {
        switch item {
        case .file: .file
        case .folder: .folder
        }
    }
}

/// Toolbar control: click toggles the terminal; the menu offers a new tab and pull request tools.
struct TerminalToolbarMenu: View {
    let environment: AppEnvironment
    let pullRequest: PullRequestID?

    var body: some View {
        Menu {
            Button("New Terminal Tab") { environment.terminal.openTab() }
            let tools = environment.customTools.tools(for: .pullRequest)
            if let pullRequest, !tools.isEmpty {
                Section("Tools") {
                    CustomToolsMenuItems(tools: tools) { tool in
                        Task {
                            await TerminalWiring.run(tool, on: nil, pullRequest: pullRequest, environment: environment)
                        }
                    }
                }
            }
            Button("Open in \(environment.terminal.externalTerminal.name)") {
                Task { await environment.terminal.openInExternalTerminal() }
            }
        } label: {
            Label {
                Text("Terminal")
            } icon: {
                Image.toolbarSymbol("terminal")
            }
        } primaryAction: {
            environment.terminal.toggle()
        }
        .help("Show or hide the terminal (⌃`)")
    }
}

/// View menu commands for the terminal.
struct TerminalCommands: Commands {
    let terminal: TerminalModel
    let panel: BottomPanelState

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(terminal.isPresented ? "Hide Terminal" : "Show Terminal") {
                // From the Commands list, ⌃` switches to the terminal instead of hiding it.
                if panel.showsCommands {
                    panel.showsCommands = false
                    terminal.show()
                } else {
                    terminal.toggle()
                }
            }
            .keyboardShortcut("`", modifiers: .control)
            Button("New Terminal Tab") { terminal.openTab() }
        }
    }
}

/// The "Terminal & Tools" settings pane.
struct TerminalToolsSettingsPane: View {
    let customTools: CustomToolStore

    var body: some View {
        Form {
            TerminalSettingsView()
            CustomToolsSettingsView(store: customTools)
        }
        .formStyle(.grouped)
    }
}

/// The bar above the bottom panel to drag it taller or shorter: a hairline with a grip, easy to hit.
private struct PanelResizeHandle: View {
    @Binding var height: CGFloat
    @State private var startHeight: CGFloat?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle().fill(.separator).frame(height: 1)
            Capsule()
                .fill(isHovering || startHeight != nil ? Color.secondary : Color.secondary.opacity(0.45))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 10)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovering = inside
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = startHeight ?? height
                    startHeight = start
                    height = min(max(start - value.translation.height, 120), 800)
                }
                .onEnded { _ in startHeight = nil }
        )
        .accessibilityLabel("Resize the panel")
    }
}
