import DesignSystem
import SwiftUI

/// A file or folder row of the navigator (for app-provided context menu items).
public enum NavigatorItem: Hashable, Sendable {
    case file(path: String)
    /// Repository-relative folder; `""` is the root.
    case folder(path: String)
}

/// Change map + files by namespace with viewed toggles (container; placed in the PR column by the app).
/// `itemMenu` is a slot for extra context menu items of file and folder rows (e.g. custom tools).
public struct DiffFileNavigatorPanel<ItemMenu: View>: View {
    private let model: DiffScreenModel
    private let itemMenu: (NavigatorItem) -> ItemMenu
    /// `tree` (folder hierarchy) or `folders` (grouped by folder); remembered per user.
    @AppStorage("fileNavigatorStyle") private var style = "tree"

    public init(model: DiffScreenModel, @ViewBuilder itemMenu: @escaping (NavigatorItem) -> ItemMenu) {
        self.model = model
        self.itemMenu = itemMenu
    }

    public var body: some View {
        if !model.files.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header("Change map")
                ChangeMapView(tiles: tiles) { folder in
                    model.selectedPath = model.orderedFiles.first { $0.directory == folder }?.path
                }
                .frame(height: 120)

                HStack {
                    header("Files")
                    Spacer()
                    Text("\(model.viewedCount) of \(model.files.count) viewed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Files", selection: $style) {
                        Label("Tree", systemImage: "list.bullet.indent").tag("tree")
                        Label("Grouped by folder", systemImage: "folder").tag("folders")
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .fixedSize()
                    .labelsHidden()
                    .help("Show files as a tree or grouped by folder")
                }
                ProgressView(value: Double(model.viewedCount), total: Double(max(model.files.count, 1)))
                    .tint(SylvraColor.brandPrimary)
                if !model.readingOrder.isEmpty {
                    Toggle(isOn: Binding(get: { model.usesReadingOrder }, set: { model.usesReadingOrder = $0 })) {
                        Label("Sort diff by AI reading order", systemImage: "sparkles")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if style == "tree" {
                    ForEach(model.fileTree) { node in treeRows(node, depth: 0) }
                } else {
                    groupedRows
                }
            }
            .animation(.snappy, value: model.collapsedFolders)
            .animation(.snappy, value: style)
        }
    }

    /// Folder hierarchy with collapsible folders (recursive; `AnyView` breaks the recursive opaque type).
    private func treeRows(_ node: FileTreeNode, depth: Int) -> AnyView {
        if let file = node.file {
            return AnyView(
                FileRowView(
                    file: file,
                    isViewed: model.isViewed(file.path),
                    isSelected: model.selectedPath == file.path,
                    select: { model.selectedPath = file.path },
                    toggleViewed: { Task { await model.toggleViewed(file.path) } },
                    menu: itemMenu(.file(path: file.path)),
                    readingNumber: model.readingStep(for: file.path)?.number
                )
                .padding(.leading, CGFloat(depth) * 14))
        }
        let isCollapsed = model.collapsedFolders.contains(node.path)
        let files = node.files
        let viewed = files.count { model.isViewed($0.path) }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                TreeFolderRowView(
                    node: node,
                    isCollapsed: isCollapsed,
                    viewedCount: viewed,
                    toggle: { model.toggleFolder(node.path) },
                    setViewed: { value in
                        Task {
                            for file in files where model.isViewed(file.path) != value {
                                await model.toggleViewed(file.path)
                            }
                        }
                    },
                    menu: itemMenu(.folder(path: node.path))
                )
                .padding(.leading, CGFloat(depth) * 14)
                if !isCollapsed {
                    ForEach(node.children) { child in treeRows(child, depth: depth + 1) }
                }
            })
    }

    @ViewBuilder private var groupedRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.folder) { group in
                FolderRowView(
                    folder: group.folder,
                    allViewed: group.files.allSatisfy { model.isViewed($0.path) },
                    setViewed: { viewed in Task { await model.setViewed(viewed, folder: group.folder) } },
                    menu: itemMenu(.folder(path: group.folder))
                )
                ForEach(group.files) { file in
                    FileRowView(
                        file: file,
                        isViewed: model.isViewed(file.path),
                        isSelected: model.selectedPath == file.path,
                        select: { model.selectedPath = file.path },
                        toggleViewed: { Task { await model.toggleViewed(file.path) } },
                        menu: itemMenu(.file(path: file.path)),
                        readingNumber: model.readingStep(for: file.path)?.number
                    )
                }
            }
        }
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
    }

    private var groups: [(folder: String, files: [FileDiff])] {
        var order: [String] = []
        var byFolder: [String: [FileDiff]] = [:]
        for file in model.orderedFiles {
            if byFolder[file.directory] == nil { order.append(file.directory) }
            byFolder[file.directory, default: []].append(file)
        }
        return order.map { ($0, byFolder[$0] ?? []) }
    }

    private var tiles: [ChangeMapView.Tile] {
        groups.filter { !$0.files.allSatisfy(\.kind.isNoise) }
            .map { group in
                ChangeMapView.Tile(
                    folder: group.folder,
                    additions: group.files.reduce(0) { $0 + $1.additions },
                    deletions: group.files.reduce(0) { $0 + $1.deletions })
            }
            .sorted { $0.weight > $1.weight }
    }
}

