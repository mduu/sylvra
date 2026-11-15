import Testing

@testable import FeatureDiff

struct FileTreeTests {
    private func file(_ path: String) -> FileDiff {
        FileDiff(
            path: path, status: .modified,
            hunks: [
                Hunk(
                    oldStart: 1, oldCount: 1, newStart: 1, newCount: 1,
                    lines: [
                        DiffLine(kind: .added, oldNumber: nil, newNumber: 1, text: "x")
                    ])
            ])
    }

    @Test func buildsHierarchyWithCompactedChains() throws {
        let tree = FileTreeNode.build([
            file("Sources/Billing/Invoice.swift"), file("Sources/Billing/InvoiceService.swift"),
            file("Sources/Export/CSVEncoder.swift"), file("README.md"),
        ])
        #expect(tree.map(\.name) == ["Sources", "README.md"])
        let sources = try #require(tree.first)
        #expect(sources.children.map(\.name) == ["Billing", "Export"])
        #expect(sources.files.count == 3)
        #expect(sources.additions == 3)
        #expect(sources.children[0].children.map(\.name) == ["Invoice.swift", "InvoiceService.swift"])
    }

    @Test func compactsSingleChildFolders() throws {
        let tree = FileTreeNode.build([file("App/Sources/Feature/A.swift"), file("App/Sources/Feature/B.swift")])
        let folder = try #require(tree.first)
        #expect(folder.name == "App/Sources/Feature")
        #expect(folder.path == "App/Sources/Feature")
        #expect(folder.children.count == 2)
    }
}
