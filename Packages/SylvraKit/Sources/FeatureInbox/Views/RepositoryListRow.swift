import SwiftUI

/// A repository in the sidebar with its number of open pull requests (pure).
struct RepositoryListRow: View {
    let repository: InboxRepository
    let openCount: Int?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(repository.name).lineLimit(1)
                Text(repository.owner).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let openCount {
                Text(openCount, format: .number)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .help("All open pull requests of \(repository.fullName)")
    }
}

#Preview {
    List {
        RepositoryListRow(repository: InboxRepository(owner: "DigitecGalaxus", name: "devinite"), openCount: 340)
        RepositoryListRow(repository: InboxRepository(owner: "DigitecGalaxus", name: "Dg.Newsletter"), openCount: 12)
    }
    .frame(width: 280)
}
