import SwiftUI

// Parts of `DiffScreen` that observe the model on their own, so their updates don't re-evaluate every row.

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

/// Find in diff: searches once per update of its own (in `DiffScreen.body` every diff update searched twice).
struct DiffSearchPanel: View {
    @Bindable var model: DiffScreenModel

    var body: some View {
        let matches = model.searchMatches
        DiffSearchBar(
            query: $model.searchQuery,
            matchCount: matches.count,
            currentIndex: model.currentSearchMatch.flatMap { matches.firstIndex(of: $0) },
            next: { model.selectSearchMatch(offset: 1) },
            previous: { model.selectSearchMatch(offset: -1) },
            close: { model.isSearchPresented = false }
        )
    }
}
