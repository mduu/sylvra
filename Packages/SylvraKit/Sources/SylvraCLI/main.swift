import Foundation
import LocalReview

/// `sylvra` — Sylvra's AI review for local changes (see `LocalReviewCommand.usage`).
/// Exit codes: 0 reviewed (findings or not), 1 the review failed, 2 wrong usage.

/// Progress and errors go to standard error, the result to standard output (or `--output`).
@MainActor
func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let command: LocalReviewCommand
do {
    command = try LocalReviewCommand.parse(Array(CommandLine.arguments.dropFirst()), currentDirectory: currentDirectory)
} catch {
    printError("sylvra: \(error.localizedDescription)")
    exit(2)
}

switch command {
case .help:
    print(LocalReviewCommand.usage)
case .version:
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    print("sylvra \(version ?? LocalReviewVersion.fromAppBundle() ?? "dev")")
case .review(let options):
    do {
        let report = try await LocalReviewRunner().run(options) { line in
            if !options.isQuiet { printError(line) }
        }
        let text = try LocalReviewOutput.render(report, format: options.format)
        if let output = options.output {
            try Data(text.utf8).write(to: output, options: .atomic)
            if !options.isQuiet { printError("Wrote \(output.path)") }
        } else {
            print(text, terminator: "")
        }
    } catch {
        printError("sylvra: \(error.localizedDescription)")
        exit(1)
    }
}
