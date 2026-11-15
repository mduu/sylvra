import SwiftUI

/// Default AI review settings (settings window pane).
public struct AIReviewSettingsView: View {
    @Bindable private var model: AIReviewModel

    public init(model: AIReviewModel) {
        self.model = model
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
        }
        .formStyle(.grouped)
        .task { await model.detectAgent() }
    }

    private static func languages(including current: String) -> [String] {
        let base = ["English", "German", "French", "Italian", "Spanish"]
        return base.contains(current) ? base : [current] + base
    }
}
