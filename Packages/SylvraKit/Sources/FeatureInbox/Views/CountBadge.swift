import DesignSystem
import SwiftUI

/// A small capsule with a count next to a section heading (pure). `isProminent` (gold) marks counts that
/// need the reviewer, e.g. review requests addressed to them.
struct CountBadge: View {
    let count: Int
    var isProminent = false

    var body: some View {
        Text(count, format: .number)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .frame(minWidth: 18)
            .foregroundStyle(isProminent ? AnyShapeStyle(Color.black.opacity(0.8)) : AnyShapeStyle(.secondary))
            .background(
                isProminent ? AnyShapeStyle(SylvraColor.accentGold) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .accessibilityLabel(Text("\(count) pull requests"))
    }
}

/// A sidebar section heading with its count badge right next to it (pure).
struct SectionHeading: View {
    let title: String
    let count: Int
    var isProminent = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            CountBadge(count: count, isProminent: isProminent)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        SectionHeading(title: "Requested from me", count: 2, isProminent: true)
        SectionHeading(title: "My teams", count: 14)
        SectionHeading(title: "Recently closed", count: 1)
    }
    .padding()
    .frame(width: 260)
}
