import FeatureAIReview
import Foundation

/// What `sylvra review` reviews and how: parsed from the command line, with Sylvra's AI review settings as
/// defaults.
public struct LocalReviewOptions: Equatable, Sendable {
    public enum Format: String, Sendable { case markdown, json }

    /// Repository to review (any folder inside it).
    public var directory: URL
    /// Branch or commit to compare with; `nil` finds the default branch (`origin/HEAD`, `main`, `master`).
    public var base: String?
    /// Only committed changes (`base...HEAD`); otherwise also uncommitted and untracked files.
    public var committedOnly = false
    public var title: String?
    public var description: String?
    public var format: Format = .markdown
    /// Writes the result to this file instead of standard output.
    public var output: URL?
    /// No progress on standard error.
    public var isQuiet = false
    /// Settings given on the command line (the rest comes from Sylvra's settings).
    public var models: [String]?
    public var effort: String?
    public var agents: Int?
    public var language: String?

    public init(directory: URL) {
        self.directory = directory
    }

    /// Sylvra's settings with the command line's overrides.
    public func settings(from defaults: ReviewSettings) -> ReviewSettings {
        var settings = defaults
        if let models, !models.isEmpty { settings.models = models }
        if let effort { settings.effort = effort }
        if let agents { settings.maxParallelAgents = agents }
        if let language { settings.agentLanguage = language }
        return settings
    }
}

/// The command line of the `sylvra` tool.
public enum LocalReviewCommand: Equatable, Sendable {
    case review(LocalReviewOptions)
    case help
    case version

    public enum ParseError: Error, Equatable, LocalizedError {
        case unknownCommand(String)
        case unknownOption(String)
        case missingValue(String)
        case invalidValue(option: String, value: String, expected: String)

        public var errorDescription: String? {
            switch self {
            case .unknownCommand(let command): "Unknown command '\(command)'. Try 'sylvra help'."
            case .unknownOption(let option): "Unknown option '\(option)'. Try 'sylvra help'."
            case .missingValue(let option): "\(option) needs a value."
            case .invalidValue(let option, let value, let expected):
                "\(option): '\(value)' is not valid (expected \(expected))."
            }
        }
    }

    /// Parses the arguments after the executable's name.
    public static func parse(_ arguments: [String], currentDirectory: URL) throws -> LocalReviewCommand {
        guard let command = arguments.first else { return .help }
        switch command {
        case "help", "-h", "--help": return .help
        case "version", "--version": return .version
        case "review": return .review(try parseReview(Array(arguments.dropFirst()), currentDirectory))
        default: throw ParseError.unknownCommand(command)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func parseReview(_ arguments: [String], _ currentDirectory: URL) throws -> LocalReviewOptions {
        var options = LocalReviewOptions(directory: currentDirectory)
        var remaining = arguments[...]
        func value(for option: String) throws -> String {
            guard let value = remaining.popFirst(), !value.hasPrefix("--") else {
                throw ParseError.missingValue(option)
            }
            return value
        }
        while let argument = remaining.popFirst() {
            // `--option=value` and `--option value`.
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            let option = parts[0]
            if parts.count == 2 { remaining.insert(parts[1], at: remaining.startIndex) }
            switch option {
            case "--base": options.base = try value(for: option)
            case "--committed": options.committedOnly = true
            case "--title": options.title = try value(for: option)
            case "--description": options.description = try value(for: option)
            case "--directory", "-C":
                options.directory =
                    URL(
                        fileURLWithPath: try value(for: option), relativeTo: currentDirectory
                    ).standardizedFileURL
            case "--output", "-o":
                options.output =
                    URL(fileURLWithPath: try value(for: option), relativeTo: currentDirectory)
                    .standardizedFileURL
            case "--format":
                let raw = try value(for: option)
                guard let format = LocalReviewOptions.Format(rawValue: raw) else {
                    throw ParseError.invalidValue(option: option, value: raw, expected: "markdown or json")
                }
                options.format = format
            case "--json": options.format = .json
            case "--quiet", "-q": options.isQuiet = true
            case "--models", "--model":
                let raw = try value(for: option)
                let models = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
                guard !models.isEmpty else {
                    throw ParseError.invalidValue(option: option, value: raw, expected: "e.g. opus,fable")
                }
                options.models = models
            case "--effort":
                let raw = try value(for: option).lowercased()
                guard AIReviewModel.efforts.contains(raw) else {
                    throw ParseError.invalidValue(
                        option: option, value: raw, expected: AIReviewModel.efforts.joined(separator: ", "))
                }
                options.effort = raw
            case "--agents":
                let raw = try value(for: option)
                guard let agents = Int(raw), (1...8).contains(agents) else {
                    throw ParseError.invalidValue(option: option, value: raw, expected: "1 to 8")
                }
                options.agents = agents
            case "--language": options.language = try value(for: option)
            default: throw ParseError.unknownOption(argument)
            }
        }
        return options
    }

    public static let usage = """
        sylvra — Sylvra's AI review for local changes, from the terminal or a coding agent

        USAGE
          sylvra review [options]     Review the current branch: commits since it left the base branch, plus
                                      uncommitted and new (untracked) files
          sylvra help | version

        WHAT TO REVIEW
          --base <ref>                Branch or commit to compare with (default: origin/HEAD, main or master)
          --committed                 Only committed changes (base...HEAD)
          -C, --directory <path>      Repository to review (default: the current folder)
          --title <text>              What the change is about (default: the branch name)
          --description <text>        More context for the reviewers (default: the commit messages)

        HOW (defaults: Sylvra's AI review settings)
          --models <a,b>              Models reviewing in parallel, merged into one result (e.g. opus,fable)
          --effort <level>            low, medium, high, xhigh or max
          --agents <n>                Parallel agents; large changes are split across them (1–8)
          --language <name>           Language of summaries and findings (e.g. German)

        OUTPUT
          --format markdown|json      Markdown for people and agents (default) or Sylvra's JSON result
          -o, --output <file>         Write the result to a file instead of standard output
          -q, --quiet                 No progress on standard error

        The agents only read the repository (Read, Grep, Glob); nothing is changed, committed or posted.
        A review takes a few minutes, longer with several models.
        """
}
