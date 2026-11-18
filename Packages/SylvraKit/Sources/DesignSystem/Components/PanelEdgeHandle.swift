import SwiftUI

/// A small tab on the edge between two columns that collapses or expands a side panel (pure).
///
/// It hugs the divider: flat on the side touching it, rounded on the side facing the content. At rest it is a
/// quiet sliver with a chevron; on hover it pulls out a little and takes the brand tint.
public struct PanelEdgeHandle: View {
    /// The side of the handle that touches the divider.
    let attachedEdge: HorizontalEdge
    /// Where the chevron points: the direction the panel will move.
    let pointsTo: HorizontalEdge
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        attachedTo attachedEdge: HorizontalEdge, pointsTo: HorizontalEdge, help: LocalizedStringKey,
        action: @escaping () -> Void
    ) {
        self.attachedEdge = attachedEdge
        self.pointsTo = pointsTo
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            tab
                .frame(width: isHovering ? 16 : 11, height: isHovering ? 52 : 44)
                // A larger target than the drawn tab, still narrow enough to leave the content clickable.
                .frame(width: 18, height: 64, alignment: attachedEdge == .leading ? .leading : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { isHovering = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private var tab: some View {
        let fill: Color = isHovering ? SylvraColor.brandTint : SylvraColor.surfaceElevated
        let border: Color = isHovering ? SylvraColor.brandPrimary.opacity(0.45) : SylvraColor.codeHairline
        return
            shape
            .fill(fill)
            .overlay(shape.strokeBorder(border))
            .overlay { chevron }
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0.08), radius: isHovering ? 5 : 2)
    }

    private var chevron: some View {
        let symbol = pointsTo == .leading ? "chevron.compact.left" : "chevron.compact.right"
        let style: AnyShapeStyle = isHovering ? AnyShapeStyle(SylvraColor.brandPrimary) : AnyShapeStyle(.tertiary)
        return Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(style)
    }

    private var shape: UnevenRoundedRectangle {
        let radius: CGFloat = 7
        return attachedEdge == .leading
            ? UnevenRoundedRectangle(bottomTrailingRadius: radius, topTrailingRadius: radius, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius, style: .continuous)
    }
}

#Preview("Panel edge handles") {
    HStack(spacing: 0) {
        Color.gray.opacity(0.1).frame(width: 120)
        Divider()
        ZStack(alignment: .leading) {
            SylvraColor.surfacePrimary
            PanelEdgeHandle(attachedTo: .leading, pointsTo: .leading, help: "Hide the inbox") {}
        }
        ZStack(alignment: .trailing) {
            SylvraColor.surfacePrimary
            PanelEdgeHandle(attachedTo: .trailing, pointsTo: .leading, help: "Show the AI panel") {}
        }
    }
    .frame(width: 420, height: 200)
}
