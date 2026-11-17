import SwiftUI

/// A text button with a light rounded background, for links that should look clickable without
/// being underlined (e.g. the repository and pull request number in the title bar).
public struct ChipButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration)
    }

    private struct ChipBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    .primary.opacity(configuration.isPressed ? 0.18 : (isHovered ? 0.13 : 0.07)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == ChipButtonStyle {
    /// See `ChipButtonStyle`.
    public static var chip: ChipButtonStyle { ChipButtonStyle() }
}

#Preview {
    HStack {
        Button("billing") {}
        Button("#1234") {}
    }
    .buttonStyle(.chip)
    .padding()
}
