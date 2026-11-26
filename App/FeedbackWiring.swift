import FeatureFeedback
import Foundation
import SwiftUI

/// Help → Send Feedback…: takes the picture of the window the user works in, then opens the feedback window.
struct FeedbackCommands: Commands {
    let model: FeedbackModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Send Feedback…") {
                // Before the feedback window opens: it would be in front, and it is never part of the picture.
                let screenshot = WindowSnapshot.workingWindow().flatMap(WindowSnapshot.png)
                Task { await model.begin(screenshot: screenshot) }
                openWindow(id: FeedbackWindow.windowID)
            }
        }
    }
}

/// The feedback window scene.
struct FeedbackWindow: Scene {
    let model: FeedbackModel
    let colorScheme: ColorScheme?
    static let windowID = "feedback"
    /// Where feedback goes: Sylvra's own repository (public).
    static let owner = "mduu"
    static let repository = "sylvra"

    var body: some Scene {
        Window("Send Feedback", id: Self.windowID) {
            FeedbackScreen(model: model, repository: "\(Self.owner)/\(Self.repository)")
                .preferredColorScheme(colorScheme)
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}

extension SystemInfo {
    /// Sylvra's version and the Mac it runs on, plus what the app passes in (e.g. the agent's version).
    static func current(extras: [Extra] = []) -> SystemInfo {
        let bundle = Bundle.main
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var architecture = "unknown"
        #if arch(arm64)
            architecture = "arm64"
        #elseif arch(x86_64)
            architecture = "x86_64"
        #endif
        return SystemInfo(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            model: hardwareModel(), architecture: architecture,
            language: Locale.preferredLanguages.first ?? "?", extras: extras)
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
