import AppKit
import DesignSystem
import SwiftUI

/// The feedback window (container): write a problem, idea or question, optionally with a picture of Sylvra's
/// window and the version information, and send it as an issue to Sylvra's repository. `isPublic`: the
/// repository's issues can be read by everyone.
public struct FeedbackScreen: View {
    @Bindable private var model: FeedbackModel
    private let repository: String
    private let isPublic: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    public init(model: FeedbackModel, repository: String, isPublic: Bool = true) {
        self.model = model
        self.repository = repository
        self.isPublic = isPublic
    }

    public var body: some View {
        Group {
            if case .sent(let receipt) = model.state {
                FeedbackSentView(
                    receipt: receipt, open: { if let url = receipt.url { openURL(url) } },
                    copyScreenshot: model.screenshot.map { png in { Self.copy(png) } }, close: { dismiss() })
            } else {
                FeedbackFormView(
                    draft: $model.draft, screenshot: model.screenshot, info: model.info, repository: repository,
                    isPublic: isPublic, isSending: model.isSending, failure: failure,
                    send: { Task { await model.send() } }, cancel: { dismiss() })
            }
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var failure: String? {
        if case .failed(let message) = model.state { return message }
        return nil
    }

    private static func copy(_ png: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
    }
}

/// The form (pure).
struct FeedbackFormView: View {
    @Binding var draft: FeedbackDraft
    let screenshot: Data?
    let info: SystemInfo?
    let repository: String
    var isPublic = true
    var isSending = false
    var failure: String?
    let send: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Send Feedback").font(.title3.weight(.semibold))
                Text(
                    isPublic
                        ? "Creates an issue in \(repository) with your GitHub account. The issue is public."
                        : "Creates an issue in \(repository) with your GitHub account."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Picker("Kind", selection: $draft.kind) {
                ForEach(FeedbackDraft.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("Title", text: $draft.title, prompt: Text("In one sentence"))
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 4) {
                Text(detailsHint).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.details)
                    .font(.body)
                    .frame(height: 130)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
            attachments
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(SylvraColor.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isSending { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Send", action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSend || isSending)
            }
        }
        .padding(20)
    }

    private var detailsHint: String {
        switch draft.kind {
        case .bug: String(localized: "What did you do, what happened, and what did you expect?")
        case .idea: String(localized: "What would you like, and what would it help you with?")
        case .question: String(localized: "What would you like to know?")
        }
    }

    @ViewBuilder private var attachments: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $draft.includesScreenshot) {
                Text("Attach a screenshot of the Sylvra window")
            }
            .disabled(screenshot == nil)
            if draft.includesScreenshot, let screenshot, let image = NSImage(data: screenshot) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .accessibilityLabel("Screenshot of the Sylvra window")
                Label(
                    isPublic
                        ? """
                        Everyone can see this picture, with all the code, names and comments in it. It shows only \
                        Sylvra's window, no other app.
                        """
                        : "The picture shows what is in Sylvra's window (code, names, comments), no other app.",
                    systemImage: "eye"
                )
                .font(.caption)
                .foregroundStyle(isPublic ? SylvraColor.statusWarning : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Include version information", isOn: $draft.includesSystemInfo)
            if draft.includesSystemInfo, let info {
                Text(info.lines.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

/// After sending: the issue's number, and what to do about a screenshot that could not be uploaded (pure).
struct FeedbackSentView: View {
    let receipt: FeedbackReceipt
    let open: () -> Void
    var copyScreenshot: (() -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            Text("Thank you — issue #\(receipt.number) was created.").font(.headline)
            if receipt.screenshotMissing {
                Text(
                    """
                    The screenshot could not be uploaded: that needs write access to the repository. You can copy \
                    it and paste it into the issue on GitHub.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                if let copyScreenshot { Button("Copy Screenshot", action: copyScreenshot) }
            }
            HStack {
                Button("Open Issue", action: open).disabled(receipt.url == nil)
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Form") {
    @Previewable @State var draft = FeedbackDraft()
    FeedbackFormView(
        draft: $draft, screenshot: nil,
        info: SystemInfo(
            appVersion: "0.8.3", build: "65", macOS: "27.2", model: "Mac16,7", architecture: "arm64", language: "de",
            extras: [.init("Claude Code", "2.1.0")]),
        repository: "mduu/sylvra", send: {}, cancel: {}
    )
    .frame(width: 540)
}

#Preview("Sent") {
    FeedbackSentView(
        receipt: .init(number: 42, url: nil, screenshotMissing: true), open: {}, copyScreenshot: {}, close: {}
    )
    .frame(width: 540)
}
