import DesignSystem
import SwiftUI
import SylvraCore

/// "✦ AI Review ▾" toolbar button: one click runs, the menu sets models and effort per PR (container).
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
        Menu {
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
        } label: {
            Label(isRunning ? "Reviewing…" : "AI Review", systemImage: isRunning ? "sparkles" : "sparkles")
                .symbolEffect(.pulse, isActive: isRunning)
        } primaryAction: {
            guard let pullRequest else { return }
            Task { await model.run(pullRequest.id, title: pullRequest.title, body: pullRequestBody) }
        }
        .disabled(pullRequest == nil || isRunning)
        .help("Run an AI review with the local agent (⌘⇧R)")
        .keyboardShortcut("r", modifiers: [.command, .shift])
    }

    private var isRunning: Bool { model.runState == .running }
}
