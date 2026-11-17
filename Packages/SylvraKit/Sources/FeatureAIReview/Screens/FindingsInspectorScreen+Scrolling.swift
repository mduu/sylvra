import DesignSystem
import SwiftUI
import SylvraCore

extension FindingsInspectorScreen {
    static let chatBottomID = "chat-bottom"
    /// Room inside the scroll view for focus rings (≈3 pt outside a field), which it would clip.
    /// The scroll view widens by the same amount, so the content stays aligned with the header.
    static let focusRingInset: CGFloat = 4

    /// The tab content in its scroll view. The chat follows new messages (an answer from its first line)
    /// and offers a button back to the end when scrolled up.
    func scrollingContent(for id: PullRequestID) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content(for: id)
                    if model.tab == .chat { Color.clear.frame(height: 1).id(Self.chatBottomID) }
                }
                .padding(.bottom, 14)
                .padding(.horizontal, Self.focusRingInset)
                .animation(.snappy, value: model.selectedFindingID)
            }
            .padding(.horizontal, -Self.focusRingInset)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
            } action: { _, isAtBottom in
                isScrolledToBottom = isAtBottom
            }
            .overlay(alignment: .bottom) {
                if model.tab == .chat, !isScrolledToBottom {
                    ScrollToBottomButton { scrollToBottom(proxy) }
                        .padding(.bottom, 12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy, value: isScrolledToBottom)
            .onChange(of: model.findingRequest) {
                guard let selected = model.selectedFindingID else { return }
                // A highlight clicked in the diff: show the finding here as well (after the tab switch).
                Task { @MainActor in
                    withAnimation(.snappy) { proxy.scrollTo(selected, anchor: .top) }
                }
            }
            .onChange(of: chat?.messages(for: id).last?.id) {
                guard model.tab == .chat, let last = chat?.messages(for: id).last else { return }
                Task { @MainActor in
                    // An answer is read from its start; the reviewer's own question just shows the end.
                    withAnimation(.snappy) {
                        if last.role == .user {
                            proxy.scrollTo(Self.chatBottomID, anchor: .bottom)
                        } else {
                            proxy.scrollTo(last.id, anchor: .top)
                        }
                    }
                }
            }
            .onChange(of: model.tab, initial: true) { _, tab in
                guard tab == .chat else { return }
                Task { @MainActor in proxy.scrollTo(Self.chatBottomID, anchor: .bottom) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) { proxy.scrollTo(Self.chatBottomID, anchor: .bottom) }
    }
}

/// Round "jump to the end" button floating over the chat (pure).
struct ScrollToBottomButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.separator))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Scroll to the latest message")
        .accessibilityLabel("Scroll to the latest message")
    }
}

#Preview {
    ScrollToBottomButton {}.padding()
}
