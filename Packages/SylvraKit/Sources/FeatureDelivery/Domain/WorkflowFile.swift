import Foundation

/// The jobs of a GitHub Actions workflow file with what each waits for (`needs:`) — just enough of the YAML to
/// draw the workflow as a graph. Anything it does not understand leaves the job without dependencies.
public struct WorkflowFile: Equatable, Sendable {
    public struct Job: Equatable, Sendable {
        /// The key under `jobs:`.
        public let key: String
        /// Its `name:` (what the check run is called; `nil`: the key is the name).
        public var name: String?
        public var needs: [String]
    }

    public let jobs: [Job]

    public init(jobs: [Job]) {
        self.jobs = jobs
    }

    public init(yaml: String) {
        var reader = Reader()
        for line in yaml.components(separatedBy: .newlines) { reader.read(line) }
        jobs = reader.finish()
    }

    /// The job a check run belongs to: by its name, a matrix job's name with its values ("build (ubuntu)"), or
    /// a reusable workflow's jobs ("deploy / migrate").
    public func job(forCheckRun name: String) -> Job? {
        jobs.first { ($0.name ?? $0.key) == name }
            ?? jobs.first { job in
                let base = job.name ?? job.key
                return name.hasPrefix(base + " (") || name.hasPrefix(base + " / ")
            }
            ?? jobs.first { $0.key == name }
    }

    /// Reads the file line by line: the keys under `jobs:` and, one level deeper, their `name:` and `needs:`.
    private struct Reader {
        var jobs: [Job] = []
        var inJobs = false
        var jobIndent: Int?
        /// How deep a job's own properties sit (the first line below its key decides).
        var propertyIndent: Int?
        var current: Job?
        var collectsNeeds = false

        mutating func read(_ raw: String) {
            let line = Self.withoutComment(raw)
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            let indent = line.prefix { $0 == " " }.count
            if indent == 0 {
                flush()
                inJobs = text == "jobs:"
                jobIndent = nil
                return
            }
            guard inJobs else { return }
            if jobIndent == nil { jobIndent = indent }
            if indent == jobIndent, text.hasSuffix(":") {
                flush()
                current = Job(key: Self.scalar(String(text.dropLast())), name: nil, needs: [])
                propertyIndent = nil
                collectsNeeds = false
                return
            }
            guard current != nil, let jobIndent, indent > jobIndent else { return }
            if propertyIndent == nil { propertyIndent = indent }
            if collectsNeeds, text.hasPrefix("- ") {
                current?.needs.append(Self.scalar(String(text.dropFirst(2))))
            } else if indent == propertyIndent {
                readProperty(text)
            }
        }

        private mutating func readProperty(_ text: String) {
            collectsNeeds = false
            if let value = Self.value(of: "name", in: text) {
                current?.name = Self.scalar(value)
            } else if let value = Self.value(of: "needs", in: text) {
                if value.isEmpty {
                    collectsNeeds = true
                } else if value.hasPrefix("[") {
                    current?.needs = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(
                        separator: ","
                    )
                    .map { Self.scalar(String($0)) }.filter { !$0.isEmpty }
                } else {
                    current?.needs = [Self.scalar(value)]
                }
            }
        }

        private mutating func flush() {
            if let current { jobs.append(current) }
            current = nil
        }

        mutating func finish() -> [Job] {
            flush()
            return jobs
        }

        private static func value(of key: String, in text: String) -> String? {
            guard text.hasPrefix(key + ":") else { return nil }
            return text.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        }

        private static func scalar(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }

        private static func withoutComment(_ line: String) -> String {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { return "" }
            guard let hash = line.range(of: " #") else { return line }
            return String(line[..<hash.lowerBound])
        }
    }
}
