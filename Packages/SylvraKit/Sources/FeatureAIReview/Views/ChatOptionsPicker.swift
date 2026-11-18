import DesignSystem
import SwiftUI
import SylvraCore

/// Two small menus below the chat input: the model and the effort of the next question (container).
struct ChatOptionsPicker: View {
    let model: AIChatModel
    let pullRequestID: PullRequestID

    var body: some View {
        let options = model.options(for: pullRequestID)
        HStack(spacing: 4) {
            Menu {
                Picker("Model", selection: binding(options.model) { model.setModel($0, for: pullRequestID) }) {
                    ForEach(AIReviewModel.availableModels, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(options.model.capitalized, systemImage: "cpu")
            }
            .help("Model for the next question")
            Menu {
                Picker("Effort", selection: binding(options.effort) { model.setEffort($0, for: pullRequestID) }) {
                    ForEach(AIReviewModel.efforts, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(options.effort.capitalized, systemImage: "gauge.with.dots.needle.50percent")
            }
            .help("Effort for the next question — more is slower, but thinks deeper")
            Spacer(minLength: 0)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.visible)
        .fixedSize(horizontal: false, vertical: true)
        .aiFont(.caption)
        .foregroundStyle(.secondary)
    }

    private func binding(_ value: String, set: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: { value }, set: set)
    }
}
