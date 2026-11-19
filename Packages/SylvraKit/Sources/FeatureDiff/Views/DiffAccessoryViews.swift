import AppKit
import DesignSystem
import SwiftUI

/// Content placed between diff lines, indented past the gutter; the gutter keeps running (pure).
extension EnvironmentValues {
    /// Width a floating panel covers at the diff's trailing edge (set by the app; 0 when nothing floats).
    @Entry public var diffTrailingCover: CGFloat = 0
}

/// How much of a floating panel's cover a box in the diff keeps clear of: all of it while the box stays at
/// least `minimum` wide, otherwise only what leaves it that wide (in a narrow side-by-side half, avoiding the
/// panel completely would squeeze a thread to a few letters per line).
func trailingClearance(cover: CGFloat, width: CGFloat, minimum: CGFloat) -> CGFloat {
    guard cover > 0 else { return 0 }
    return min(cover, max(width - minimum, 0))
}

struct AccessoryLane<Content: View>: View {
    var minWidth: CGFloat = 0
    /// Width of the gutter the lane continues (inline has two line-number columns).
    var gutterWidth: CGFloat = halfGutterWidth
    /// How the line above continues through the lane (change bar).
    var continuation: HalfContinuation = .none
    /// Side by side draws the surfaces once behind both lanes (with the continued ribbon and bars).
    var drawsSurface = true
    /// Whether the lane ends at the diff's trailing edge, where a floating panel may cover it.
    var reachesTrailingEdge = true
    @ViewBuilder let content: Content
    @Environment(\.diffTrailingCover) private var trailingCover
    @State private var width: CGFloat = 0

    /// Threads, composers and finding cards stay readable from this width on.
    static var minimumContentWidth: CGFloat { 420 }

    var body: some View {
        // The zero-height placeholder keeps an empty lane in the layout (an empty `if` would vanish and let
        // the other side's thread take the full width).
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 0)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Keeps cards, composers and their buttons clear of a floating panel; the surface still runs underneath.
        .padding(
            .trailing,
            reachesTrailingEdge
                ? trailingClearance(
                    cover: trailingCover, width: width - gutterWidth, minimum: Self.minimumContentWidth) : 0
        )
        .padding(.leading, gutterWidth)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .background {
            // Clipped to the lane: the change bar's minimum height made an empty lane's surface spill 1 pt
            // into the line above (a white seam between lines).
            if drawsSurface {
                Color.clear.overlay { GutterStrip(gutterWidth: gutterWidth, continuation: continuation) }.clipped()
            }
        }
    }
}

/// A gutter column with the code surface beside it (background only); a change bar or hatching continues.
struct GutterStrip: View {
    var gutterWidth: CGFloat = halfGutterWidth
    var continuation: HalfContinuation = .none

    var body: some View {
        HStack(spacing: 0) {
            SylvraColor.codeGutter.frame(width: gutterWidth)
            switch continuation {
            case .none:
                SylvraColor.codeSurface
            case .changeBar(let kind):
                HStack(spacing: 0) {
                    ChangeBar(kind: kind)
                    SylvraColor.codeSurface
                }
            case .empty:
                HatchPattern().background(SylvraColor.codeSurface)
            }
        }
    }
}

/// Subtle diagonal hatching for the empty side of a side-by-side row (pure).
struct HatchPattern: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            context.stroke(path, with: .color(.secondary.opacity(0.10)), lineWidth: 1)
        }
    }
}

/// Xcode-style AI highlight (pure): a rounded box around the finding's lines with a border in the AI gradient,
/// a soft glow along its edges (the middle keeps the red/green of the change), ✦ in the gutter of the first
/// line and an AI badge at the box's top right. Each row draws its slice of the box.
struct AIHighlightOverlay: View {
    let highlight: LineHighlight?
    /// The new-side line the overlay sits on: the box spans the finding's whole range.
    var line: Int?
    /// Clicks on the gutter keep starting comments.
    var gutterWidth: CGFloat = halfGutterWidth
    @Environment(\.diffSelectFinding) private var selectFinding
    @Environment(\.diffTrailingCover) private var trailingCover
    @State private var isHovered = false
    @State private var width: CGFloat = 0

