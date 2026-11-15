import Testing

@testable import FeatureDiff

struct SyntaxHighlighterTests {
    private func kinds(_ line: String, _ language: SyntaxHighlighter.Language) -> [String: SyntaxHighlighter.TokenKind]
    {
        let units = Array(line.utf16)
        var result: [String: SyntaxHighlighter.TokenKind] = [:]
        for token in SyntaxHighlighter.tokens(line, language: language) {
            let slice = Array(units[token.range])
            result[String(utf16CodeUnits: slice, count: slice.count)] = token.kind
        }
        return result
    }

    @Test func swiftLine() {
        let tokens = kinds(#"let total: Decimal = 42 // "sum""#, .swift)
        #expect(tokens["let"] == .keyword)
        #expect(tokens["Decimal"] == .type)
        #expect(tokens["42"] == .number)
        #expect(tokens[#"// "sum""#] == .comment)
    }

    @Test func stringsWithEscapes() {
        let tokens = kinds(#"print("a \"b\" c")"#, .swift)
        #expect(tokens[#""a \"b\" c""#] == .string)
    }

    @Test func attributesAndPythonComments() {
        #expect(kinds("@MainActor final class A {}", .swift)["@MainActor"] == .attribute)
        #expect(kinds("x = 1  # note", .python)["# note"] == .comment)
    }

    @Test func languageFromPath() {
        #expect(SyntaxHighlighter.Language(path: "A/B.cs") == .csharp)
        #expect(SyntaxHighlighter.Language(path: "README.md") == .plain)
        #expect(SyntaxHighlighter.tokens("let x = 1", language: .plain).isEmpty)
    }
}
