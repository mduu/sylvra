import FeatureInbox
import Foundation
import Platform

/// Composition root: creates the services and feature models of the app.
///
/// Launch with `--demo` to use fixture data (screenshots, demos) instead of GitHub.
@MainActor
final class AppEnvironment {
    let isDemo: Bool
    let gitHub: GitHubClient
    let inbox: InboxScreenModel

    init(arguments: [String] = CommandLine.arguments) {
        isDemo = arguments.contains("--demo")
        gitHub = GitHubClient(tokenProvider: GitHubCLITokenProvider())
        let inboxLoader: any InboxLoading = isDemo ? DemoInboxLoader() : GitHubInboxLoader(client: gitHub)
        inbox = InboxScreenModel(loader: inboxLoader)
    }
}
