import Foundation
import Testing

@testable import FeatureAIReview

@MainActor
struct ClaudeSkillUpdateTests {
    private let skills = FileManager.default.temporaryDirectory.appending(path: "Skills-\(UUID().uuidString)")
    private let defaults = UserDefaults(suiteName: "skill-update-\(UUID().uuidString)") ?? .standard

    private func installer(_ tool: String) -> ClaudeSkillInstaller {
        ClaudeSkillInstaller(commandLineTool: URL(fileURLWithPath: tool), skillsDirectory: skills)
    }

    @Test func asksOnceForAnOutdatedSkillAndUpdatesIt() async throws {
        try installer("/Old/Sylvra.app/Contents/Helpers/sylvra").install()
        let current = installer("/Applications/Sylvra.app/Contents/Helpers/sylvra")
        let model = ClaudeSkillUpdateModel(installer: current, defaults: defaults)
        await model.checkAtLaunch()
        #expect(model.isAsking)
        await model.update()
        #expect(!model.isAsking)
        #expect(current.status == .installed)
        #expect(model.failure == nil)
    }

    @Test func laterMeansNotAgainForTheSameSkill() async throws {
        try installer("/Old/Sylvra.app/Contents/Helpers/sylvra").install()
        let current = installer("/Applications/Sylvra.app/Contents/Helpers/sylvra")
        let first = ClaudeSkillUpdateModel(installer: current, defaults: defaults)
        await first.checkAtLaunch()
        #expect(first.isAsking)
        first.isAsking = false  // Later
        let nextLaunch = ClaudeSkillUpdateModel(installer: current, defaults: defaults)
        await nextLaunch.checkAtLaunch()
        #expect(!nextLaunch.isAsking)
        #expect(current.status == .outdated)
        // Another skill (a later release, or the app moved): asked again.
        let moved = ClaudeSkillUpdateModel(
            installer: installer("/Users/me/Apps/Sylvra.app/Contents/Helpers/sylvra"), defaults: defaults)
        await moved.checkAtLaunch()
        #expect(moved.isAsking)
    }

    @Test func doesNotAskWithoutAnInstalledOrWithACurrentSkill() async throws {
        let current = installer("/Applications/Sylvra.app/Contents/Helpers/sylvra")
        let notInstalled = ClaudeSkillUpdateModel(installer: current, defaults: defaults)
        await notInstalled.checkAtLaunch()
        #expect(!notInstalled.isAsking)
        try current.install()
        let upToDate = ClaudeSkillUpdateModel(installer: current, defaults: defaults)
        await upToDate.checkAtLaunch()
        #expect(!upToDate.isAsking)
        let development = ClaudeSkillUpdateModel(installer: nil, defaults: defaults)
        await development.checkAtLaunch()
        #expect(!development.isAsking)
    }
}
