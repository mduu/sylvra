import Testing

@testable import FeatureDiff

struct UnifiedDiffParserTests {
    static let sample = """
        diff --git a/Sources/Billing/InvoiceService.swift b/Sources/Billing/InvoiceService.swift
        index 1111111..2222222 100644
        --- a/Sources/Billing/InvoiceService.swift
        +++ b/Sources/Billing/InvoiceService.swift
        @@ -40,7 +40,9 @@ struct InvoiceService {
         func total(for invoice: Invoice) -> Decimal {
        -    invoice.items.reduce(0) { $0 + $1.price }
        +    invoice.items.reduce(.zero) { sum, item in
        +        sum + item.price * item.quantity
        +    }
         }
        \u{20}
         func export() {}
        @@ -60,3 +62,2 @@ struct InvoiceService {
         let a = 1
        -let b = 2
         let c = 3
        \\ No newline at end of file
        diff --git a/README.md b/README.md
        new file mode 100644
        index 0000000..3333333
        --- /dev/null
        +++ b/README.md
        @@ -0,0 +1,2 @@
        +# Title
        +Text
        diff --git a/old.txt b/old.txt
        deleted file mode 100644
        --- a/old.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -bye
        diff --git a/A.swift b/B.swift
        similarity index 100%
        rename from A.swift
        rename to B.swift
        diff --git a/logo.png b/logo.png
        index 4444444..5555555 100644
        Binary files a/logo.png and b/logo.png differ
        """

    @Test func parsesAllFiles() {
        let files = UnifiedDiffParser.parse(Self.sample)
        #expect(
            files.map(\.path) == [
                "Sources/Billing/InvoiceService.swift", "README.md", "old.txt", "B.swift", "logo.png",
            ])
        #expect(files.map(\.status) == [.modified, .added, .deleted, .renamed, .modified])
        #expect(files[3].previousPath == "A.swift")
        #expect(files[4].isBinary)
    }

    @Test func parsesHunksAndLineNumbers() throws {
        let file = try #require(UnifiedDiffParser.parse(Self.sample).first)
        #expect(file.hunks.count == 2)
        let hunk = file.hunks[0]
        #expect(hunk.section == "struct InvoiceService {")
        #expect(hunk.oldStart == 40 && hunk.newStart == 40 && hunk.newCount == 9)
        #expect(hunk.lines[1].kind == .removed && hunk.lines[1].oldNumber == 41)
        #expect(hunk.lines[2].kind == .added && hunk.lines[2].newNumber == 41)
        #expect(hunk.lines.last?.newNumber == 46)
        #expect(file.additions == 3 && file.deletions == 2)
        #expect(file.hunks[1].lines.last?.missingNewline == true)
    }

    @Test func singleLineHunkHeader() throws {
        let file = try #require(UnifiedDiffParser.parse(Self.sample).first { $0.path == "old.txt" })
        #expect(file.hunks.first?.oldCount == 1)
        #expect(file.hunks.first?.lines.first?.text == "bye")
    }

    @Test func emptyInputYieldsNoFiles() {
        #expect(UnifiedDiffParser.parse("").isEmpty)
    }
}

struct IntraLineDiffTests {
    @Test func highlightsChangedTokensOnly() {
        let old = "invoice.items.reduce(0) { $0 + $1.price }"
        let new = "invoice.items.reduce(.zero) { $0 + $1.price }"
        let (oldRanges, newRanges) = IntraLineDiff.highlights(old: old, new: new)
        #expect(oldRanges.map { slice(old, $0) } == ["0"])
        #expect(newRanges.map { slice(new, $0) } == [".zero"])
    }

    @Test func completelyDifferentLinesGetNoHighlights() {
        let (old, new) = IntraLineDiff.highlights(old: "let a = 1", new: "return foo(bar)")
        #expect(old.isEmpty && new.isEmpty)
    }

    @Test func annotatesPairsInsideHunks() throws {
        let file = try #require(UnifiedDiffParser.parse(UnifiedDiffParserTests.sample).first)
        let removed = file.hunks[0].lines[1]
        #expect(!removed.highlights.isEmpty)
    }

    private func slice(_ text: String, _ range: Range<Int>) -> String {
        let utf16 = Array(text.utf16)[range]
        return String(utf16CodeUnits: Array(utf16), count: utf16.count)
    }
}

struct SideBySideRowTests {
    @Test func pairsRemovedAndAddedRuns() throws {
        let file = try #require(UnifiedDiffParser.parse(UnifiedDiffParserTests.sample).first)
        let rows = SideBySideRow.rows(for: file.hunks[0])
        #expect(rows.count == 7)
        #expect(rows[1].left?.kind == .removed && rows[1].right?.kind == .added)
        #expect(rows[2].left == nil && rows[2].right?.kind == .added)
        #expect(rows[0].left == rows[0].right)
    }
}

struct FileClassifierTests {
    @Test(arguments: [
        ("Sources/App/Main.swift", FileKind.source),
        ("Tests/AppTests/MainTests.swift", .test),
        ("src/components/button.test.tsx", .test),
        ("package-lock.json", .lockfile),
        ("Package.resolved", .lockfile),
        ("Api/Models.generated.cs", .generated),
        ("README.md", .docs),
        (".github/workflows/ci.yml", .config),
        ("App/Assets.xcassets/Icon.png", .asset),
        ("Sylvra.xcodeproj/project.pbxproj", .config),
    ])
    func classifies(path: String, expected: FileKind) {
        #expect(FileClassifier.classify(path) == expected)
    }
}
