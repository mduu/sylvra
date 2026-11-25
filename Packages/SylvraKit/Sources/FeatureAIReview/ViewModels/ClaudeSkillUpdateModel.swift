import CryptoKit
import Foundation
import Observation

/// After installing a new Sylvra whose Claude Code skill changed: asks once whether to update the installed skill.
/// Asks again only when a later release brings another skill; nothing happens when the skill isn't installed.
@MainActor
@Observable
public final class ClaudeSkillUpdateModel {
    /// The question is showing.
    public var isAsking = false
    public private(set) var failure: String?

    private let installer: ClaudeSkillInstaller?
    private let defaults: UserDefaults
    static let askedKey = "claudeSkill.askedForUpdate"

    /// `installer` is `nil` without the command line tool in the bundle (development builds) or in demo mode.
    public init(installer: ClaudeSkillInstaller?, defaults: UserDefaults = .standard) {
        self.installer = installer
        self.defaults = defaults
    }

    /// Checks the installed skill (off the main actor) and asks if it's out of date and not asked for this skill.
    public func checkAtLaunch() async {
        guard let installer else { return }
        let fingerprint = Self.fingerprint(of: installer)
        guard defaults.string(forKey: Self.askedKey) != fingerprint else { return }
        let status = await Task.detached { installer.status }.value
        guard status == .outdated else { return }
        defaults.set(fingerprint, forKey: Self.askedKey)
        isAsking = true
    }

    public func update() async {
        guard let installer else { return }
        isAsking = false
        do {
            try await Task.detached { try installer.install() }.value
            failure = nil
        } catch {
            failure = String(localized: "Couldn't update the Claude Code skill: \(error.localizedDescription)")
        }
    }

    public func dismissFailure() { failure = nil }

    /// Identifies the skill this Sylvra would install (text and tool path).
    static func fingerprint(of installer: ClaudeSkillInstaller) -> String {
        let skill = ClaudeSkillInstaller.skill(commandLineTool: installer.commandLineTool.path)
        return SHA256.hash(data: Data(skill.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
