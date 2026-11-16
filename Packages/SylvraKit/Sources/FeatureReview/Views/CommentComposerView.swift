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
    /// Language of this comment (`English`, `German`); changing it translates the draft when a rewriter exists.
    var language: Binding<String>?
    /// What the AI is doing with the draft (shown over the text, which is locked meanwhile).
    var rewritingStyle: CommentRewriteStyle?
    var cancelRewrite: () -> Void = {}
    private var isRewriting: Bool { rewritingStyle != nil }
    /// Rewrites the draft personally in the selected language; `nil` hides the button.
    var rewrite: ((CommentRewriteStyle) -> Void)?
    /// Discusses the selected lines privately with the agent (the draft text becomes the question).
    var discuss: (() -> Void)?
    /// Restores the text before the last rewrite; `nil` when there is nothing to undo.
    var undoRewrite: (() -> Void)?

    @State private var isPreviewing = false
    @FocusState private var isFocused: Bool

    private var toneIssues: [ToneCheck.Issue] { isPreviewing ? [] : ToneCheck.issues(in: text) }

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
                Text(lineLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Spacer()
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
                if let discuss {
                    Button(action: discuss) {
                        Label("Discuss with Claude", systemImage: "bubble.left.and.text.bubble.right").labelStyle(
                            .iconOnly)
                    }
                    .help(
                        "Discuss these lines privately with the agent — your text becomes the question, nothing is posted"
                    )
                }
                Button(action: insertSuggestion) {
                    Label("Insert suggestion", systemImage: "plus.forwardslash.minus").labelStyle(.iconOnly)
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
            .disabled(isRewriting)
            .overlay {
                if let rewritingStyle {
                    RewriteProgressView(
                        title: Self.progressTitle(rewritingStyle, language: language?.wrappedValue),
                        cancel: cancelRewrite
                    )
                    .transition(.opacity)
                }
            }
            .animation(.snappy, value: rewritingStyle)

            if !toneIssues.isEmpty {
                ToneHintView(
                    issues: toneIssues, isRewriting: isRewriting, makeFactual: rewrite.map { r in { r(.improve) } }
                )
                .transition(.opacity)
            }

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

    static func progressTitle(_ style: CommentRewriteStyle, language: String?) -> String {
        switch style {
        case .translate where language == "German": String(localized: "Translating to German…")
        case .translate: String(localized: "Translating to English…")
        case .improve: String(localized: "Rephrasing…")
        case .shorten: String(localized: "Shortening…")
        }
    }
}

/// The AI working on the draft: a veil over the text with what's happening and a way to stop it (pure).
struct RewriteProgressView: View {
    let title: String
    var cancel: () -> Void = {}

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.background.opacity(0.75))
            RoundedRectangle(cornerRadius: 6).fill(AIAccent.lineGradient(opacity: 0.25))
            RoundedRectangle(cornerRadius: 6).strokeBorder(AIAccent.border.opacity(0.7), lineWidth: 1.5)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Label(title, systemImage: "sparkles").font(.callout.weight(.medium))
                }
                Button("Cancel", action: cancel).controlSize(.small)
            }
        }
    }
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

/// Hint below the composer when the draft contains judgmental wording (pure).
struct ToneHintView: View {
    let issues: [ToneCheck.Issue]
    var isRewriting = false
    var makeFactual: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "text.bubble").foregroundStyle(SylvraColor.accentGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep it factual").font(.caption.weight(.semibold))
                Text(summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let makeFactual {
                Button("Rephrase", systemImage: "sparkles", action: makeFactual)
                    .controlSize(.small)
                    .disabled(isRewriting)
            }
        }
        .padding(8)
        .background(SylvraColor.accentGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var summary: String {
        issues.prefix(3).map { "«\($0.phrase)» \(Self.reason($0.reason))" }.joined(separator: " · ")
    }

    private static func reason(_ reason: ToneCheck.Reason) -> String {
        switch reason {
        case .dismissive: String(localized: "sounds dismissive")
        case .absolute: String(localized: "is absolute — name the concrete case")
        case .loaded: String(localized: "is judgmental — describe the effect instead")
        case .emphasis: String(localized: "reads as raised voice")
        }
    }
}

#Preview("Tone hint") {
    ToneHintView(issues: ToneCheck.issues(in: "This is obviously wrong, we always round at the end!"), makeFactual: {})
        .padding()
        .frame(width: 520)
}
