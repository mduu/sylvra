import DesignSystem
import SwiftUI

/// Content placed between diff lines, indented past the gutter; the gutter keeps running (pure).
struct AccessoryLane<Content: View>: View {
    var minWidth: CGFloat = 0
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
        .padding(.leading, 62)
        .background(alignment: .leading) { if drawsSurface { SylvraColor.codeGutter.frame(width: 62) } }
        .background(drawsSurface ? SylvraColor.codeSurface : .clear)
    }
}

/// A half's gutter column with the code surface beside it (background only).
struct GutterStrip: View {
    var continuation: HalfContinuation = .none

    var body: some View {
        HStack(spacing: 0) {
            SylvraColor.codeGutter.frame(width: 62)
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
