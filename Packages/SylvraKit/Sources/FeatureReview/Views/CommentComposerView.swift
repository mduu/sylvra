import DesignSystem
import SwiftUI
import SylvraCore

/// Composer for a new review comment (pure): Markdown with preview, *Insert suggestion*,
/// *Add to review* (pending) or *Comment now*.
struct CommentComposerView: View {
    let location: CodeLocation
    @Binding var text: String
    let hasPendingReview: Bool
    let isWorking: Bool
    var insertSuggestion: () -> Void = {}
    var addToReview: () -> Void = {}
    var commentNow: () -> Void = {}
    var cancel: () -> Void = {}

    @State private var isPreviewing = false
    @FocusState private var isFocused: Bool

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Mode", selection: $isPreviewing) {
                    Text("Write").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text(lineLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: insertSuggestion) {
                    Label("Insert suggestion", systemImage: "plus.forwardslash.minus")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Insert a suggestion block with the selected lines (⌘⇧S)")
                .disabled(location.side == .left)
            }
            .controlSize(.small)

            Group {
                if isPreviewing {
                    ScrollView {
                        MarkdownBodyView(markdown: isEmpty ? "_Nothing to preview_" : text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                } else {
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .padding(4)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Leave a comment — Markdown supported")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .frame(minHeight: 80, maxHeight: 220)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))

            HStack {
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("Comment now", action: commentNow)
                    .disabled(isEmpty || isWorking || hasPendingReview)
                    .help(
                        hasPendingReview ? "Finish or submit your pending review first" : "Post this comment right away"
                    )
                Button(hasPendingReview ? "Add to review" : "Start a review", action: addToReview)
                    .buttonStyle(.borderedProminent)
                    .tint(SylvraColor.brandPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isEmpty || isWorking)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(SylvraColor.brandTint.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SylvraColor.brandSecondary.opacity(0.6)))
        .onAppear { isFocused = true }
    }

    private var lineLabel: String { ReviewThreadView.lineLabel(location) }
}

#Preview {
    @Previewable @State var text = ""
    CommentComposerView(
        location: CodeLocation(path: "Sources/Billing/InvoiceService.swift", line: 9, side: .right, startLine: 8),
        text: $text, hasPendingReview: true, isWorking: false
    )
    .padding()
    .frame(width: 560)
}
