import AppKit
import DesignSystem
import SwiftUI

/// Content placed between diff lines, indented past the gutter; the gutter keeps running (pure).
struct AccessoryLane<Content: View>: View {
    var minWidth: CGFloat = 0
    /// Width of the gutter the lane continues (inline has two line-number columns).
    var gutterWidth: CGFloat = halfGutterWidth
    /// How the line above continues through the lane (change bar).
    var continuation: HalfContinuation = .none
    /// Side by side draws the surfaces once behind both lanes (with the continued ribbon and bars).
    var drawsSurface = true
    @ViewBuilder let content: Content

    var body: some View {
        // The zero-height placeholder keeps an empty lane in the layout (an empty `if` would vanish and let
        // the other side's thread take the full width).
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 0)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, gutterWidth)
        .background {
            if drawsSurface { GutterStrip(gutterWidth: gutterWidth, continuation: continuation) }
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

/// Xcode-style AI highlight: a soft gradient fading to the right, a gold edge and ✦ for the selected finding (pure).
struct AIHighlightOverlay: View {
    let highlight: LineHighlight?
    /// Clicks on the gutter keep starting comments.
    var gutterWidth: CGFloat = halfGutterWidth
    @Environment(\.diffSelectFinding) private var selectFinding
    @State private var isHovered = false

    var body: some View {
        if let highlight {
            ZStack(alignment: .leading) {
                AIAccent.lineGradient(
                    opacity: highlight.isSelected ? 0.45 : 0.18 + 0.22 * highlight.intensity + (isHovered ? 0.12 : 0))
                Rectangle()
                    .fill(highlight.isSelected ? AnyShapeStyle(SylvraColor.accentGold) : AnyShapeStyle(AIAccent.border))
                    .frame(width: 3)
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(
                        highlight.isSelected ? AnyShapeStyle(SylvraColor.accentGold) : AnyShapeStyle(AIAccent.border)
                    )
                    .padding(.trailing, 6)
                    .opacity(highlight.isSelected || isHovered ? 1 : 0.45)
            }
            .allowsHitTesting(false)
            .overlay {
                // Clicking the code of a highlighted line opens its finding; the gutter keeps its comment action.
                if !highlight.isSelected, let id = highlight.findingID, let selectFinding {
                    Color.clear
                        .contentShape(Rectangle())
                        .padding(.leading, gutterWidth)
                        .onTapGesture { selectFinding(id) }
                        .onHover { hovering in
                            isHovered = hovering
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                        .help("Show this AI finding")
                }
            }
            .transition(.opacity)
        }
    }
}
