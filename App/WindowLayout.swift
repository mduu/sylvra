import SwiftUI

/// How the main window arranges inbox, pull request, diff and AI inspector (toolbar menu, ⌃⌘0–4).
enum WindowLayout: String, CaseIterable, Identifiable {
    /// Wide below `compactBelow`, compact otherwise.
    case automatic
    /// Inbox · pull request · diff · inspector side by side (wide screens).
    case wide
    /// Pull request · diff; the inbox and the inspector float on demand (laptops).
    case compact
    /// Only the diff, with the inspector as a sidebar; files in a popover.
    case focus
    /// Inbox and pull request in this window, diff and AI in a second one (two screens).
    case twoWindows

    static let storageKey = "layout.mode"
    /// Windows narrower than this use the compact layout in `automatic`. All columns at their default
    /// widths (inbox 290, pull request 380, inspector 320) leave the diff ~700 pt at this width; MacBook
    /// screens (1470–1728 pt) were above the old 1400 and never switched.
    nonisolated static let compactBelow: CGFloat = 1700
    /// Back to wide only from this width: switching layouts changes the columns' minimum widths, which can
    /// nudge the window width; without the band the layout flipped back and forth until AppKit aborted.
    nonisolated static let wideFrom: CGFloat = 1760

    /// Where a window width lies relative to `compactBelow` and `wideFrom`.
    nonisolated enum WidthBand: Equatable, Sendable {
        case narrow, between, wide

        init(width: CGFloat) {
            self = width < WindowLayout.compactBelow ? .narrow : (width >= WindowLayout.wideFrom ? .wide : .between)
        }

        /// Narrow below `compactBelow`, wide from `wideFrom`; in between the window keeps its layout.
        func isNarrow(wasNarrow: Bool) -> Bool {
            switch self {
            case .narrow: true
            case .wide: false
            case .between: wasNarrow
            }
        }
    }

    var id: String { rawValue }

    /// The layout to use; `automatic` depends on whether the window is narrower than `compactBelow`.
    func resolved(isNarrow: Bool) -> WindowLayout {
        guard self == .automatic else { return self }
        return isNarrow ? .compact : .wide
    }

    var title: LocalizedStringKey {
        switch self {
        case .automatic: "Automatic"
        case .wide: "Wide"
        case .compact: "Compact"
        case .focus: "Focus"
        case .twoWindows: "Two windows"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .automatic: "Compact on narrow windows, wide otherwise"
        case .wide: "Inbox, pull request, diff and AI side by side"
        case .compact: "Pull request and diff; inbox and AI float on demand"
        case .focus: "Only the diff and the AI sidebar"
        case .twoWindows: "Inbox and pull request here, diff and AI in a second window"
        }
    }

    var icon: String {
        switch self {
        case .automatic: "rectangle.3.group"
        case .wide: "rectangle.split.3x1"
        case .compact: "rectangle.split.2x1"
        case .focus: "rectangle"
        case .twoWindows: "rectangle.on.rectangle"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .automatic: "0"
        case .wide: "1"
        case .compact: "2"
        case .focus: "3"
        case .twoWindows: "4"
        }
    }

    /// Which split view columns are visible.
    var columnVisibility: NavigationSplitViewVisibility {
        switch self {
        case .automatic, .wide, .twoWindows: .all
        case .compact: .doubleColumn
        case .focus: .detailOnly
        }
    }

    /// The AI inspector is a sidebar here; elsewhere it floats over the diff.
    var docksInspector: Bool { self != .compact }

    /// The inbox floats in over the content instead of being a column.
    var floatsInbox: Bool { self == .compact || self == .focus }
}

/// Toolbar menu to choose the layout; shows the active one.
struct WindowLayoutMenu: View {
    @Binding var selection: String
    let resolved: WindowLayout

    var body: some View {
        Menu {
            Picker("Layout", selection: $selection) {
                ForEach(WindowLayout.allCases) { layout in
                    Label {
                        Text(layout.title)
                        Text(layout.detail)
                    } icon: {
                        Image(systemName: layout.icon)
                    }
                    .tag(layout.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Layout", systemImage: resolved.icon)
        }
        .menuIndicator(.hidden)
        .help("Window layout: wide, compact (laptop) or focus on the diff")
    }
}

/// View → layout commands (⌃⌘0 automatic, ⌃⌘1 wide, ⌃⌘2 compact, ⌃⌘3 focus, ⌃⌘4 two windows).
struct WindowLayoutCommands: Commands {
    @AppStorage(WindowLayout.storageKey) private var layout = WindowLayout.automatic.rawValue

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            ForEach(WindowLayout.allCases) { option in
                Toggle(isOn: Binding(get: { layout == option.rawValue }, set: { if $0 { layout = option.rawValue } })) {
                    Text(option.title)
                }
                .keyboardShortcut(option.shortcut, modifiers: [.control, .command])
            }
        }
    }
}

/// A panel floating over the content at one edge (inbox left, AI inspector right), closed with Esc.
struct FloatingPanel<Content: View>: View {
    let edge: HorizontalEdge
    let width: CGFloat
    @Binding var isPresented: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.25), radius: 18, x: edge == .leading ? 6 : -6)
            .padding(8)
            .onExitCommand { isPresented = false }
            .transition(.move(edge: edge == .leading ? .leading : .trailing).combined(with: .opacity))
    }
}
