import AppKit
import DesignSystem
import Platform
import SwiftUI

/// Bottom panel listing the GitHub requests and commands of this session (container). `accessory` is a slot
/// for app-provided header actions (e.g. switching to the terminal).
public struct CommandLogPanel<Accessory: View>: View {
    private let log: CommandLog
    private let accessory: Accessory
    @State private var filter: CommandLogFilter = .all
    @State private var searchText = ""
    @State private var expanded: Set<UUID> = []

    public init(log: CommandLog = .shared, @ViewBuilder accessory: () -> Accessory) {
        self.log = log
        self.accessory = accessory()
    }

    private var visibleEntries: [CommandLogEntry] {
        filter.apply(log.entries, searchText: searchText).reversed()
    }

    public var body: some View {
        VStack(spacing: 0) {
            CommandLogHeaderView(
                filter: $filter, searchText: $searchText, count: visibleEntries.count,
                failures: visibleEntries.filter(\.isFailure).count,
                copy: copy, clear: { log.clear() }, accessory: accessory
            )
            .background(.bar)
            Divider()
            if visibleEntries.isEmpty {
                ContentUnavailableView(
                    "No commands yet", systemImage: "list.bullet.rectangle",
                    description: Text("GitHub requests, git and other commands show up here as Sylvra runs them."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleEntries) { entry in
                            CommandLogRowView(
                                entry: entry, isExpanded: expanded.contains(entry.id),
                                toggle: { toggle(entry.id) })
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .background(SylvraColor.surfacePrimary)
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func copy() {
        let text = visibleEntries.reversed().map(CommandLogRowView.plainText).joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Which entries the panel shows.
enum CommandLogFilter: String, CaseIterable, Identifiable {
    case all, github, git, process, failures

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .github: String(localized: "GitHub")
        case .git: String(localized: "git")
        case .process: String(localized: "Other")
        case .failures: String(localized: "Failed")
        }
    }

    func apply(_ entries: [CommandLogEntry], searchText: String) -> [CommandLogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            let matchesKind =
                switch self {
                case .all: true
                case .github: entry.kind == .github
                case .git: entry.kind == .git
                case .process: entry.kind == .process
                case .failures: entry.isFailure
                }
            return matchesKind && (query.isEmpty || entry.title.localizedCaseInsensitiveContains(query))
        }
    }
}

/// Filter, search and actions above the list (pure).
struct CommandLogHeaderView<Accessory: View>: View {
    @Binding var filter: CommandLogFilter
    @Binding var searchText: String
    let count: Int
    let failures: Int
    var copy: () -> Void = {}
    var clear: () -> Void = {}
    let accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Label("Commands", systemImage: "list.bullet.rectangle").font(.callout.weight(.semibold))
            Picker("Show", selection: $filter) {
                ForEach(CommandLogFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            TextField("Filter", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            Text("\(count) entries").font(.caption).foregroundStyle(.secondary)
            if failures > 0 {
                Text("\(failures) failed").font(.caption.weight(.medium)).foregroundStyle(.red)
            }
            Spacer()
            Button("Copy", systemImage: "doc.on.doc", action: copy)
                .labelStyle(.iconOnly)
                .help("Copy the shown entries")
                .disabled(count < 1)
            Button("Clear", systemImage: "trash", action: clear)
                .labelStyle(.iconOnly)
                .help("Clear the list")
            accessory
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
