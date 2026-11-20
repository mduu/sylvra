import AppKit
import DesignSystem
import SwiftUI

/// The update card floating at the window's top trailing corner while `isCardPresented`.
public struct UpdatePanel: View {
    let model: UpdateModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: UpdateModel) {
        self.model = model
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            if model.isCardPresented {
                UpdateCardView(
                    state: model.state,
                    currentVersion: model.currentVersion?.description ?? "–",
                    canInstallInPlace: model.canInstallInPlace,
                    icon: Image(nsImage: NSApplication.shared.applicationIconImage),
                    install: { Task { await model.install() } },
                    later: model.later,
                    skip: model.skip,
                    openPage: { openURL($0) }
                )
                .padding(.top, 12)
                .padding(.trailing, 16)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing))))
            }
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.35, bounce: 0.2),
            value: model.isCardPresented
        )
        .animation(.easeInOut(duration: 0.2), value: model.state)
    }
}

/// A toolbar button for a found update that was put off with *Later* (opens the card again).
public struct UpdateToolbarButton: View {
    let model: UpdateModel

    public init(model: UpdateModel) {
        self.model = model
    }

    public var body: some View {
        if let release = model.pendingRelease, !model.isCardPresented {
            Button {
                model.isCardPresented = true
            } label: {
                Label {
                    Text("Update")
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, SylvraColor.brandPrimary)
                }
                .labelStyle(.titleAndIcon)
            }
            .help("Sylvra \(release.version.description) is available")
        }
    }
}

/// *Sylvra → Check for Updates…*
public struct UpdateCommands: Commands {
    let model: UpdateModel

    public init(model: UpdateModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                Task { await model.check(userInitiated: true) }
            }
            .disabled(model.isWorking)
        }
    }
}
