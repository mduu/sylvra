import SwiftUI

/// The columns whose widths are remembered (per screen setup, see `DisplaySetupMonitor`).
///
/// `NavigationSplitView` and `.inspector` don't persist column widths, so each column reports its width
/// and the stored value becomes the column's ideal width when the columns are built (at launch and after a
/// screen change). Feeding the values back while dragging would fight the split view.
enum ColumnLayout {
    enum Column: String, CaseIterable {
        case inbox, pullRequest, inspector

        var range: ClosedRange<CGFloat> {
            switch self {
            case .inbox: 220...420
            case .pullRequest: 320...560
            case .inspector: 260...480
            }
        }

        var defaultWidth: CGFloat {
            switch self {
            case .inbox: 290
            case .pullRequest: 380
            case .inspector: 320
            }
        }

        /// Stored as `layout.columnWidth.<column>` before widths were remembered per setup.
        var memoryName: String { "columnWidth.\(rawValue)" }
    }
}

extension View {
    /// Column width that is stable while content changes and remembered per screen setup.
    ///
    /// The content can neither widen nor narrow the column (otherwise a refresh that changes a chip or a
    /// title makes the split view redistribute the columns); the limits come from the split view alone.
    ///
    /// `minHeight: 0` matters: a column whose minimum height follows its content (wrapping text in a pinned,
    /// non-scrolling area gets taller when narrower) made the split view re-layout endlessly — AppKit then
    /// aborted while zooming, or the window grew taller than the screen and no column could scroll.
    func rememberedColumn(_ column: ColumnLayout.Column, ideal: CGFloat) -> some View {
        frame(minWidth: 0, idealWidth: ideal, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: { width in
                DisplaySetupMonitor.shared.saveWidth(width, for: column)
            }
    }

    /// The detail column: only decoupled from its content (it takes the remaining width).
    func stableColumn() -> some View {
        frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity).clipped()
    }
}
