import Foundation
import SylvraCore
import Testing

@testable import FeaturePullRequest

struct NewActivityTests {
    let me = UserRef(login: "mduu")
    let lena = UserRef(login: "lkeller")
    let bot = UserRef(login: "renovate[bot]")
    let since = Date(timeIntervalSince1970: 1_000_000)

    func at(_ offset: TimeInterval) -> Date { since.addingTimeInterval(offset) }

    func detail() -> PullRequestDetail {
        let id = PullRequestID(owner: "acme", repository: "billing", number: 1)
        var detail = DemoPullRequestDetailLoader.detail(for: id)
        detail.commits = [
            Commit(sha: "old", subject: "Before", author: lena, authoredAt: at(-60)),
            Commit(sha: "new1", subject: "Fix rounding", author: lena, authoredAt: at(60)),
            Commit(sha: "new2", subject: "Add test", author: lena, authoredAt: at(120)),
        ]
        detail.discussion = [
            DiscussionItem(
                id: "t1", place: .code(path: "Sources/A.swift", line: 4, isResolved: false), author: me,
                body: "Why?", date: at(-10),
                replies: [
                    .init(author: lena, body: "> Why?\n\nBecause   of VAT.", date: at(30)),
                    .init(author: me, body: "Ok", date: at(40)),
                ]),
            DiscussionItem(id: "c1", place: .conversation, author: bot, body: "Bump", date: at(50)),
            DiscussionItem(id: "c2", place: .conversation, author: lena, body: "Old", date: at(-30)),
            DiscussionItem(id: "r1", place: .review, author: lena, body: "Looks good", date: at(90)),
        ]
        detail.involvement = Involvement(
            login: "MDUU", ownCommentCount: 2, lastOwnCommentAt: since, othersLastActivityAt: at(120))
        return detail
    }

    @Test func listsCommitsAndCommentsByOthersSinceTheLastComment() throws {
        let activity = try #require(detail().newActivity)
        #expect(activity.commits.map(\.sha) == ["new2", "new1"])
        #expect(activity.comments.map(\.id) == ["r1", "t1#0"])
        #expect(activity.comments.last?.isReply == true)
        #expect(activity.comments.last?.excerpt == "Because of VAT.")
    }

    @Test func nothingWhenTheViewerActedLast() {
        var waiting = detail()
        waiting.involvement.othersLastActivityAt = at(-1)
        #expect(waiting.newActivity == nil)
    }

    @Test func excerptIsShortened() {
        #expect(NewActivity.excerpt(String(repeating: "a ", count: 200), limit: 20).count == 20)
    }

    @Test func describesWhereACommentWasMade() {
        let reply = NewActivity.Comment(
            id: "x", author: lena, place: .code(path: "Sources/A.swift", line: 4, isResolved: false), isReply: true,
            excerpt: "", date: since, url: nil)
        #expect(NewActivityView.placeText(reply) == "replied on A.swift:4")
        #expect(NewActivityView.count(3, "commit") == "3 new commits")
        #expect(NewActivityView.count(1, "comment") == "1 new comment")
    }
}
