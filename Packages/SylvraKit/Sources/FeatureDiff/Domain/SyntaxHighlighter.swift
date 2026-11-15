import Foundation

/// Lightweight, line-based syntax highlighting for diffs (keywords, types, strings, numbers, comments).
///
/// Works per line, so multi-line strings/comments are only approximated. Tree-sitter can replace this later
/// (see specs/architecture.md §7) behind the same interface.
public enum SyntaxHighlighter {
    public enum TokenKind: Sendable, Equatable {
        case keyword, type, string, number, comment, attribute
    }

    public struct Token: Sendable, Equatable {
        public let kind: TokenKind
        /// UTF-16 range in the line.
        public let range: Range<Int>
    }

    public enum Language: Sendable, Hashable {
        case swift, csharp, typescript, python, go, kotlin, rust, java, shell, json, yaml, plain

        private static let byExtension: [String: Language] = [
            "swift": .swift, "cs": .csharp, "ts": .typescript, "tsx": .typescript, "js": .typescript,
            "jsx": .typescript, "mjs": .typescript, "cjs": .typescript, "py": .python, "go": .go, "kt": .kotlin,
            "kts": .kotlin, "rs": .rust, "java": .java, "sh": .shell, "zsh": .shell, "bash": .shell, "json": .json,
            "yml": .yaml, "yaml": .yaml,
        ]

        public init(path: String) {
            self = Self.byExtension[(path as NSString).pathExtension.lowercased()] ?? .plain
        }

        var lineComment: String? {
            switch self {
            case .python, .shell, .yaml: "#"
            case .json, .plain: nil
            default: "//"
            }
        }

        var keywords: Set<String> {
            switch self {
            case .swift:
                [
                    "func", "let", "var", "if", "else", "guard", "return", "struct", "class", "enum", "protocol",
                    "extension",
                    "import", "for", "in", "while", "switch", "case", "default", "break", "continue", "throw", "throws",
                    "try", "await", "async", "public", "private", "fileprivate", "internal", "static", "final", "init",
                    "self", "Self", "nil", "true", "false", "some", "any", "where", "inout", "defer", "do", "catch",
                    "actor",
                    "nonisolated", "lazy", "weak", "override", "mutating", "typealias", "associatedtype",
                ]
            case .csharp, .java, .kotlin:
                [
                    "public", "private", "protected", "internal", "static", "class", "interface", "record", "struct",
                    "enum",
                    "void", "var", "val", "fun", "if", "else", "return", "new", "using", "namespace", "package",
                    "import",
                    "for", "foreach", "while", "switch", "case", "default", "break", "continue", "throw", "throws",
                    "try",
                    "catch", "finally", "async", "await", "this", "null", "true", "false", "readonly", "override",
                    "virtual", "abstract", "sealed", "const", "in", "is", "as", "when", "object", "data", "suspend",
                ]
            case .typescript:
                [
                    "function", "const", "let", "var", "if", "else", "return", "class", "interface", "type", "enum",
                    "import",
                    "export", "from", "for", "of", "in", "while", "switch", "case", "default", "break", "continue",
                    "throw",
                    "try", "catch", "finally", "async", "await", "new", "this", "null", "undefined", "true", "false",
                    "extends", "implements", "public", "private", "readonly", "static",
                ]
            case .python:
                [
                    "def", "class", "if", "elif", "else", "return", "import", "from", "as", "for", "in", "while", "try",
                    "except", "finally", "raise", "with", "lambda", "None", "True", "False", "and", "or", "not",
                    "async",
                    "await", "yield", "pass", "self",
                ]
            case .go:
                [
                    "func", "package", "import", "var", "const", "type", "struct", "interface", "if", "else", "return",
                    "for",
                    "range", "switch", "case", "default", "go", "defer", "chan", "map", "nil", "true", "false", "err",
                ]
            case .rust:
                [
                    "fn", "let", "mut", "if", "else", "return", "struct", "enum", "impl", "trait", "use", "mod", "pub",
                    "for", "in", "while", "loop", "match", "self", "Self", "true", "false", "async", "await", "move",
                ]
            case .shell:
                ["if", "then", "else", "fi", "for", "do", "done", "case", "esac", "function", "export", "local"]
            case .json, .yaml: ["true", "false", "null"]
            case .plain: []
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public static func tokens(_ line: String, language: Language) -> [Token] {
        guard language != .plain, !line.isEmpty else { return [] }
        let units = Array(line.utf16)
        var tokens: [Token] = []
        var index = 0
        let comment = language.lineComment.map { Array($0.utf16) }

        func isIdentifierStart(_ unit: UInt16) -> Bool {
            (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122) || unit == 95
        }
        func isIdentifierPart(_ unit: UInt16) -> Bool { isIdentifierStart(unit) || (unit >= 48 && unit <= 57) }

        while index < units.count {
            let unit = units[index]
            if let comment, units[index...].starts(with: comment) {
                tokens.append(Token(kind: .comment, range: index..<units.count))
                break
            }
            if unit == 34 || unit == 39 || unit == 96 {  // " ' `
                var end = index + 1
                while end < units.count, units[end] != unit {
                    end += units[end] == 92 ? 2 : 1  // skip escapes
                }
                end = min(end + 1, units.count)
                tokens.append(Token(kind: .string, range: index..<end))
                index = end
                continue
            }
            if unit >= 48 && unit <= 57, index == 0 || !isIdentifierPart(units[index - 1]) {
                var end = index + 1
                while end < units.count, isIdentifierPart(units[end]) || units[end] == 46 { end += 1 }
                tokens.append(Token(kind: .number, range: index..<end))
                index = end
                continue
            }
            if unit == 64, index + 1 < units.count, isIdentifierStart(units[index + 1]) {  // @attribute
                var end = index + 1
                while end < units.count, isIdentifierPart(units[end]) { end += 1 }
                tokens.append(Token(kind: .attribute, range: index..<end))
                index = end
                continue
            }
            if isIdentifierStart(unit) {
                var end = index + 1
                while end < units.count, isIdentifierPart(units[end]) { end += 1 }
                let word = String(utf16CodeUnits: Array(units[index..<end]), count: end - index)
                if language.keywords.contains(word) {
                    tokens.append(Token(kind: .keyword, range: index..<end))
                } else if unit >= 65 && unit <= 90, language != .json, language != .yaml {
                    tokens.append(Token(kind: .type, range: index..<end))
                }
                index = end
                continue
            }
            index += 1
        }
        return tokens
    }
}
