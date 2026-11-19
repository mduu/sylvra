import DesignSystem
import SwiftUI

/// A line's code at full length, shifted by the diff's horizontal scroll offset and clipped (pure).
/// Long lines used to be cut off at the right edge. Dragging selects code across lines, from a column to a
/// column (`DiffTextSelectionController`); the last selected line carries *Ask AI* and *Copy*.
struct ScrollingCodeText: View {
    let text: AttributedString
    /// Characters in the line (columns a selection can reach).
    let length: Int
    let selectionKey: DiffTextSelectionController.RowKey?
    @Environment(\.diffHorizontalOffset) private var offset
    @Environment(\.diffTextSelection) private var selection

    var body: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: -offset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) { highlight }
            .overlay(alignment: .leading) { actions }
            .clipped()
            .modifier(SelectionTracking(key: selectionKey, length: length, controller: selection))
    }

    private var selected: (selection: DiffTextSelection, columns: Range<Int>)? {
        guard let key = selectionKey, let current = selection?.selection, current.path == key.path,
            current.lane == key.lane, let columns = current.columns(hunk: key.hunk, row: key.row)
        else { return nil }
        return (current, columns)
    }

    /// The selected columns; a line selected to its end includes one cell for the line break.
    @ViewBuilder private var highlight: some View {
        if let columns = selected?.columns {
            let width = DiffTextSelectionController.characterWidth
            let lower = min(columns.lowerBound, length)
            let upper = columns.upperBound == Int.max ? length + 1 : min(columns.upperBound, length)
            if upper > lower {
                DiffColors.textSelection
                    .frame(width: CGFloat(upper - lower) * width)
                    .offset(x: CGFloat(lower) * width - offset)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Right of the selection's end, on its last line.
    @ViewBuilder private var actions: some View {
        if let selected, let key = selectionKey, let controller = selection,
            selected.selection.end.hunk == key.hunk, selected.selection.end.row == key.row
        {
            let endColumn = min(selected.selection.end.column, length)
            DiffSelectionActionsView(
                askAI: controller.askAI.map { askAI in { askAI(selected.selection) } },
                copy: controller.copy.map { copy in { copy(selected.selection) } }
            )
            .offset(x: max(CGFloat(endColumn) * DiffTextSelectionController.characterWidth - offset + 8, 4))
            .transition(.opacity)
        }
    }
}

/// Registers a row's code frame for mouse selection (the drag itself is on the whole diff, so it survives rows
/// the lazy stack drops while scrolling); a click into the code clears the selection.
private struct SelectionTracking: ViewModifier {
    let key: DiffTextSelectionController.RowKey?
    let length: Int
    let controller: DiffTextSelectionController?

    func body(content: Content) -> some View {
        if let key, let controller {
            content
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(DiffTextSelectionController.coordinateSpace))
                } action: { frame in
                    controller.register(key, frame: frame, length: length)
                }
                .onDisappear { controller.unregister(key) }
                .simultaneousGesture(TapGesture().onEnded { controller.clear() })
        } else {
            content
        }
    }
}
