import FeatureActivity
import SwiftUI

/// Help → Show Log: Sylvra's errors of this run, ready to copy.
struct DiagnosticCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Show Log") { openWindow(id: DiagnosticCommands.windowID) }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }
    }

    static let windowID = "log"
}

/// The log window scene.
struct DiagnosticLogWindow: Scene {
    var body: some Scene {
        Window("Sylvra Log", id: DiagnosticCommands.windowID) {
            DiagnosticLogScreen()
        }
        .defaultSize(width: 820, height: 420)
    }
}
