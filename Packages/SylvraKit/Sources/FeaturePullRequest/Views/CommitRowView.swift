import AppKit
import DesignSystem
import SwiftUI
import SylvraCore

/// One commit: avatar, subject, author, CI and copyable SHA (pure).
/// With `select`, a click reviews this commit on its own; the chevron shows the message body.
struct CommitRowView: View {
    let commit: Commit
    /// Position in the PR (1-based), shown when commits can be selected.
    var number: Int?
    var isSelected = false
    var select: (() -> Void)?
    let copySHA: (_ full: Bool) -> Void
    let open: () -> Void
    @State private var isExpanded = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if let number {
                    Text(number, format: .number)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .frame(width: 20, height: 20)
                        .background(
                            isSelected ? AnyShapeStyle(SylvraColor.brandPrimary) : AnyShapeStyle(.quaternary),
                            in: Circle())
                }
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
                if select != nil, !commit.body.isEmpty {
                    Button {
                        withAnimation(.snappy) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded ? "Hide commit message" : "Show commit message")
                }
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
        .padding(6)
        .background(
            isSelected ? AnyShapeStyle(SylvraColor.brandTint) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let select {
                select()
            } else if !commit.body.isEmpty {
                withAnimation(.snappy) { isExpanded.toggle() }
            }
        }
        .help(select == nil ? "" : String(localized: "Review this commit on its own"))
        .contextMenu {
            if let select { Button("Review this commit", action: select) }
            Button("Copy SHA") { copySHA(false) }
            Button("Copy full SHA") { copySHA(true) }
            Button("Open on GitHub", action: open)
        }
    }
}

/// "All changes" entry above the commits: back from reviewing a single commit (pure).
struct AllChangesRowView: View {
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.down.right")
                    .foregroundStyle(isSelected ? SylvraColor.brandPrimary : .secondary)
                    .frame(width: 20)
                Text("All changes").font(.callout.weight(.medium))
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(SylvraColor.brandPrimary) }
            }
            .padding(6)
            .background(
                isSelected ? AnyShapeStyle(SylvraColor.brandTint) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One check run (pure): a click shows what it reported, the arrow opens it on GitHub.
struct CheckRowView: View {
    let check: PullRequestDetail.CheckRun
    var showReport: (() -> Void)?
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
        .contentShape(Rectangle())
        .onTapGesture { showReport?() }
        .help(showReport == nil ? "" : String(localized: "Show what this check reported"))
    }
}
