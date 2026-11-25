import SwiftUI

/// Asks once after launch whether to update the Claude Code skill (container; see `ClaudeSkillUpdateModel`).
struct ClaudeSkillUpdatePrompt: ViewModifier {
    @Bindable var model: ClaudeSkillUpdateModel

    func body(content: Content) -> some View {
        content
            .task { await model.checkAtLaunch() }
            .alert("Update the Claude Code skill?", isPresented: $model.isAsking) {
                Button("Update") { Task { await model.update() } }
                    .keyboardShortcut(.defaultAction)
                Button("Later", role: .cancel) {}
            } message: {
                Text(
                    """
                    This version of Sylvra comes with a newer sylvra-review skill for Claude Code. Update it now? \
                    Later: Settings → AI → Use from Claude Code.
                    """)
            }
            .alert(
                "Skill not updated",
                isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.dismissFailure() } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.failure ?? "")
            }
    }
}

extension View {
    /// Asks once after launch whether to update an out-of-date Claude Code skill.
    public func claudeSkillUpdatePrompt(_ model: ClaudeSkillUpdateModel) -> some View {
        modifier(ClaudeSkillUpdatePrompt(model: model))
    }
}
