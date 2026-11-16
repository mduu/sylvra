import DesignSystem
import SwiftUI

/// Treemap of the changed folders: area = changed lines (pure, see specs/ux.md §6.3).
struct ChangeMapView: View {
    struct Tile: Identifiable, Hashable {
        var id: String { folder }
        let folder: String
        let additions: Int
        let deletions: Int
        var weight: Int { max(additions + deletions, 1) }
    }

    let tiles: [Tile]
    let select: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            let frames = Self.layout(tiles, in: CGRect(origin: .zero, size: geometry.size))
            ForEach(Array(zip(tiles, frames)), id: \.0) { tile, frame in
                Button {
                    select(tile.folder)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tile.folder.isEmpty ? "/" : (tile.folder as NSString).lastPathComponent)
                            .font(.caption.weight(.semibold))
                        if frame.height > 34 {
                            Text(verbatim: "+\(tile.additions) −\(tile.deletions)").font(.caption2).opacity(0.85)
                        }
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(6)
                    .frame(width: max(frame.width - 3, 0), height: max(frame.height - 3, 0), alignment: .topLeading)
                    .background(color(for: tile).gradient, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(tile.folder)
                .position(x: frame.midX, y: frame.midY)
            }
        }
    }

    private func color(for tile: Tile) -> Color {
        // More additions → brand violet, more deletions → muted plum.
        let share = Double(tile.additions) / Double(max(tile.additions + tile.deletions, 1))
        return SylvraColor.brandPrimary.mix(with: Color(red: 0.55, green: 0.24, blue: 0.40), by: 1 - share)
    }

    /// One tile per folder with changed lines (generated files and lockfiles left out), largest first.
    static func tiles(for files: [FileDiff]) -> [Tile] {
        var order: [String] = []
        var byFolder: [String: [FileDiff]] = [:]
        for file in files where !file.kind.isNoise {
            if byFolder[file.directory] == nil { order.append(file.directory) }
            byFolder[file.directory, default: []].append(file)
        }
        return order.map { folder in
            let group = byFolder[folder] ?? []
            return Tile(
                folder: folder, additions: group.reduce(0) { $0 + $1.additions },
                deletions: group.reduce(0) { $0 + $1.deletions })
        }
        .sorted { $0.weight > $1.weight }
    }

    /// Slice-and-dice layout, alternating direction, largest first.
    static func layout(_ tiles: [Tile], in rect: CGRect) -> [CGRect] {
        guard !tiles.isEmpty else { return [] }
        var frames: [CGRect] = []
        var remaining = rect
        var total = Double(tiles.map(\.weight).reduce(0, +))
        for (index, tile) in tiles.enumerated() {
            if index == tiles.count - 1 {
                frames.append(remaining)
                break
            }
            let share = Double(tile.weight) / total
            if remaining.width >= remaining.height {
                let width = remaining.width * share
                frames.append(CGRect(x: remaining.minX, y: remaining.minY, width: width, height: remaining.height))
                remaining = CGRect(
                    x: remaining.minX + width, y: remaining.minY, width: remaining.width - width,
                    height: remaining.height)
            } else {
                let height = remaining.height * share
                frames.append(CGRect(x: remaining.minX, y: remaining.minY, width: remaining.width, height: height))
                remaining = CGRect(
                    x: remaining.minX, y: remaining.minY + height, width: remaining.width,
                    height: remaining.height - height)
            }
            total -= Double(tile.weight)
        }
        return frames
    }
}
