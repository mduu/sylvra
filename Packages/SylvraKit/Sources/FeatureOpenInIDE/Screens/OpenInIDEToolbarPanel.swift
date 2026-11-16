import DesignSystem
import SwiftUI
import SylvraCore

/// "Open in <IDE> ▾" toolbar control with checkout target and stash confirmation (container).
public struct OpenInIDEToolbarPanel: View {
    @Bindable private var model: OpenInIDEModel
    private let pullRequestID: PullRequestID?

    public init(model: OpenInIDEModel, pullRequestID: PullRequestID?) {
        self.model = model
        self.pullRequestID = pullRequestID
    }

    public var body: some View {
        Menu {
            if let id = pullRequestID {
                Section("Open in") {
                    ForEach(model.installedIDEs) { ide in
                        Button {
                            Task { await model.open(id, in: ide) }
                        } label: {
                            Label(ide.name, systemImage: ide.symbol)
                        }
                    }
                }
                Section("Check out in") {
                    Picker(
                        "Check out in",
                        selection: Binding(
                            get: { model.checkoutTarget(for: id) }, set: { model.setCheckoutTarget($0, for: id) })
                    ) {
                        ForEach(CheckoutTarget.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
        } label: {
            Label(title, systemImage: symbol).toolbarMenuLabelInset()
        } primaryAction: {
            if let id = pullRequestID { Task { await model.open(id) } }
        }
        .disabled(pullRequestID == nil || isWorking)
        .help("Open the pull request locally (⌘⇧O)")
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .alert(
            "Uncommitted changes",
            isPresented: Binding(
                get: { model.stashConfirmation != nil }, set: { if !$0 { model.stashConfirmation = nil } }),
            presenting: model.stashConfirmation
        ) { _ in
            Button("Stash and continue") { Task { await model.confirmStash() } }
            Button("Cancel", role: .cancel) { model.stashConfirmation = nil }
        } message: { request in
            Text(
                "\(request.clone.path) has uncommitted changes. "
                    + "Sylvra can stash them (named “Sylvra: before reviewing …”) and check out the pull request."
            )
        }
    }

    private var isWorking: Bool {
        if case .working = model.status { return true }
        return false
    }

    /// Constant width (see AIReviewToolbarPanel): progress and results are shown in the toast.
    private var title: String {
        pullRequestID.map { String(localized: "Open in \(model.preferredIDE(for: $0).name)") }
            ?? String(localized: "Open in IDE")
    }

    private var symbol: String {
        switch model.status {
        case .working: "hourglass"
        case .failed: "exclamationmark.triangle"
        default: "arrow.up.forward.app"
        }
    }
}

/// Transient feedback ("Opened in Rider", errors) shown at the bottom of the window (pure).
public struct OpenInIDEStatusToast: View {
    private let status: OpenInIDEModel.Status

    public init(status: OpenInIDEModel.Status) {
        self.status = status
    }

    public var body: some View {
        switch status {
        case .done(let message):
            toast(message, symbol: "checkmark.circle.fill", tint: .green)
        case .failed(let message):
            toast(message, symbol: "exclamationmark.triangle.fill", tint: .red)
        case .working(let message):
            toast(message, symbol: "hourglass", tint: .secondary)
        case .idle:
            EmptyView()
        }
    }

    private func toast(_ message: String, symbol: String, tint: Color) -> some View {
        Label(message, systemImage: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 8, y: 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
