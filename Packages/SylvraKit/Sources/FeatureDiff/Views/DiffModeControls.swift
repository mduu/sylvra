import SwiftUI

/// Side by side or inline as one segmented toolbar item (pure); ⌥⌘1 / ⌥⌘2 switch as well.
struct DiffLayoutControl: View {
    let layout: DiffScreenModel.Layout
    let setLayout: (DiffScreenModel.Layout) -> Void

    var body: some View {
        Picker("Layout", selection: Binding(get: { layout }, set: setLayout)) {
            ForEach(DiffScreenModel.Layout.allCases) { option in
                Label(option.title, systemImage: option.icon).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .fixedSize()
        .help("\(layout.title) — side by side (⌥⌘1) or inline (⌥⌘2)")
        .background {
            // Shortcuts without extra toolbar items.
            ForEach(Array(DiffScreenModel.Layout.allCases.enumerated()), id: \.element) { index, option in
                Button(option.title) { setLayout(option) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// What the diff shows, as a menu naming the current choice (pure).
struct DiffScopeMenu: View {
    let scope: DiffScreenModel.Scope
    let canShowSinceReview: Bool
    let setScope: (DiffScreenModel.Scope) -> Void

    var body: some View {
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
        case .fullFile: String(localized: "Every line of the selected file")
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
        DiffLayoutControl(layout: .inline, setLayout: { _ in })
        DiffScopeMenu(scope: .fullFile, canShowSinceReview: true, setScope: { _ in })
    }
    .padding()
}