    var body: some View {
        if let highlight {
            let span = Self.span(of: line, in: highlight.lines)
            let isFirst = span.index == 0
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: gutterWidth)
                    .overlay(alignment: .leading) { gutterMark(highlight, isFirst: isFirst) }
                AIFindingBoxSlice(
                    isFirst: isFirst, isLast: span.index == span.count - 1,
                    strength: isHovered ? 1 : 0.55 + 0.45 * highlight.intensity,
                    isSelected: highlight.isSelected
                )
                .overlay(alignment: .topTrailing) {
                    if isFirst { badge(highlight) }
                }
                // Clear of the change bar on the left and of a floating panel on the right.
                .padding(.leading, 4)
                .padding(
                    .trailing, 4 + trailingClearance(cover: trailingCover, width: width - gutterWidth, minimum: 240)
                )
                .allowsHitTesting(false)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .transition(.opacity)
        }
    }

    /// ✦ on the finding's first line; clicking it opens the finding (the line numbers keep their comment action).
    @ViewBuilder private func gutterMark(_ highlight: LineHighlight, isFirst: Bool) -> some View {
        if isFirst {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(
                    highlight.isSelected ? AnyShapeStyle(SylvraColor.accentGold) : AnyShapeStyle(AIAccent.border)
                )
                .frame(width: 20, height: diffRowHeight)
                .background(SylvraColor.codeGutter)
                .overlay {
                    if let id = highlight.findingID, let selectFinding {
                        tapArea { selectFinding(id) }
                    }
                }
        }
    }

    private func badge(_ highlight: LineHighlight) -> some View {
        Image(systemName: "sparkles")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(
                highlight.isSelected ? AnyShapeStyle(SylvraColor.accentGold) : AnyShapeStyle(AIAccent.border)
            )
            .padding(.horizontal, 6)
            .frame(height: 15)
            .background(SylvraColor.codeSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(AIAccent.border, lineWidth: 1))
            // Sits on the box's top edge, clear of the code.
            .offset(y: -7)
            .padding(.trailing, 10)
    }

    /// Position of `line` in the highlighted range (row index and number of rows).
    nonisolated static func span(of line: Int?, in lines: ClosedRange<Int>) -> (index: Int, count: Int) {
        let count = max(lines.count, 1)
        guard let line else { return (0, 1) }
        return (min(max(line - lines.lowerBound, 0), count - 1), count)
    }

    private func tapArea(_ action: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help("Show this AI finding")
    }
}

/// One row's slice of a finding's box (pure): the whole box is taller than the row and clipped to it, so the
/// first row shows the top with its rounded corners, the last row the bottom and rows between only the sides.
struct AIFindingBoxSlice: View {
    let isFirst: Bool
    let isLast: Bool
    /// 0…1: border and glow opacity (severity, hover).
    var strength: Double = 1
    var isSelected = false

    /// How far the box reaches past a middle row, enough to hide the corners.
    private static let overhang: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let top = isFirst ? 0 : Self.overhang
            let bottom = isLast ? 0 : Self.overhang
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            ZStack {
                // Glow along the edges, fading towards the middle.
                shape.strokeBorder(AIAccent.boxBorder(isSelected: isSelected), lineWidth: 8)
                    .blur(radius: 5)
                    .opacity(0.22 * strength)
                    .mask(shape)
                shape.strokeBorder(AIAccent.boxBorder(isSelected: isSelected), lineWidth: isSelected ? 2 : 1.5)
                    .opacity(isSelected ? 1 : strength)
            }
            .frame(width: geometry.size.width, height: geometry.size.height + top + bottom)
            .offset(y: -top)
        }
        .padding(.top, isFirst ? 1 : 0)
        .padding(.bottom, isLast ? 1 : 0)
        .clipped()
    }
}

#Preview("AI finding box") {
    VStack(spacing: 0) {
        ForEach(0..<4) { index in
            Text("    if (!options.Value.Enabled) return;")
                .font(.system(size: 12.5, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: diffRowHeight, alignment: .leading)
                .background(DiffColors.background(.added))
                .overlay { AIFindingBoxSlice(isFirst: index == 0, isLast: index == 3) }
        }
    }
    .frame(width: 480)
    .padding()
}

extension View {
    /// A plain click on a highlighted line opens its finding, without blocking text selection in the code
    /// (drags and double-clicks select text as usual).
    func selectsFinding(_ id: String?, using select: ((String) -> Void)?) -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                if let id, let select { select(id) }
            },
            including: id == nil ? .subviews : .all)
    }
}
