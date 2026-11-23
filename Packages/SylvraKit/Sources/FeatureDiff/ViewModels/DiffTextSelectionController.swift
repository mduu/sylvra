import AppKit
import Observation
import SwiftUI

/// Mouse selection across diff lines (shared by the rows of one diff): which rows are on screen and where,
/// and the current selection. Rows register their code frames; a drag on the diff maps the pointer to the row
/// under it. Held at the top or bottom edge (or beyond), the diff scrolls on and the selection grows with it.
@MainActor @Observable
final class DiffTextSelectionController {
    /// One row's code in one lane.
    struct RowKey: Hashable {
        let path: String
        let lane: DiffSelectionLane
        let hunk: Int
        let row: Int
    }

    /// A side-by-side row's place; its halves are separate lanes.
    struct RowPlace {
        let path: String
        let hunk: Int
        let row: Int

        func key(_ lane: DiffSelectionLane) -> RowKey { RowKey(path: path, lane: lane, hunk: hunk, row: row) }
    }

    private struct RowInfo {
        var frame: CGRect
        var length: Int
    }

    /// Coordinate space of the diff's content; row frames and drag locations are in it.
    nonisolated static let coordinateSpace = "diffTextSelection"
    /// Width of one character of the diff's code font (monospaced).
    static let characterWidth: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        return ("M" as NSString).size(withAttributes: [.font: font]).width
    }()

    private(set) var selection: DiffTextSelection?
    @ObservationIgnored private var rows: [RowKey: RowInfo] = [:]
    @ObservationIgnored private var isDragging = false
    /// The drag started outside code (gutter, thread, header): it selects nothing.
    @ObservationIgnored private var ignoresDrag = false
    /// Visible part of the diff in content coordinates (set by the screen while scrolling).
    @ObservationIgnored var visibleRect: CGRect = .zero {
        // The diff moves under a resting pointer: the hovered row changes with it.
        didSet {
            if let point = hoverPoint, visibleRect.minY != oldValue.minY {
                hover(at: CGPoint(x: point.x, y: point.y + visibleRect.minY - oldValue.minY))
            }
        }
    }
    /// One per row lane, so only the lane the pointer leaves and the one it enters redraw.
    @ObservationIgnored private var hoverFlags: [RowKey: HoverFlag] = [:]
    @ObservationIgnored private var hovered: RowKey?
    @ObservationIgnored private var hoverPoint: CGPoint?
    /// Scrolls the diff by a distance (set by the screen); positive is down.
    @ObservationIgnored var scrollBy: ((CGFloat) -> Void)?
    /// Where the pointer is while dragging: x in content coordinates, y in the visible part (stays put while
    /// the diff scrolls under it).
    private struct Pointer {
        let x: CGFloat
        let yInView: CGFloat
        let horizontalOffset: CGFloat
    }

    @ObservationIgnored private var pointer: Pointer?
    @ObservationIgnored private var autoscroll: Task<Void, Never>?
    /// Opens a chat about the selection (wired by the screen; `nil` hides "Ask AI").
    @ObservationIgnored var askAI: ((DiffTextSelection) -> Void)?
    @ObservationIgnored var copy: ((DiffTextSelection) -> Void)?

    func register(_ key: RowKey, frame: CGRect, length: Int) {
        rows[key] = RowInfo(frame: frame, length: length)
    }

    func unregister(_ key: RowKey) {
        rows[key] = nil
    }

    // MARK: Hover

    /// Whether a row lane is under the pointer (its gutter shows the comment and IDE buttons).
    @MainActor @Observable
    final class HoverFlag {
        var isHovered = false
    }

    /// The hover state of a lane; rows read it in their body.
    func hoverFlag(for key: RowKey) -> HoverFlag {
        if let flag = hoverFlags[key] { return flag }
        let flag = HoverFlag()
        hoverFlags[key] = flag
        return flag
    }

    /// The pointer moved over the diff (content coordinates; `nil`: it left). One hover handler for the whole
    /// diff instead of one per row: hit-testing hundreds of row hover areas on every mouse move cost up to
    /// half a CPU core while the pointer crossed a large diff.
    func hover(at point: CGPoint?) {
        hoverPoint = point
        let key = point.flatMap { point in
            DiffHoverLane.lane(at: point, in: rows.map { (key: $0.key, frame: $0.value.frame) })
        }
        guard key != hovered else { return }
        if let hovered { hoverFlags[hovered]?.isHovered = false }
        hovered = key
        if let key { hoverFlag(for: key).isHovered = true }
    }

    /// Rows are built from scratch (another layout, scope or commit): their hover states go with them.
    func resetHover() {
        hoverFlags = [:]
        hovered = nil
    }

    /// A drag on the diff (content coordinates): starts a selection in the code under `start`, or moves its end
    /// to the row under the pointer.
    func drag(from start: CGPoint, to location: CGPoint, horizontalOffset: CGFloat) {
        if !isDragging {
            isDragging = true
            guard let key = row(containing: start),
                let anchor = position(at: start, in: key, horizontalOffset: horizontalOffset)
            else {
                ignoresDrag = true
                return
            }
            selection = DiffTextSelection(path: key.path, lane: key.lane, anchor: anchor, head: anchor)
        }
        guard !ignoresDrag else { return }
        pointer = Pointer(x: location.x, yInView: location.y - visibleRect.minY, horizontalOffset: horizontalOffset)
        extend(to: location, horizontalOffset: horizontalOffset)
        updateAutoscroll()
    }

    func endDrag() {
        isDragging = false
        ignoresDrag = false
        pointer = nil
        autoscroll?.cancel()
        autoscroll = nil
        if selection?.isEmpty == true { selection = nil }
    }

    private func extend(to location: CGPoint, horizontalOffset: CGFloat) {
        guard var current = selection,
            let target = nearestRow(to: location.y, path: current.path, lane: current.lane),
            let head = position(at: location, in: target, horizontalOffset: horizontalOffset)
        else { return }
        current.head = head
        if current != selection { selection = current }
    }

    // MARK: Scrolling while dragging at an edge

    /// Height at the top covered by the pinned file header; the pointer there already scrolls up.
    private nonisolated static let topEdge: CGFloat = 44
    private nonisolated static let bottomEdge: CGFloat = 16

    /// Scroll speed (points per tick) for the pointer's distance into or beyond an edge zone; 0 inside.
    nonisolated static func autoscrollSpeed(pointerY: CGFloat, viewHeight: CGFloat) -> CGFloat {
        let overTop = topEdge - pointerY
        let overBottom = pointerY - (viewHeight - bottomEdge)
        let distance = overTop > 0 ? -overTop : (overBottom > 0 ? overBottom : 0)
        guard distance != 0 else { return 0 }
        // Faster the further out, like text editors; capped so the selection stays followable.
        let speed = min(4 + abs(distance) * 0.5, 60)
        return distance < 0 ? -speed : speed
    }

    private func updateAutoscroll() {
        guard let pointer, autoscroll == nil,
            Self.autoscrollSpeed(pointerY: pointer.yInView, viewHeight: visibleRect.height) != 0
        else { return }
        autoscroll = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isDragging, let pointer = self.pointer {
                let speed = Self.autoscrollSpeed(pointerY: pointer.yInView, viewHeight: self.visibleRect.height)
                guard speed != 0 else { break }
                self.scrollBy?(speed)
                try? await Task.sleep(for: .milliseconds(16))
                // The pointer stands still on screen while the content moves under it.
                let location = CGPoint(x: pointer.x, y: self.visibleRect.minY + pointer.yInView)
                self.extend(to: location, horizontalOffset: pointer.horizontalOffset)
            }
            self?.autoscroll = nil
        }
    }

    func clear() {
        guard !isDragging, selection != nil else { return }
        selection = nil
    }

    private func position(at point: CGPoint, in key: RowKey, horizontalOffset: CGFloat) -> DiffTextPosition? {
        guard let info = rows[key] else { return nil }
        let column = Int(((point.x - info.frame.minX + horizontalOffset) / Self.characterWidth).rounded())
        return DiffTextPosition(hunk: key.hunk, row: key.row, column: min(max(column, 0), info.length))
    }

    private func row(containing point: CGPoint) -> RowKey? {
        rows.first { $0.value.frame.contains(point) }?.key
    }

    /// The row under `y`, or the closest one (between rows: review threads, hunk headers; outside the view).
    private func nearestRow(to y: CGFloat, path: String, lane: DiffSelectionLane) -> RowKey? {
        rows.filter { $0.key.path == path && $0.key.lane == lane }
            .min { distance(y, $0.value.frame) < distance(y, $1.value.frame) }?.key
    }

    private func distance(_ y: CGFloat, _ frame: CGRect) -> CGFloat {
        y < frame.minY ? frame.minY - y : (y >= frame.maxY ? y - frame.maxY + 0.5 : 0)
    }
}
