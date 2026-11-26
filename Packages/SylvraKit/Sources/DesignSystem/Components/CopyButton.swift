import AppKit
import SwiftUI

/// Puts text on the general pasteboard.
public enum Clipboard {
    @MainActor
    public static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Text with an HTML version next to it: apps that take rich text (chat, mail) paste the HTML, e.g. a
    /// title as a link.
    @MainActor
    public static func copy(_ text: String, html: String?) {
        copy(text)
        if let html { NSPasteboard.general.setString(html, forType: .html) }
    }
}

/// A small copy button (two squares) that shows a checkmark for a moment after copying. The text is built only
/// when clicked.
public struct CopyButton: View {
    private let help: LocalizedStringKey
    private let text: () -> String
    @State private var didCopy = false

    public init(_ help: LocalizedStringKey = "Copy", text: @escaping () -> String) {
        self.help = help
        self.text = text
    }

    public var body: some View {
        Button {
            Clipboard.copy(text())
            withAnimation(.snappy) { didCopy = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.snappy) { didCopy = false }
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(didCopy ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

extension View {
    /// Right-click → *Copy* (the text is built only when chosen).
    public func copyMenu(_ title: LocalizedStringKey = "Copy", text: @escaping () -> String) -> some View {
        contextMenu {
            Button(title, systemImage: "doc.on.doc") { Clipboard.copy(text()) }
        }
    }
}

#Preview {
    HStack {
        Text("AI summary")
        CopyButton("Copy summary") { "Summary" }
    }
    .padding()
    .copyMenu { "Summary" }
}
