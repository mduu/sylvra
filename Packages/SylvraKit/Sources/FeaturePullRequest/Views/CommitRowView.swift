import AppKit
import DesignSystem
import SwiftUI
import SylvraCore

/// One commit: avatar, subject, author, CI and copyable SHA (pure).
struct CommitRowView: View {
    let commit: Commit
    let copySHA: (_ full: Bool) -> Void
    let open: () -> Void
    @State private var isExpanded = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                AvatarView(commit.author, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.subject)
                        .font(.callout.weight(.medium))
                        .lineLimit(isExpanded ? nil : 2)
                    HStack(spacing: 4) {
                        Text(commit.author.displayName)
                        Text(verbatim: "·")
                        Text(commit.authoredAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        if commit.isVerified {
                            Image(systemName: "checkmark.seal").help("Verified signature")
                        }
                        CheckStateBadge(commit.checkState)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    copySHA(NSEvent.modifierFlags.contains(.option))
                    withAnimation(.snappy) { didCopy = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        withAnimation(.snappy) { didCopy = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(didCopy ? String(localized: "Copied") : commit.shortSHA)
                            .contentTransition(.numericText())
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .font(.caption.monospaced())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy SHA (⌥-click: full SHA)")
            }
            if isExpanded, !commit.body.isEmpty {
                Text(commit.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 30)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !commit.body.isEmpty { withAnimation(.snappy) { isExpanded.toggle() } } }
        .contextMenu {
            Button("Copy SHA") { copySHA(false) }
            Button("Copy full SHA") { copySHA(true) }
            Button("Open on GitHub", action: open)
        }
    }
}

/// One check run with a link to its logs on GitHub (pure).
struct CheckRowView: View {
    let check: PullRequestDetail.CheckRun
    let open: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CheckStateBadge(check.state).frame(width: 14)
            Text(check.name).lineLimit(1)
            Spacer(minLength: 4)
            if let duration = check.duration {
                Text(duration, format: .units(allowed: [.minutes, .seconds], width: .narrow))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button(action: open) {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .disabled(check.url == nil)
            .help(check.state == .failure ? "Open run on GitHub" : "Details on GitHub")
        }
        .padding(.vertical, 2)
    }
}
