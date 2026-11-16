import FeatureActivity
import Observation
import Platform
import SwiftUI

/// What the bottom panel shows: the terminal or the Commands list (both share the space below the diff).
@MainActor @Observable
final class BottomPanelState {
    var showsCommands = false

}

/// View → Show Commands (⌥⌘K): the GitHub requests and commands of this session.
struct CommandLogCommands: Commands {
    let panel: BottomPanelState

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(panel.showsCommands ? "Hide Commands" : "Show Commands") {
                panel.showsCommands.toggle()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])
        }
    }
}

/// Header button to switch between the terminal and the Commands list.
struct BottomPanelSwitch: View {
    let title: LocalizedStringKey
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(help)
    }
}
