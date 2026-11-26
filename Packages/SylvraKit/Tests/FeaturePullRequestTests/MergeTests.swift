import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeaturePullRequest

/// Records what was sent to GitHub; refuses while `refusal` is set.
private final class RecordingMerger: PullRequestMerging, @unchecked Sendable {
    var calls: [String] = []
    var refusal: String?

    private func record(_ call: String) throws {
        if let refusal { throw GitHubError.graphQL([refusal]) }
        calls.append(call)
    }

    func merge(_ options: MergeOptions, method: MergeMethod, expectedHeadSHA: String) async throws {
        try record("merge \(method.rawValue) \(expectedHeadSHA)")
    }
    func enableAutoMerge(_ options: MergeOptions, method: MergeMethod) async throws {
        try record("auto \(method.rawValue)")
    }
    func disableAutoMerge(_ options: MergeOptions) async throws { try record("auto off") }
}

/// The demo pull request with a merge state and merge options.
private struct MergeableLoader: PullRequestDetailLoading {
    var state = "CLEAN"
    var options = MergeOptions(pullRequestNodeID: "PR_1", methods: [.merge, .squash], viewerCanMerge: true)

    func loadDetail(for id: PullRequestID) async throws -> PullRequestDetail {
        var detail = DemoPullRequestDetailLoader.detail(for: id)
        detail.mergeStatus = .derive(
            state: .open, mergeStateStatus: state, reviewDecision: state == "CLEAN" ? .approved : .reviewRequired,
            checks: [], isDraft: false)
        detail.mergeOptions = options
        return detail
    }
}

struct MergeOptionsTests {
    private func options(auto: Bool = false, on: MergeMethod? = nil, canMerge: Bool = true) -> MergeOptions {
        MergeOptions(
            pullRequestNodeID: "PR_1", methods: [.squash], viewerCanMerge: canMerge, viewerCanEnableAutoMerge: auto,
            autoMerge: on)
    }

    @Test func offersWhatThePullRequestAllows() {
        #expect(options().action(for: MergeStatus(kind: .ready)) == .merge)
        // Blocked by reviews or checks: only auto-merge, and only where the repository allows it.
        #expect(options().action(for: MergeStatus(kind: .blocked)) == nil)
        #expect(options(auto: true).action(for: MergeStatus(kind: .blocked)) == .enableAutoMerge)
        #expect(options(auto: true, on: .squash).action(for: MergeStatus(kind: .blocked)) == .disableAutoMerge)
        #expect(options(auto: true).action(for: MergeStatus(kind: .conflicts)) == nil)
        #expect(options().action(for: MergeStatus(kind: .merged)) == nil)
        // No write access: no button.
        #expect(options(canMerge: false).action(for: MergeStatus(kind: .ready)) == nil)
    }

    @Test func readsTheRepositorysMethodsWithTheViewersDefaultFirst() throws {
        let json = PullRequestDetailMappingTests.json
            .replacingOccurrences(
                of: #""number": 5,"#, with: #""id": "PR_5", "viewerCanEnableAutoMerge": true, "number": 5,"#
            )
            .replacingOccurrences(
                of: #""repository": {"name": "r", "owner": {"login": "o"}}"#,
                with: #"""
                    "repository": {"name": "r", "owner": {"login": "o"}, "viewerPermission": "WRITE",
                      "viewerDefaultMergeMethod": "SQUASH", "mergeCommitAllowed": true, "squashMergeAllowed": true,
                      "rebaseMergeAllowed": false}
                    """#)
        let node = try #require(
            try GitHubJSON.decoder.decode(DetailResponse.self, from: Data(json.utf8)).repository?.pullRequest)
        let options = try #require(node.mergeOptions)
        #expect(options.methods == [.squash, .merge])
        #expect(options.viewerCanMerge && options.viewerCanEnableAutoMerge && options.autoMerge == nil)
        #expect(options.pullRequestNodeID == "PR_5")
    }
}

@MainActor
struct MergeModelTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    private func defaults() -> UserDefaults {
        let name = "merge-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func mergesOnlyAfterConfirmingAndRemembersTheMethod() async throws {
        let merger = RecordingMerger()
        let defaults = defaults()
        let model = PullRequestScreenModel(loader: MergeableLoader(), merger: merger, defaults: defaults)
        await model.load(id)
        #expect(model.mergeAction == .merge)
        model.startMerge()
        #expect(model.isMergeSheetPresented && merger.calls.isEmpty)
        model.mergeMethod = .squash
        await model.confirmMerge()
        let head = try #require(model.detail?.headSHA)
        #expect(merger.calls == ["merge SQUASH \(head)"])
        #expect(!model.isMergeSheetPresented)

        // The next merge in this repository starts with the method used last.
        model.startMerge()
        #expect(model.mergeMethod == .squash)
    }

    /// GitHub's refusal stays in the sheet (an alert next to a sheet opens a second window).
    @Test func aRefusalIsShownInTheSheet() async {
        let merger = RecordingMerger()
        merger.refusal = "Head branch was modified"
        let model = PullRequestScreenModel(loader: MergeableLoader(), merger: merger)
        await model.load(id)
        model.startMerge()
        await model.confirmMerge()
        #expect(model.isMergeSheetPresented)
        #expect(model.mergeError?.contains("Head branch was modified") == true)
    }

    @Test func blockedPullRequestsOfferAutoMerge() async {
        let merger = RecordingMerger()
        var loader = MergeableLoader(state: "BLOCKED")
        loader.options.viewerCanEnableAutoMerge = true
        let model = PullRequestScreenModel(loader: loader, merger: merger)
        await model.load(id)
        #expect(model.mergeAction == .enableAutoMerge)
        model.startMerge()
        await model.confirmMerge()
        #expect(merger.calls == ["auto MERGE"])
    }

    @Test func noButtonWithoutAMerger() async {
        let model = PullRequestScreenModel(loader: MergeableLoader())
        await model.load(id)
        #expect(model.mergeAction == nil)
    }
}
