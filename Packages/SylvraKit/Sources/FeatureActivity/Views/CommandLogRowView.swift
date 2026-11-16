import DesignSystem
import Platform
import SwiftUI

/// One GitHub request or command: time, kind, title, status and duration; details when expanded (pure).
struct CommandLogRowView: View {
    let entry: CommandLogEntry
    let isExpanded: Bool
    var toggle: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                Text(entry.startedAt, format: .dateTime.hour().minute().second())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: Self.icon(entry.kind))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .help(entry.kind.rawValue)
                Text(entry.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(entry.status)
                    .foregroundStyle(entry.isFailure ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .fontWeight(entry.isFailure ? .semibold : .regular)
                Text(Self.duration(entry.duration))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 11.5, design: .monospaced))
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            if isExpanded {
                details
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(entry.isFailure ? Color.red.opacity(0.06) : .clear)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let request = entry.request {
                section("Request", request)
            }
            if let response = entry.response, !response.isEmpty {
                section("Response", response)
            }
        }
        .padding(.leading, 26)
        .padding(.bottom, 4)
    }

    private func section(_ title: LocalizedStringKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    static func icon(_ kind: CommandLogEntry.Kind) -> String {
        switch kind {
        case .github: "network"
        case .git: "arrow.triangle.branch"
        case .process: "terminal"
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 1 ? "\(Int((seconds * 1000).rounded())) ms" : String(format: "%.1f s", seconds)
    }

    /// The entry as text for the clipboard.
    static func plainText(_ entry: CommandLogEntry) -> String {
        let time = entry.startedAt.formatted(.dateTime.hour().minute().second())
        var lines = ["\(time)  \(entry.title)  →  \(entry.status), \(duration(entry.duration))"]
        if let request = entry.request { lines.append("Request:\n\(request)") }
        if let response = entry.response { lines.append("Response:\n\(response)") }
        return lines.joined(separator: "\n")
    }
}

#Preview {
    VStack(spacing: 0) {
        CommandLogRowView(
            entry: CommandLogEntry(
                kind: .github, title: "GraphQL query search", startedAt: .now, duration: 0.42, status: "200",
                isFailure: false, request: #"{ "q0" : "is:pr is:open review-requested:@me" }"#,
                response: #"{"data":{"s0":{"nodes":[]}}}"#),
            isExpanded: true)
        CommandLogRowView(
            entry: CommandLogEntry(
                kind: .git, title: "git fetch --quiet origin pull/1234/head", startedAt: .now, duration: 2.3,
                status: "exit 128", isFailure: true, response: "fatal: couldn't find remote ref"),
            isExpanded: false)
    }
    .frame(width: 720)
}
