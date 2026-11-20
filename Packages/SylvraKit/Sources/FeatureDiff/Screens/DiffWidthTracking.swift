import SwiftUI

/// The diff's width, kept out of `DiffScreen`'s state: it changes on every frame while a column is resized,
/// and only the horizontal offset and the scroll indicator depend on it. Reading it in `DiffScreen.body`
/// re-evaluated every file's rows per frame.
@MainActor @Observable
final class DiffWidth {
    var value: CGFloat = 800
}

/// Publishes the clamped horizontal code offset; only this modifier re-runs while the width changes, and
/// the rows only update when the clamped offset does.
struct DiffHorizontalOffsetEnvironment: ViewModifier {
    let model: DiffScreenModel
    let width: DiffWidth

    func body(content: Content) -> some View {
        content.environment(
            \.diffHorizontalOffset, min(model.horizontalOffset, model.maxHorizontalOffset(diffWidth: width.value)))
    }
}

/// Shown while some line is wider than the view.
struct DiffHorizontalIndicator: View {
    let model: DiffScreenModel
    let width: DiffWidth

    var body: some View {
        let maxOffset = model.maxHorizontalOffset(diffWidth: width.value)
        if maxOffset > 0 {
            HorizontalScrollIndicator(
                offset: min(model.horizontalOffset, maxOffset), maxOffset: maxOffset,
                codeWidth: DiffScreenModel.codeWidth(diffWidth: width.value, layout: model.layout)
            ) { model.scrollHorizontally(by: $0, diffWidth: width.value) }
        }
    }
}
