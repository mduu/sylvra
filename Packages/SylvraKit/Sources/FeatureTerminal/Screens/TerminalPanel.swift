import AppKit
import DesignSystem
@preconcurrency import SwiftTerm
import SwiftUI

/// Bottom terminal panel: tabs with PTY shell sessions (container). `accessory` is a slot for
/// app-provided actions in the header (e.g. pull request tools).
public struct TerminalPanel<Accessory: View>: View {
    @Bindable private var model: TerminalModel
    private let accessory: Accessory

    public init(model: TerminalModel, @ViewBuilder accessory: () -> Accessory) {
        self.model = model
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(spacing: 0) {
            TerminalTabBarView(
                tabs: model.sessions.map { TerminalTab(id: $0.id, title: $0.title, hasExited: $0.hasExited) },
                selection: model.selectedID,
                select: { model.selectedID = $0 },
                close: { model.closeTab($0) },
                newTab: { model.openTab() },
                actions: headerActions
            )
            .background(.bar)
            Divider()
            if let session = model.selectedSession, let store = model.host as? TerminalViewStore {
                TerminalHostView(view: store.view(for: session, in: model))
                    .id(session.id)
                    .padding(.leading, 6)
                    .background(SylvraColor.terminalBackground)
            } else {
                SylvraColor.terminalBackground
            }
        }
        .alert(
            "Terminal",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            accessory
            Button {
                Task { await model.openInExternalTerminal() }
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Open in \(model.externalTerminal.name)")
            .accessibilityLabel("Open in external terminal")
            Button {
                model.isPresented = false
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Hide terminal (⌃`)")
            .accessibilityLabel("Hide terminal")
        }
    }
}

extension TerminalPanel where Accessory == EmptyView {
    public init(model: TerminalModel) {
        self.init(model: model) { EmptyView() }
    }
}

/// Hosts a session's long-lived terminal view and themes it for the current appearance.
private struct TerminalHostView: NSViewRepresentable {
    let view: LocalProcessTerminalView
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            nsView.nativeBackgroundColor = NSColor(SylvraColor.terminalBackground)
            nsView.nativeForegroundColor = NSColor(SylvraColor.terminalForeground)
            nsView.caretColor = NSColor(SylvraColor.accentGold)
            nsView.selectedTextBackgroundColor = NSColor(SylvraColor.terminalSelection)
        }
    }

    /// The view outlives this representable (it belongs to the session), so it is only detached.
    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {}
}
