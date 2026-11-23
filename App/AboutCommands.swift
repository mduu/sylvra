import AppKit
import FeatureUpdates
import SwiftUI

/// *Sylvra → About Sylvra* opens Sylvra's own About window; *Help → Sylvra on GitHub* the project page.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sylvra") { openWindow(id: AboutWindow.id) }
        }
        CommandGroup(after: .help) {
            Button("Sylvra on GitHub") {
                guard let url = AboutWindow.projectURL else { return }
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// The About window: fixed size, no title bar, the brand canvas up to the window edges.
struct AboutWindow: Scene {
    static let id = "about"
    static let projectURL = URL(string: "https://github.com/mduu/sylvra")
    static let licenseURL = URL(string: "https://github.com/mduu/sylvra/blob/main/LICENSE")

    let updates: UpdateModel
    /// The app's appearance setting (nil: follow the system).
    let colorScheme: ColorScheme?

    var body: some Scene {
        Window("About Sylvra", id: Self.id) {
            AboutView(
                icon: Image(nsImage: NSApplication.shared.applicationIconImage),
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                copyright: Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
                    ?? "© Marc Dürst",
                author: "Marc Dürst",
                projectURL: Self.projectURL,
                licenseURL: Self.licenseURL,
                checkForUpdates: { Task { await updates.check(userInitiated: true) } }
            )
            .fixedSize()
            .preferredColorScheme(colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        // Opened from the Sylvra menu (About Sylvra), not listed again in the Window menu.
        .commandsRemoved()
    }
}
