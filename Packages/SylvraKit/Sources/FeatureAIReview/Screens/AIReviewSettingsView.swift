import AppKit
import DesignSystem
import SwiftUI

/// Default AI review settings (settings window pane), and using the review from Claude Code.
public struct AIReviewSettingsView: View {
    @Bindable private var model: AIReviewModel
    /// The `sylvra` command line tool in the app bundle (`nil`: not there, e.g. a development build).
    private let commandLineTool: URL?
    @State private var skillStatus: ClaudeSkillInstaller.Status = .notInstalled
    @State private var skillError: String?

    public init(model: AIReviewModel, commandLineTool: URL? = nil) {
        self.model = model
        self.commandLineTool = commandLineTool
    }

    public var body: some View {
        Form {
            Section("Agent") {
                LabeledContent("Provider", value: model.providerName)
                LabeledContent("Installed version", value: model.agentVersion ?? String(localized: "not found"))
            }
            Section("Defaults (can be overridden per pull request)") {
                ForEach(AIReviewModel.availableModels, id: \.self) { name in
                    Toggle(
                        name.capitalized,
                        isOn: Binding(
                            get: { model.defaultSettings.models.contains(name) },
                            set: { isOn in
                                if isOn {
                                    model.defaultSettings.models.append(name)
                                } else if model.defaultSettings.models.count > 1 {
                                    model.defaultSettings.models.removeAll { $0 == name }
                                }
                            }))
                }
                Picker("Effort", selection: $model.defaultSettings.effort) {
                    ForEach(AIReviewModel.efforts, id: \.self) { Text($0.capitalized).tag($0) }
                }
                Stepper(
                    "Parallel agents: \(model.defaultSettings.maxParallelAgents)",
                    value: $model.defaultSettings.maxParallelAgents, in: 1...8)
                Stepper(
                    "Split PRs above \(model.defaultSettings.shardThreshold) changed lines",
                    value: $model.defaultSettings.shardThreshold, in: 100...2000, step: 100)
                Picker("Agent language", selection: $model.defaultSettings.agentLanguage) {
                    ForEach(Self.languages(including: model.defaultSettings.agentLanguage), id: \.self) {
                        Text($0).tag($0)
                    }
                }
            }
            claudeCodeSection
        }
        .formStyle(.grouped)
        .task { await model.detectAgent() }
        .onAppear { refreshSkillStatus() }
    }

    /// The same review for local changes: `sylvra review` in a terminal, or Claude Code through the skill.
    @ViewBuilder private var claudeCodeSection: some View {
        Section {
            if let tool = commandLineTool {
                LabeledContent("Command line tool") {
                    HStack(spacing: 4) {
                        Text(verbatim: tool.path).font(.caption.monospaced()).textSelection(.enabled)
                            .lineLimit(1).truncationMode(.middle)
                        CopyButton("Copy the path") { tool.path }
                    }
                }
                LabeledContent("Claude Code skill") {
                    HStack(spacing: 8) {
                        Text(skillStatusText).foregroundStyle(.secondary)
                        Button(installTitle) { installSkill(tool) }
                        if skillStatus != .notInstalled {
                            Button("Remove") { removeSkill(tool) }
                        }
                    }
                }
                if let skillError {
                    Text(skillError).font(.caption).foregroundStyle(.red)
                }
            } else {
                Text("The command line tool ships with release builds of Sylvra (Contents/Helpers/sylvra).")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Use from Claude Code")
        } footer: {
            Text(
                "Reviews the current branch's local changes — commits, uncommitted and new files — with the "
                    + "settings above: `sylvra review` in a terminal, or ask Claude Code for a Sylvra review once "
                    + "the skill is installed (~/.claude/skills/sylvra-review). The agents only read the repository."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var installTitle: LocalizedStringKey {
        switch skillStatus {
        case .notInstalled: "Install"
        case .installed: "Reinstall"
        case .outdated: "Update"
        }
    }

    private var skillStatusText: String {
        switch skillStatus {
        case .notInstalled: String(localized: "Not installed")
        case .installed: String(localized: "Installed")
        case .outdated: String(localized: "Out of date: click Update")
        }
    }

    private func refreshSkillStatus() {
        guard let commandLineTool else { return }
        skillStatus = ClaudeSkillInstaller(commandLineTool: commandLineTool).status
    }

    private func installSkill(_ tool: URL) {
        do {
            try ClaudeSkillInstaller(commandLineTool: tool).install()
            skillError = nil
        } catch {
            skillError = String(localized: "Couldn't install the skill: \(error.localizedDescription)")
        }
        refreshSkillStatus()
    }

    private func removeSkill(_ tool: URL) {
        do {
            try ClaudeSkillInstaller(commandLineTool: tool).uninstall()
            skillError = nil
        } catch {
            skillError = String(localized: "Couldn't remove the skill: \(error.localizedDescription)")
        }
        refreshSkillStatus()
    }

    private static func languages(including current: String) -> [String] {
        let base = ["English", "German", "French", "Italian", "Spanish"]
        return base.contains(current) ? base : [current] + base
    }
}
