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
    /// The last row of its hunk: the hunk header below breaks the selection's shape.
    var isLastInHunk = false
    @Environment(\.diffHorizontalOffset) private var offset
    @Environment(\.diffTextSelection) private var selection

    var body: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: -offset)
            // Full row height: the selection's rows join without gaps.
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

    /// This row's part of the selection: a translucent fill with the outline's edges (a line selected past its
    /// end runs to the right edge, like in an editor).
    private var outline: DiffSelectionOutline? {
        guard let selected, let key = selectionKey else { return nil }
        let current = selected.selection
        func clamped(_ columns: Range<Int>?) -> Range<Int>? {
            guard let columns else { return nil }
            let lower = min(columns.lowerBound, length)
            let upper = columns.upperBound == Int.max ? Int.max : min(columns.upperBound, length)
            return upper > lower ? lower..<upper : nil
        }
        guard let row = clamped(selected.columns) else { return nil }
        // Neighbours in the same hunk; their own lengths don't matter for full rows (to the right edge).
        let above = key.row > 0 ? current.columns(hunk: key.hunk, row: key.row - 1) : nil
        let below = isLastInHunk ? nil : current.columns(hunk: key.hunk, row: key.row + 1)
        return DiffSelectionOutline(row: row, above: above, below: below)
    }

    @ViewBuilder private var highlight: some View {
        if let outline {
            let width = DiffTextSelectionController.characterWidth
            let offset = offset
            Canvas { context, size in
                func x(_ column: Int) -> CGFloat {
                    column == Int.max ? size.width + 2 : CGFloat(column) * width - offset
                }
                let fill = CGRect(
                    x: x(outline.fill.lowerBound), y: 0,
                    width: x(outline.fill.upperBound) - x(outline.fill.lowerBound), height: size.height)
                context.fill(Path(fill), with: .color(DiffColors.selectionFill))
                var border = Path()
                border.move(to: CGPoint(x: fill.minX + 0.5, y: 0))
                border.addLine(to: CGPoint(x: fill.minX + 0.5, y: size.height))
                if outline.closesRight {
                    border.move(to: CGPoint(x: fill.maxX - 0.5, y: 0))
                    border.addLine(to: CGPoint(x: fill.maxX - 0.5, y: size.height))
                }
                for range in outline.top {
                    border.move(to: CGPoint(x: x(range.lowerBound), y: 0.5))
                    border.addLine(to: CGPoint(x: x(range.upperBound), y: 0.5))
                }
                for range in outline.bottom {
                    border.move(to: CGPoint(x: x(range.lowerBound), y: size.height - 0.5))
                    border.addLine(to: CGPoint(x: x(range.upperBound), y: size.height - 0.5))
                }
                context.stroke(border, with: .color(DiffColors.selectionBorder), lineWidth: 1)
            }
            .allowsHitTesting(false)
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
