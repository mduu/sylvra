import DesignSystem
import SwiftUI

/// All review shortcuts (`?`).
struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    static let groups: [(String, [(String, String)])] = [
        (
            String(localized: "Navigate"),
            [
                ("j / k", String(localized: "Next / previous file")),
                ("n / p", String(localized: "Next / previous change")),
                (". / ,", String(localized: "Next / previous AI finding")),
                ("⌘K", String(localized: "Command palette")),
                ("⌘F  /", String(localized: "Find in diff")),
            ]
        ),
        (
            String(localized: "Review"),
            [
                ("v", String(localized: "Toggle viewed")),
                ("i", String(localized: "Toggle AI inspector")),
                ("⌘⇧R", String(localized: "Run AI review")),
                ("⌘⇧E / ⌘⇧K", String(localized: "Rephrase / shorten comment")),
                ("⌘↩", String(localized: "Add comment to review")),
                ("⌘⇧G", String(localized: "Open on GitHub")),
            ]
        ),
        (String(localized: "Help"), [("?", String(localized: "This overview"))]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard shortcuts").font(.title3.weight(.semibold))
            ForEach(Self.groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.0).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                    ForEach(group.1, id: \.0) { key, title in
                        HStack {
                            Text(verbatim: key)
                                .font(.system(.callout, design: .monospaced).weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(SylvraColor.surfaceSelected, in: RoundedRectangle(cornerRadius: 5))
                                .frame(width: 120, alignment: .leading)
                            Text(title)
                        }
                    }
                }
            }
            Text("Single keys work whenever you are not typing.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

#Preview("Shortcuts") {
    KeyboardShortcutsSheet()
}
