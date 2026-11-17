import DesignSystem
import SwiftUI
import SylvraCore

/// Chat with the agent about the selected pull request (container).
public struct AIChatPanel: View {
    @Bindable private var model: AIChatModel
    private let pullRequestID: PullRequestID?
    private let jump: (String, Int) -> Void
    private let useAsComment: ((String, CodeLocation) -> Void)?

    /// - Parameters:
    ///   - jump: shows `path:line` in the diff (wired by the app).
    ///   - useAsComment: turns an answer into a draft comment at the discussed code (wired by the app).
    public init(
        model: AIChatModel, pullRequestID: PullRequestID?, jump: @escaping (String, Int) -> Void,
        useAsComment: ((String, CodeLocation) -> Void)? = nil
    ) {
        self.model = model
        self.pullRequestID = pullRequestID
        self.jump = jump
        self.useAsComment = useAsComment
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.messages(for: pullRequestID)) { message in
                ChatMessageView(
                    message: message,
                    showCode: message.location.map { location in { jump(location.path, location.line) } },
                    useAsComment: commentAction(for: message)
                )
            }
            if model.isSending {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").aiFont(.caption).foregroundStyle(.secondary)
                }
            }
            if model.messages(for: pullRequestID).isEmpty, let id = pullRequestID {
                FlowPrompts(prompts: AIChatModel.quickPrompts) { prompt in Task { await model.send(prompt, for: id) } }
            }
            contextChips
            HStack(alignment: .bottom, spacing: 6) {
                TextField("Ask about this pull request…", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").aiFont(.title2) }
                    .buttonStyle(.borderless)
                    .disabled(model.draft.isEmpty || model.isSending || pullRequestID == nil)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .environment(
            \.openURL,
            OpenURLAction { url in
                guard url.scheme == "sylvra-code", let reference = CodeReferenceURL(url) else { return .systemAction }
                jump(reference.path, reference.line)
                return .handled
            }
        )
        .animation(.snappy, value: model.messages(for: pullRequestID))
    }

    @ViewBuilder private var contextChips: some View {
        let chips = [model.context.file, model.context.finding, model.context.code?.label].compactMap { $0 }
        if !chips.isEmpty {
            HStack(spacing: 6) {
                if let code = model.context.code {
                    chip(code.label) { model.context.code = nil }
                }
                if let file = model.context.file {
                    chip((file as NSString).lastPathComponent) { model.context.file = nil }
                }
                if let finding = model.context.finding {
                    chip(finding) { model.context.finding = nil }
                }
            }
        }
    }

    private func chip(_ title: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .aiFont(.caption)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(SylvraColor.brandPrimary.opacity(0.14), in: Capsule())
    }

    /// Answers about discussed code can become a draft comment on that code.
    private func commentAction(for message: AIChatModel.Message) -> (() -> Void)? {
        guard message.role == .assistant, let useAsComment,
            let location = model.location(answering: message, in: pullRequestID)
        else { return nil }
        return { useAsComment(message.text, location) }
    }

    private func send() {
        guard let id = pullRequestID else { return }
        Task { await model.send(for: id) }
    }
}

/// One chat bubble with markdown and clickable `path:line` references (pure).
struct ChatMessageView: View {
    let message: AIChatModel.Message
    var showCode: (() -> Void)?
    var useAsComment: (() -> Void)?
    @Environment(\.aiTextScale) private var textScale

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            if let location = message.location, let showCode {
                Button(action: showCode) {
                    Label(
                        AIChatModel.CodeSnippet(location: location, text: "").label,
                        systemImage: "text.bubble")
                }
                .buttonStyle(.borderless)
                .aiFont(.caption, design: .monospaced)
                .help("Show the discussed code")
            }
            if message.role == .user {
                // The reviewer's question: a compact bubble on the right that only grows with its text.
                Text(Self.render(message.text, scale: textScale))
                    .aiFont(.callout)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(SylvraColor.brandPrimary.opacity(0.32), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.leading, 36)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                // AI answers (and errors) use the full width; answers carry the AI accent and Markdown blocks.
                Group {
                    if message.role == .assistant {
                        ChatMarkdownView(text: message.text) { Self.render($0, scale: textScale) }
                    } else {
                        Text(Self.render(message.text, scale: textScale))
                            .aiFont(.callout)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if message.role == .assistant {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(AIAccent.border.opacity(0.35))
                    }
                }
                .foregroundStyle(message.role == .error ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            }
            if let useAsComment {
                Button("Use as comment", systemImage: "text.bubble.badge.plus", action: useAsComment)
                    .buttonStyle(.borderless)
                    .aiFont(.caption)
                    .help("Draft a short, factual review comment from this answer — you edit it before posting")
            }
        }
    }

    private var background: AnyShapeStyle {
        switch message.role {
        case .user: AnyShapeStyle(SylvraColor.brandPrimary.opacity(0.32))
        case .assistant: AnyShapeStyle(AIAccent.cardBackground)
        case .error: AnyShapeStyle(Color.red.opacity(0.08))
        }
    }

    static func render(_ text: String, scale: CGFloat = 1) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        let plain = String(result.characters)
        for reference in AIChatModel.codeReferences(in: plain) {
            let token = String(plain[reference.range])
            guard let range = result.range(of: token),
                let url = CodeReferenceURL.make(path: reference.path, line: reference.line)
            else { continue }
            result[range].link = url
            result[range].font = .system(
                size: (AIFontMetrics.pointSize(of: .callout) * scale).rounded(), design: .monospaced)
        }
        return result
    }
}

/// `sylvra-code://open?path=…&line=…` links used inside chat answers.
struct CodeReferenceURL {
    let path: String
    let line: Int

    init?(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let path = items.first(where: { $0.name == "path" })?.value,
            let line = items.first(where: { $0.name == "line" })?.value.flatMap(Int.init)
        else { return nil }
        self.path = path
        self.line = line
    }

    static func make(path: String, line: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "sylvra-code"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "path", value: path), URLQueryItem(name: "line", value: String(line)),
        ]
        return components.url
    }
}

/// Quick prompt buttons (pure).
private struct FlowPrompts: View {
    let prompts: [String]
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(prompts, id: \.self) { prompt in
                Button(prompt) { select(prompt) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
