import SwiftUI

/// Remembers the widths the user dragged the columns to and restores them at launch.
///
/// `NavigationSplitView` and `.inspector` don't persist column widths, so each column reports its width
/// and the stored value becomes the column's ideal width at the next launch. The stored values are read
/// once: feeding them back while dragging would fight the split view.
enum ColumnLayout {
    enum Column: String {
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

        var key: String { "layout.columnWidth.\(rawValue)" }
    }

    /// The width to start with: the last width the user chose, otherwise the default.
    static func initialWidth(_ column: Column, defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.double(forKey: column.key)
        guard stored > 0 else { return column.defaultWidth }
        return min(max(stored, column.range.lowerBound), column.range.upperBound)
    }

    /// Saves a width the column was laid out with (ignores hidden or collapsing columns).
    static func save(_ width: CGFloat, for column: Column, defaults: UserDefaults = .standard) {
        guard column.range.contains(width) else { return }
        defaults.set(Double(width.rounded()), forKey: column.key)
    }
}

extension View {
    /// Column width that is stable while content changes and remembered across launches.
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
                ColumnLayout.save(width, for: column)
            }
    }

    /// The detail column: only decoupled from its content (it takes the remaining width).
    func stableColumn() -> some View {
        frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity).clipped()
    }
}
