import Foundation
import Testing

@testable import FeatureCustomTools

struct CommandTemplateTests {
    private let context = ToolContext(
        worktree: URL(fileURLWithPath: "/tmp/review worktree"), file: "Sources/App/Main.swift", prNumber: 1234,
        headSHA: "abc123", baseSHA: "def456")

    @Test func substitutesAllPlaceholders() throws {
        let command = try CommandTemplate.expand(
            "tool {file} {folder} {repoRoot} {worktree} {prNumber} {headSHA} {baseSHA}", context: context)
        #expect(
            command
                == "tool '/tmp/review worktree/Sources/App/Main.swift' '/tmp/review worktree/Sources/App' "
                + "'/tmp/review worktree' '/tmp/review worktree' '1234' 'abc123' 'def456'")
    }

    @Test func escapesQuotesAndShellSyntax() throws {
        let hostile = ToolContext(worktree: URL(fileURLWithPath: "/tmp/x"), file: "a'; rm -rf ~; echo '$(id).swift")
        let command = try CommandTemplate.expand("cat {file}", context: hostile)
        #expect(command == #"cat '/tmp/x/a'\''; rm -rf ~; echo '\''$(id).swift'"#)
    }

    @Test func quotesEmptyValues() {
        #expect(ShellEscaping.quote("") == "''")
        #expect(ShellEscaping.quote("it's") == #"'it'\''s'"#)
    }

    @Test func leavesUnknownBracesAlone() throws {
        let command = try CommandTemplate.expand("echo {a,b} {prNumber} {", context: context)
        #expect(command == "echo {a,b} '1234' {")
    }

    @Test func folderRootIsTheWorktree() throws {
        let root = ToolContext(worktree: URL(fileURLWithPath: "/tmp/w"), folder: "")
        #expect(try CommandTemplate.expand("ls {folder}", context: root) == "ls '/tmp/w'")
    }

    @Test func failsWhenAValueIsMissing() {
        let empty = ToolContext(prNumber: 1)
        #expect(throws: CommandTemplate.ExpansionError.missingValue("{file}")) {
            try CommandTemplate.expand("open {file}", context: empty)
        }
        #expect(throws: CommandTemplate.ExpansionError.missingValue("{headSHA}")) {
            try CommandTemplate.expand("git show {headSHA}", context: ToolContext(headSHA: ""))
        }
    }

    @Test func listsUsedPlaceholders() {
        #expect(CommandTemplate.placeholders(in: "x {file} {baseSHA}") == [.file, .baseSHA])
    }
}

@MainActor
struct CustomToolStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "sylvra-tools-\(UUID().uuidString)")!
    }

    @Test func startsWithExamples() {
        let store = CustomToolStore(defaults: makeDefaults())
        #expect(store.tools == CustomTool.examples)
        #expect(store.tools(for: .pullRequest).count == 2)
        #expect(store.tools(for: .file).isEmpty)
    }

    @Test func persistsAddEditDeleteAndMove() {
        let defaults = makeDefaults()
        let store = CustomToolStore(defaults: defaults)
        var tool = CustomTool(name: "Lint", scope: .file, command: "swiftlint lint {file}")
        store.save(tool)
        tool.name = "Lint file"
        store.save(tool)
        store.delete(CustomTool.examples[0].id)
        store.move(fromOffsets: [1], toOffset: 0)

        let reloaded = CustomToolStore(defaults: defaults)
        #expect(reloaded.tools.map(\.name) == ["Lint file", "Open in Fork"])
        #expect(reloaded.tools(for: .file) == [tool])
    }

    @Test func keepsAnEmptyList() {
        let defaults = makeDefaults()
        let store = CustomToolStore(defaults: defaults)
        store.tools.forEach { store.delete($0.id) }
        #expect(CustomToolStore(defaults: defaults).tools.isEmpty)
    }

    @Test func fallsBackToExamplesOnCorruptData() {
        let defaults = makeDefaults()
        defaults.set(Data("nope".utf8), forKey: CustomToolStore.storageKey)
        #expect(CustomToolStore(defaults: defaults).tools == CustomTool.examples)
    }
}
