import Foundation
import Testing

@testable import FeatureAIReview

/// The Claude Code skill points at the `sylvra` tool of this Sylvra and tells the agent how to use the review.
struct ClaudeSkillInstallerTests {
    private func installer(tool: String = "/Applications/Sylvra.app/Contents/Helpers/sylvra", in skills: URL)
        -> ClaudeSkillInstaller
    {
        ClaudeSkillInstaller(commandLineTool: URL(fileURLWithPath: tool), skillsDirectory: skills)
    }

    private func skillsDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "Skills-\(UUID().uuidString)")
    }

    @Test func installsReinstallsAndRemoves() throws {
        let skills = skillsDirectory()
        let installer = installer(in: skills)
        #expect(installer.status == .notInstalled)
        try installer.install()
        #expect(installer.status == .installed)
        #expect(installer.skillFile.path.hasSuffix("sylvra-review/SKILL.md"))
        // Another copy of Sylvra (moved app): the skill still points at the old one until reinstalled.
        let moved = self.installer(tool: "/Users/me/Apps/Sylvra.app/Contents/Helpers/sylvra", in: skills)
        #expect(moved.status == .outdated)
        try moved.install()
        #expect(moved.status == .installed)
        try moved.uninstall()
        #expect(moved.status == .notInstalled)
    }

    @Test func theSkillRunsTheToolInTheBackgroundAndVerifiesFindings() {
        let skill = ClaudeSkillInstaller.skill(commandLineTool: "/Applications/Sylvra.app/Contents/Helpers/sylvra")
        #expect(skill.hasPrefix("---\nname: sylvra-review\ndescription: "))
        #expect(skill.contains("\"/Applications/Sylvra.app/Contents/Helpers/sylvra\" review -o "))
        #expect(skill.contains("## Show the progress"))
        #expect(skill.contains("--hint \"thread safety of the cache\""))
        #expect(skill.contains("run_in_background"))
        #expect(skill.contains("Check each one against the code before you act on it"))
    }
}
