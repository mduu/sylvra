import DesignSystem
import SwiftUI
import SylvraCore

/// Above the chat: which conversation is shown (a menu once there are several) and "New chat" (container).
struct ChatSwitcher: View {
    let model: AIChatModel
    let pullRequestID: PullRequestID

    var body: some View {
        let chats = model.chatList(for: pullRequestID)
        let active = model.activeChat(for: pullRequestID)
        if !chats.isEmpty {
            HStack(spacing: 8) {
                if chats.count > 1 {
                    Menu {
                        ForEach(chats.reversed()) { chat in
                            Toggle(
                                chat.title,
                                isOn: Binding(
                                    get: { chat.id == active?.id },
                                    set: { _ in model.selectChat(chat.id, for: pullRequestID) }))
                        }
                    } label: {
                        Label(active?.title ?? String(localized: "Chat"), systemImage: "bubble.left.and.bubble.right")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Switch to an earlier chat about this pull request")
                } else {
                    Label(active?.title ?? String(localized: "Chat"), systemImage: "bubble.left.and.bubble.right")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let messages = active?.messages, !messages.isEmpty, let open = model.continueInSession {
                    ContinueInSessionMenu {
                        open(
                            AIReviewClipboard.chatHandoff(
                                messages, pullRequest: AIReviewClipboard.pullRequestLine(pullRequestID)), $0)
                    }
                }
                if let messages = active?.messages, !messages.isEmpty {
                    CopyButton("Copy the whole chat for an agent") {
                        AIReviewClipboard.chat(messages, pullRequest: AIReviewClipboard.pullRequestLine(pullRequestID))
                    }
                }
                Button("New chat", systemImage: "square.and.pencil") {
                    withAnimation(.snappy) { model.newChat(for: pullRequestID) }
                }
                .buttonStyle(.borderless)
                .disabled(active?.messages.isEmpty ?? true)
                .help("Start a new conversation — the earlier chats stay in the menu")
            }
            .aiFont(.caption)
            .padding(.trailing, 12)
        }
    }
}

/// *Continue in Claude Code*: the chat in an interactive session, in Sylvra's terminal or the external one (pure).
struct ContinueInSessionMenu: View {
    let open: (_ external: Bool) -> Void

    var body: some View {
        Menu {
            Button("In Sylvra's Terminal", systemImage: "terminal") { open(false) }
            Button("In the External Terminal", systemImage: "macwindow") { open(true) }
        } label: {
            Label("Continue in Claude Code", systemImage: "apple.terminal")
        } primaryAction: {
            open(false)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .fixedSize()
        .help("Continue this chat in an interactive Claude Code session, with the chat as context")
    }
}

#Preview {
    ContinueInSessionMenu { _ in }.padding()
}
