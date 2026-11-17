import DesignSystem
import SwiftUI
import SylvraCore

/// Comment language and AI writing help next to a comment field (pure): switching the language translates
/// the text; the menu rephrases factually, shortens or undoes the last rewrite.
struct WritingHelpControls: View {
    /// `nil` hides the language switch.
    var language: Binding<String>?
    /// `nil` hides the writing help (no AI agent).
    var rewrite: ((CommentRewriteStyle) -> Void)?
    var undoRewrite: (() -> Void)?
    var isRewriting: Bool
    var isEmpty: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let language {
                Picker("Language", selection: language) {
                    Text(verbatim: "EN").tag("English")
                    Text(verbatim: "DE").tag("German")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Language of this comment — switching translates the draft")
            }
            if let rewrite {
                Menu {
                    Button("Rephrase factually", systemImage: "wand.and.sparkles") { rewrite(.improve) }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("Shorter and crisper", systemImage: "scissors") { rewrite(.shorten) }
                        .keyboardShortcut("k", modifiers: [.command, .shift])
                    if let undoRewrite {
                        Divider()
                        Button("Undo rewrite", systemImage: "arrow.uturn.backward", action: undoRewrite)
                    }
                } label: {
                    if isRewriting {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label("Writing help", systemImage: "sparkles").labelStyle(.iconOnly)
                    }
                } primaryAction: {
                    rewrite(.improve)
                }
                .menuStyle(.button)
                .fixedSize()
                .foregroundStyle(SylvraColor.accentGold)
                .disabled(isRewriting || isEmpty)
                .help("Rephrase factually and concisely (⌘⇧E). Menu: shorter (⌘⇧K), undo")
            }
        }
    }
}