extension DiffFileNavigatorPanel where ItemMenu == EmptyView {
    public init(model: DiffScreenModel) {
        self.init(model: model) { _ in EmptyView() }
    }
}

private struct FolderRowView<Menu: View>: View {
    let folder: String
    let allViewed: Bool
    let setViewed: (Bool) -> Void
    let menu: Menu

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(folder.isEmpty ? "/" : folder).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.head)
            Spacer()
        }
        .padding(.top, 4)
        .contextMenu {
            Button("Mark all as viewed") { setViewed(true) }
            Button("Mark all as not viewed") { setViewed(false) }
            menu
        }
    }
}

private struct FileRowView<Menu: View>: View {
    let file: FileDiff
    let isViewed: Bool
    let isSelected: Bool
    let select: () -> Void
    let toggleViewed: () -> Void
    let menu: Menu
    var readingNumber: Int?

    var body: some View {
        HStack(spacing: 6) {
            Toggle("Viewed", isOn: Binding(get: { isViewed }, set: { _ in toggleViewed() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            FileKindIcon(kind: file.kind)
            Text(file.fileName).lineLimit(1).foregroundStyle(isViewed ? .secondary : .primary)
            if let readingNumber {
                Text(verbatim: "\(readingNumber)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 14, minHeight: 14)
                    .background(AIAccent.border, in: Circle())
                    .help("Suggested reading order (AI)")
            }
            Spacer(minLength: 4)
            Text(verbatim: "+\(file.additions) −\(file.deletions)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.leading, 14)
        .padding(.vertical, 3)
        .padding(.trailing, 6)
        .background(isSelected ? SylvraColor.brandPrimary.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .contextMenu {
            Button(isViewed ? "Mark as not viewed" : "Mark as viewed", action: toggleViewed)
            menu
        }
    }
}

/// A folder in the tree: chevron, name, file count, aggregated +/− and an all-viewed checkbox (pure).
private struct TreeFolderRowView<Menu: View>: View {
    let node: FileTreeNode
    let isCollapsed: Bool
    let viewedCount: Int
    let toggle: () -> Void
    let setViewed: (Bool) -> Void
    let menu: Menu

    var body: some View {
        let fileCount = node.files.count
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .frame(width: 10)
                .foregroundStyle(.secondary)
            Image(systemName: isCollapsed ? "folder" : "folder.fill")
                .foregroundStyle(SylvraColor.brandPrimary.opacity(0.8))
            Text(node.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
            Text("\(fileCount)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 5)
                .background(.quaternary, in: Capsule())
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(verbatim: "+\(node.additions) −\(node.deletions)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Toggle("All viewed", isOn: Binding(get: { viewedCount == fileCount }, set: { setViewed($0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("\(viewedCount) of \(fileCount) viewed")
        }
        .padding(.vertical, 4)
        .padding(.trailing, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .contextMenu {
            Button("Mark all as viewed") { setViewed(true) }
            Button("Mark all as not viewed") { setViewed(false) }
            menu
        }
    }
}
