import SwiftUI

/// `‹ Title` that goes back one level (repository → inbox, pull request → inbox), in the brand color with a
/// generous click target.
public struct BackButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.body.weight(.medium))
            }
            .foregroundStyle(SylvraColor.brandPrimary)
            .padding(.vertical, 4)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Back button") {
    VStack(alignment: .leading) {
        BackButton("Inbox") {}
        Text("feldnah").font(.headline)
    }
    .padding()
    .background(SylvraColor.surfaceSidebar)
}
