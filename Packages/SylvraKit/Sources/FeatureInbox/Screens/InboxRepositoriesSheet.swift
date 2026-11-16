import DesignSystem
import SwiftUI

/// Chooses the repositories the broad inbox sections search (container: owns the search).
public struct InboxRepositoriesSheet: View {
    @Bindable private var model: InboxScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [InboxRepository] = []
    @State private var isSearching = false
    @State private var searchError: String?

    public init(model: InboxScreenModel) {
        self.model = model
    }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Inbox repositories").font(.title3.weight(.semibold))
                Text(
                    // swiftlint:disable:next line_length
                    "“My teams”, “Involved” and “Recently closed” only search these repositories. Review requests to you and your own pull requests always come from all repositories."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                searchField.padding(.top, 6)
            }
            .padding(16)

            Divider()

            List {
                if trimmedSearch.count >= 2 {
                    searchSection
                } else {
                    chosenSection
                    suggestionsSection
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                if !model.scope.isAll {
                    Button("Show all repositories") { Task { await model.showAllRepositories() } }
                        .help("Search every repository you have access to (slow for large organizations)")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(SylvraColor.brandPrimary)
            }
            .padding(12)
        }
        .frame(width: 520, height: 560)
        .background(SylvraColor.surfaceElevated)
        .task(id: trimmedSearch) { await search(trimmedSearch) }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search repositories, e.g. org:acme billing", text: $searchText)
                .textFieldStyle(.plain)
            if isSearching { ProgressView().controlSize(.small) }
        }
        .padding(7)
        .background(.background, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator))
    }

    @ViewBuilder private var searchSection: some View {
        Section("Search results") {
            if let searchError {
                Label(searchError, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else if results.isEmpty, !isSearching {
                Text("No repositories found").foregroundStyle(.secondary)
            }
            ForEach(results) { repository in
                row(repository)
            }
        }
    }

    @ViewBuilder private var chosenSection: some View {
        Section("In your inbox") {
            if model.scope.isAll {
                Label("All repositories", systemImage: "square.stack.3d.up")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.scope.repositories) { repository in
                row(repository)
            }
        }
    }

    @ViewBuilder private var suggestionsSection: some View {
        let suggestions = model.suggestedRepositories
        if !suggestions.isEmpty {
            Section("From your current inbox") {
                ForEach(suggestions.prefix(12)) { repository in
                    row(repository)
                }
            }
        }
    }

    private func row(_ repository: InboxRepository) -> some View {
        let isAdded = model.scope.repositories.contains(repository)
        return InboxRepositoryRow(repository: repository, isAdded: isAdded) {
            Task {
                if isAdded {
                    await model.removeRepository(repository)
                } else {
                    await model.addRepository(repository)
                }
            }
        }
    }

    private func search(_ text: String) async {
        guard text.count >= 2, let searcher = model.repositorySearcher else {
            results = []
            return
        }
        // Debounce typing; the task is cancelled when the text changes.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await searcher.searchRepositories(matching: text)
            searchError = nil
        } catch is CancellationError {
        } catch {
            searchError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}

/// A repository with an add / remove button (pure).
struct InboxRepositoryRow: View {
    let repository: InboxRepository
    let isAdded: Bool
    var toggle: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(repository.fullName).fontWeight(.medium)
                if let summary = repository.summary, !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button(action: toggle) {
                Label(
                    isAdded ? "Remove from inbox" : "Add to inbox",
                    systemImage: isAdded ? "minus.circle" : "plus.circle.fill"
                )
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(isAdded ? AnyShapeStyle(.secondary) : AnyShapeStyle(SylvraColor.brandPrimary))
            }
            .buttonStyle(.plain)
            .help(isAdded ? "Remove from inbox" : "Add to inbox")
        }
        .padding(.vertical, 2)
    }
}

#Preview("Row") {
    VStack {
        InboxRepositoryRow(repository: DemoRepositorySearcher.repositories[0], isAdded: true)
        InboxRepositoryRow(repository: DemoRepositorySearcher.repositories[2], isAdded: false)
    }
    .padding()
    .frame(width: 420)
}

#Preview("Sheet") {
    InboxRepositoriesSheet(
        model: InboxScreenModel(loader: DemoInboxLoader(), repositorySearcher: DemoRepositorySearcher()))
}
