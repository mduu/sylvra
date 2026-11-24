import DesignSystem
import SwiftUI
import SylvraCore

/// "✦ ▾" toolbar button on the AI gradient: one click runs, the menu sets models and effort per PR (container).
public struct AIReviewToolbarPanel: View {
    private let model: AIReviewModel
    private let pullRequest: PullRequestSummary?
    private let pullRequestBody: String

    public init(model: AIReviewModel, pullRequest: PullRequestSummary?, pullRequestBody: String) {
        self.model = model
        self.pullRequest = pullRequest
        self.pullRequestBody = pullRequestBody
    }

    public var body: some View {
        // Its own gradient capsule instead of the toolbar glass: the AI review is the most important action.
        // Constant size: toolbar items that change width while the window is full can make AppKit's constraint
        // pass loop. Progress is shown by the pulse and the inspector.
        HStack(spacing: 0) {
            Button(action: run) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .symbolEffect(.pulse, isActive: isRunning)
                    .frame(width: 44, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .accessibilityLabel("AI Review")
            Rectangle()
                .fill(.white.opacity(0.45))
                .frame(width: 1, height: 16)
            Menu {
                settingsMenu
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 32, height: 34)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("AI review settings")
        }
        .foregroundStyle(.white)
        .background(AIAccent.prominentFill, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
        .help(
            model.isOutdated(pullRequest?.id)
                ? "New commits since the last AI review — run it again (⌘⇧R)"
                : "Run an AI review with the local agent (⌘⇧R)"
        )
    }

    /// Models, effort and parallel agents for this pull request.
    @ViewBuilder private var settingsMenu: some View {
        if let id = pullRequest?.id {
            let settings = model.settings(for: id)
            Section("Models") {
                ForEach(AIReviewModel.availableModels, id: \.self) { name in
                    Toggle(
                        name.capitalized,
                        isOn: Binding(
                            get: { settings.models.contains(name) }, set: { _ in model.toggleModel(name, for: id) })
                    )
                }
            }
            Picker(
                "Effort",
                selection: Binding(
                    get: { settings.effort },
                    set: { effort in
                        var updated = settings
                        updated.effort = effort
                        model.setSettings(updated, for: id)
                    })
            ) {
                ForEach(AIReviewModel.efforts, id: \.self) { Text($0.capitalized).tag($0) }
            }
            Picker(
                "Parallel agents",
                selection: Binding(
                    get: { settings.maxParallelAgents },
                    set: { count in
                        var updated = settings
                        updated.maxParallelAgents = count
                        model.setSettings(updated, for: id)
                    })
            ) {
                ForEach([1, 2, 3, 4, 6], id: \.self) { Text("\($0)").tag($0) }
            }
            Divider()
            Button("Save as default for all PRs") { model.defaultSettings = settings }
        }
    }

    private var isEnabled: Bool { pullRequest != nil && !isRunning }

    private func run() {
        guard let pullRequest else { return }
        Task { await model.run(pullRequest.id, title: pullRequest.title, body: pullRequestBody) }
    }

    private var isRunning: Bool { model.runState == .running }
}
