import DesignSystem
import SwiftUI
import SylvraCore

/// Confirms merging a pull request, switching auto-merge on or off (container: acts through the model).
/// Nothing is sent to GitHub before the confirming click; a refusal is shown here.
struct MergeSheet: View {
    @Bindable var model: PullRequestScreenModel
    let detail: PullRequestDetail
    let action: MergeOptions.Action
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MergeSheetView(
            detail: detail, action: action, method: $model.mergeMethod, isWorking: model.isMerging,
            error: model.mergeError, confirm: { Task { await model.confirmMerge() } }, cancel: { dismiss() })
    }
}

/// The merge sheet's content (pure).
struct MergeSheetView: View {
    let detail: PullRequestDetail
    let action: MergeOptions.Action
    @Binding var method: MergeMethod
    var isWorking = false
    var error: String?
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(verbatim: "\(detail.summary.id.repository) #\(detail.summary.id.number) · \(detail.summary.title)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if action == .disableAutoMerge {
                Text("GitHub no longer merges this pull request on its own once reviews and checks are through.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                methodPicker
                if action == .enableAutoMerge { waitingFor }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(SylvraColor.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var methods: [MergeMethod] { detail.mergeOptions?.methods ?? [] }

    @ViewBuilder private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if methods.count > 1 {
                Picker("Method", selection: $method) {
                    ForEach(methods) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } else {
                Text(method.title).font(.callout.weight(.medium))
            }
            Text(method.explanation(commits: detail.commits.count, base: detail.summary.baseRefName))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What still blocks the merge; GitHub merges once it is through.
    private var waitingFor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GitHub merges on its own once this is through:").font(.callout)
            ForEach(detail.mergeStatus.reasons, id: \.self) { reason in
                Label(reason, systemImage: "hourglass").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        switch action {
        case .merge: String(localized: "Merge pull request?")
        case .enableAutoMerge: String(localized: "Enable auto-merge?")
        case .disableAutoMerge: String(localized: "Disable auto-merge?")
        }
    }

    private var confirmTitle: String {
        switch action {
        case .merge: String(localized: "Merge")
        case .enableAutoMerge: String(localized: "Enable Auto-Merge")
        case .disableAutoMerge: String(localized: "Disable Auto-Merge")
        }
    }
}

#Preview {
    @Previewable @State var method = MergeMethod.squash
    var detail = DemoPullRequestDetailLoader.detail(for: .init(owner: "acme", repository: "billing", number: 1234))
    detail.mergeOptions = MergeOptions(
        pullRequestNodeID: "PR_1", methods: [.squash, .merge], viewerCanMerge: true, viewerCanEnableAutoMerge: true)
    return MergeSheetView(
        detail: detail, action: .enableAutoMerge, method: $method, error: "Pull request is in clean status",
        confirm: {}, cancel: {})
}
