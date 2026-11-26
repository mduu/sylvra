import Foundation

/// What the user writes to the Sylvra project: becomes an issue in its GitHub repository.
public struct FeedbackDraft: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case bug, idea, question

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .bug: String(localized: "Problem")
            case .idea: String(localized: "Idea")
            case .question: String(localized: "Question")
            }
        }

        /// The label on the issue.
        var label: String {
            switch self {
            case .bug: "bug"
            case .idea: "enhancement"
            case .question: "question"
            }
        }
    }

    public var kind: Kind = .bug
    public var title = ""
    public var details = ""
    /// Attach the picture of Sylvra's window.
    public var includesScreenshot = false
    /// Add Sylvra's version and the system it runs on.
    public var includesSystemInfo = true

    public init() {}

    /// A title is all an issue needs.
    public var canSend: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// The version of Sylvra and what it runs on — nothing about the user's repositories or pull requests.
public struct SystemInfo: Equatable, Sendable {
    public var appVersion: String
    public var build: String
    public var macOS: String
    /// Hardware model, e.g. "Mac16,7".
    public var model: String
    public var architecture: String
    public var language: String
    /// Further lines the app knows, e.g. ("Claude Code", "2.1.0"), ("Layout", "wide").
    public var extras: [Extra]

    public struct Extra: Equatable, Sendable {
        public let name: String
        public let value: String

        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    public init(
        appVersion: String, build: String, macOS: String, model: String, architecture: String, language: String,
        extras: [Extra] = []
    ) {
        self.appVersion = appVersion
        self.build = build
        self.macOS = macOS
        self.model = model
        self.architecture = architecture
        self.language = language
        self.extras = extras
    }

    /// As shown to the user before sending and as written into the issue.
    public var lines: [String] {
        [
            "Sylvra \(appVersion) (\(build))", "macOS \(macOS)", "\(model) · \(architecture)", "Language: \(language)",
        ] + extras.map { "\($0.name): \($0.value)" }
    }
}

/// The issue as it is sent.
public struct FeedbackIssue: Equatable, Sendable {
    public var title: String
    public var body: String
    public var labels: [String]

    /// Builds the issue from the draft. `screenshot`: Markdown for the uploaded picture, or a note that it
    /// follows; `nil`: none.
    public static func make(from draft: FeedbackDraft, info: SystemInfo?, screenshot: String? = nil) -> FeedbackIssue {
        var sections: [String] = []
        let details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty { sections.append(details) }
        if let screenshot { sections.append("### Screenshot\n\n\(screenshot)") }
        if draft.includesSystemInfo, let info {
            sections.append("### Environment\n\n" + info.lines.map { "- \($0)" }.joined(separator: "\n"))
        }
        sections.append("_Sent from Sylvra (Help → Send Feedback)._")
        return FeedbackIssue(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: sections.joined(separator: "\n\n"), labels: ["feedback", draft.kind.label])
    }
}

/// What came of sending.
public struct FeedbackReceipt: Equatable, Sendable {
    public let number: Int
    public let url: URL?
    /// A screenshot was asked for but could not be uploaded (no write access to the repository).
    public var screenshotMissing = false

    public init(number: Int, url: URL?, screenshotMissing: Bool = false) {
        self.number = number
        self.url = url
        self.screenshotMissing = screenshotMissing
    }
}
