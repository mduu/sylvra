import SwiftUI

/// Toolbar controls for the diff: layout as two toggle buttons, scope as a menu naming the current choice
/// (pure). Icon-only segmented pickers shared one tooltip and didn't say which mode was active.
struct DiffModeControls: View {
    let layout: DiffScreenModel.Layout
    let scope: DiffScreenModel.Scope
    let canShowSinceReview: Bool
    let setLayout: (DiffScreenModel.Layout) -> Void
    let setScope: (DiffScreenModel.Scope) -> Void

    var body: some View {
        ControlGroup {
            layoutToggle(.sideBySide, shortcut: "1")
            layoutToggle(.inline, shortcut: "2")
        }
        Menu {
            ForEach(scopes, id: \.self) { option in
                Toggle(isOn: Binding(get: { scope == option }, set: { if $0 { setScope(option) } })) {
                    Label(option.title, systemImage: option.icon)
                    Text(option.detail)
                }
            }
        } label: {
            Label(scope.title, systemImage: scope.icon).labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help("What to show: \(scope.detail.lowercased())")
    }

    private var scopes: [DiffScreenModel.Scope] {
        canShowSinceReview ? DiffScreenModel.Scope.allCases : [.focused, .fullFile]
    }

    private func layoutToggle(_ option: DiffScreenModel.Layout, shortcut: KeyEquivalent) -> some View {
        Toggle(isOn: Binding(get: { layout == option }, set: { _ in setLayout(option) })) {
            Label(option.title, systemImage: option.icon)
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .keyboardShortcut(shortcut, modifiers: [.command, .option])
        .help("\(option.title) (⌥⌘\(String(shortcut.character)))")
    }
}

extension DiffScreenModel.Layout {
    var title: String {
        switch self {
        case .sideBySide: String(localized: "Side by side")
        case .inline: String(localized: "Inline")
        }
    }

    var icon: String {
        switch self {
        case .sideBySide: "rectangle.split.2x1"
        case .inline: "rectangle.split.1x2"
        }
    }
}

extension DiffScreenModel.Scope {
    var title: String {
        switch self {
        case .focused: String(localized: "Changes")
        case .fullFile: String(localized: "Full file")
        case .sinceLastReview: String(localized: "Since my review")
        }
    }

    var detail: String {
        switch self {
        case .focused: String(localized: "Changed lines with a little context")
        case .fullFile: String(localized: "Every line of the changed files")
        case .sinceLastReview: String(localized: "Only what changed since your last review")
        }
    }

    var icon: String {
        switch self {
        case .focused: "line.3.horizontal.decrease"
        case .fullFile: "doc.text"
        case .sinceLastReview: "clock.arrow.circlepath"
        }
    }
}

#Preview {
    HStack {
        DiffModeControls(
            layout: .inline, scope: .fullFile, canShowSinceReview: true, setLayout: { _ in }, setScope: { _ in })
    }
    .padding()
}
