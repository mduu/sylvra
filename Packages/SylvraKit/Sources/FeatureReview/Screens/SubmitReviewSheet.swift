import DesignSystem
import SwiftUI
import SylvraCore

/// Sheet to submit the review: summary, event and the list of pending comments (container).
public struct SubmitReviewSheet: View {
    @Bindable private var model: ReviewScreenModel
    @Environment(\.dismiss) private var dismiss

    public init(model: ReviewScreenModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Submit review").font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Summary").font(.headline)
                TextEditor(text: $model.submitBody)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 110)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            }

            Picker("Event", selection: $model.submitEvent) {
                ForEach(ReviewEvent.allCases) { event in
                    Label(event.title, systemImage: event.systemImage).tag(event)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            PendingCommentsView(comments: model.pendingComments.map { ($0.thread.location, $0.comment) })

            SubmitProblemView(problem: model.submitProblem, error: model.submitError)

            HStack {
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Submit review") { Task { await model.submitReview() } }
                    .buttonStyle(.borderedProminent)
                    .tint(SylvraColor.brandPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isWorking || model.submitProblem != nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: model.submitEvent) { model.submitError = nil }
        .onDisappear { model.submitError = nil }
    }
}

/// Why the review can't be submitted yet, or why GitHub refused it (pure).
struct SubmitProblemView: View {
    let problem: String?
    let error: String?

    var body: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(SylvraColor.statusCritical)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else if let problem {
            Label(problem, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The comments of the pending review (pure).
struct PendingCommentsView: View {
    let comments: [(location: CodeLocation, comment: ReviewComment)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pending comments (\(comments.count))").font(.headline)
            if comments.isEmpty {
                Text("No inline comments — the review consists of the summary only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(comments, id: \.comment.id) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.location.description)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                Text(MarkdownBodyView.attributed(ReviewThreadView.preview(of: item.comment.body)))
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                // A scroll view has no ideal height inside a sheet; size it to its content up to a limit.
                .frame(height: min(CGFloat(comments.count) * 64, 192))
            }
        }
    }
}

extension ReviewEvent {
    var title: LocalizedStringKey {
        switch self {
        case .comment: "Comment — general feedback without explicit approval"
        case .approve: "Approve — give your approval to merge"
        case .requestChanges: "Request changes — feedback that must be addressed"
        }
    }

    var systemImage: String {
        switch self {
        case .comment: "text.bubble"
        case .approve: "checkmark.circle"
        case .requestChanges: "exclamationmark.bubble"
        }
    }
}

#Preview {
    let snapshot = DemoReviewService.sample()
    PendingCommentsView(
        comments: snapshot.threads.flatMap { thread in thread.comments.map { (thread.location, $0) } }
    )
    .padding()
    .frame(width: 480)
}
