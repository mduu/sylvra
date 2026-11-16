import DesignSystem
import SwiftUI
import SylvraCore

/// What went wrong in a check (container): GitHub's summary of the run, details and annotations.
struct CheckReportSheet: View {
    let check: PullRequestDetail.CheckRun
    let load: () async throws -> CheckReport
    let openOnGitHub: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var report: CheckReport?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CheckStateBadge(check.state)
                Text(check.name).font(.headline).lineLimit(2)
                Spacer()
                if let duration = check.duration {
                    Text(duration, format: .units(allowed: [.minutes, .seconds], width: .narrow))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            Divider()
            HStack {
                Button("Open on GitHub", systemImage: "safari", action: openOnGitHub)
                    .disabled(check.url == nil)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 640, height: 560)
        .background(SylvraColor.surfaceElevated)
        .task {
            do {
                report = try await load()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary).textSelection(.enabled)
        } else if let report {
            if report.isEmpty {
                Text("This check didn't report a summary. Its logs are on GitHub.").foregroundStyle(.secondary)
            } else {
                CheckReportView(report: report)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }
}

/// A check report: title, summary, annotations and details (pure).
struct CheckReportView: View {
    let report: CheckReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = report.title, !title.isEmpty {
                Text(title).font(.title3.weight(.semibold)).textSelection(.enabled)
            }
            if let summary = report.summary, !summary.isEmpty {
                SimpleMarkdownView(markdown: summary)
            }
            if !report.annotations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Annotations").font(.caption.weight(.semibold)).textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    ForEach(report.annotations) { annotation in
                        AnnotationRowView(annotation: annotation)
                    }
                }
            }
            if let text = report.text, !text.isEmpty {
                DisclosureGroup("Details") {
                    SimpleMarkdownView(markdown: text).padding(.top, 6)
                }
            }
        }
    }
}

private struct AnnotationRowView: View {
    let annotation: CheckReport.Annotation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: annotation.line.map { "\(annotation.path):\($0)" } ?? annotation.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let title = annotation.title, !title.isEmpty {
                    Text(title).font(.callout.weight(.medium))
                }
                Text(annotation.message)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var symbol: String {
        switch annotation.level {
        case .failure: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .notice: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch annotation.level {
        case .failure: SylvraColor.diffRemoved
        case .warning: SylvraColor.accentGold
        case .notice: .secondary
        }
    }
}

/// Block Markdown as checks write it: headings, paragraphs, lists and fenced code; HTML tags are dropped (pure).
struct SimpleMarkdownView: View {
    let markdown: String

    enum Block: Equatable {
        case heading(String)
        case paragraph(String)
        case code(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(Self.inline(text)).font(.headline).padding(.top, 4)
                case .paragraph(let text):
                    Text(Self.inline(text))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let code):
                    Text(code)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .font(.callout)
    }

    nonisolated static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    nonisolated static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph = []
        }
        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(rawLine)
                continue
            }
            let line = rawLine.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                flush()
                blocks.append(.heading(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if trimmed.isEmpty {
                flush()
            } else {
                // List items keep their own line; "- " / "* " become bullets.
                let bullet = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ? "• " + trimmed.dropFirst(2) : line
                paragraph.append(String(bullet))
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}

#Preview {
    CheckReportView(
        report: CheckReport(
            title: "1 test failed", summary: "## Results\n**41 passed**, 1 failed\n\n- `totalRoundsPerLine()`",
            text: "```\n42.29 != 42.30\n```",
            annotations: [
                .init(
                    path: "Tests/InvoiceServiceTests.swift", line: 31, level: .failure, title: nil,
                    message: "Expectation failed")
            ])
    )
    .padding()
    .frame(width: 560)
}
