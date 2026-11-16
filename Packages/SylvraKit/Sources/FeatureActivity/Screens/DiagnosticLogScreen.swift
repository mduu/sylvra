import AppKit
import DesignSystem
import Platform
import SwiftUI

/// Sylvra's log of the current run (container): errors to copy into a bug report or a question.
/// Tokens and code are never logged (see AGENTS.md).
public struct DiagnosticLogScreen: View {
    @State private var entries: [DiagnosticLogEntry] = []
    @State private var showsAll = false
    @State private var loadError: String?

    public init() {}

    private var visibleEntries: [DiagnosticLogEntry] {
        let filtered = showsAll ? entries : entries.filter { $0.level == .error || $0.level == .fault }
        return filtered.reversed()
    }

    public var body: some View {
        DiagnosticLogView(entries: visibleEntries, loadError: loadError)
            .toolbar {
                ToolbarItem {
                    Picker("Show", selection: $showsAll) {
                        Text("Errors").tag(false)
                        Text("All").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem {
                    Button("Copy", systemImage: "doc.on.doc") {
                        let text = visibleEntries.reversed().map(\.line).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .help("Copy the shown entries")
                    .disabled(visibleEntries.isEmpty)
                }
            }
            .frame(minWidth: 560, minHeight: 320)
            .task { await keepLoading() }
    }

    /// Reloads while the window is open, so new errors show up without a button.
    private func keepLoading() async {
        while !Task.isCancelled {
            let result = await Task.detached(priority: .utility) { Result { try DiagnosticLog.entries() } }.value
            switch result {
            case .success(let loaded):
                if loaded != entries { entries = loaded }
                loadError = nil
            case .failure(let error):
                loadError = String(describing: error)
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}

/// The log entries, newest first (pure).
struct DiagnosticLogView: View {
    let entries: [DiagnosticLogEntry]
    var loadError: String?

    var body: some View {
        if let loadError {
            ContentUnavailableView(
                "Couldn't read the log", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else if entries.isEmpty {
            ContentUnavailableView(
                "No errors", systemImage: "checkmark.circle",
                description: Text("Errors of this app run appear here."))
        } else {
            List(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(entry.level.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(entry.level))
                        .frame(width: 44, alignment: .leading)
                    Text(entry.category)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(entry.message)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
        }
    }

    private func color(_ level: DiagnosticLogEntry.Level) -> Color {
        switch level {
        case .error, .fault: SylvraColor.diffRemoved
        case .notice: SylvraColor.accentGold
        case .debug, .info: .secondary
        }
    }
}

#Preview {
    DiagnosticLogView(entries: [
        DiagnosticLogEntry(
            id: 1, date: .now, level: .error, category: "github",
            message: "/graphql failed: 502 502 Bad Gateway nginx"),
        DiagnosticLogEntry(
            id: 2, date: .now.addingTimeInterval(-20), level: .notice, category: "github",
            message: "/graphql returned 502, retrying"),
    ])
    .frame(width: 640, height: 240)
}
