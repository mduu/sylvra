import DesignSystem
import SwiftUI

/// The brand look of the update UI.
enum UpdateBrand {
    static let gradient = LinearGradient(
        colors: [SylvraColor.brandPrimary, SylvraColor.brandSecondary, SylvraColor.accentGold],
        startPoint: .leading, endPoint: .trailing)

    static let border = LinearGradient(
        colors: [SylvraColor.brandPrimary.opacity(0.55), SylvraColor.accentGold.opacity(0.35), .clear],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Material with a soft brand glow from the top corner.
struct UpdateCardBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            SylvraColor.surfaceElevated.opacity(0.6)
            RadialGradient(
                colors: [SylvraColor.brandTint, SylvraColor.brandTint.opacity(0)],
                center: .topLeading, startRadius: 0, endRadius: 260)
            RadialGradient(
                colors: [SylvraColor.accentGold.opacity(0.12), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 180)
        }
    }
}

/// The app icon on a glowing ring that turns while work is going on (still with Reduce Motion).
struct UpdateIconHalo: View {
    let icon: Image
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(SylvraColor.brandTint)
                .blur(radius: 10)
            if isActive && !reduceMotion {
                TimelineView(.animation) { context in
                    ring.rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 120))
                }
            } else {
                ring
            }
            icon
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }

    private var ring: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [
                        SylvraColor.brandPrimary, SylvraColor.accentGold, SylvraColor.brandSecondary,
                        SylvraColor.brandPrimary,
                    ],
                    center: .center),
                lineWidth: 2
            )
            .opacity(isActive ? 1 : 0.6)
    }
}

/// A slim brand gradient bar: determinate with `fraction`, otherwise a sweeping highlight.
struct UpdateProgressBar: View {
    let fraction: Double?
    let label: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SylvraColor.brandTint)
                    if let fraction {
                        Capsule()
                            .fill(UpdateBrand.gradient)
                            .frame(width: max(6, proxy.size.width * fraction))
                            .animation(.easeOut(duration: 0.25), value: fraction)
                    } else if reduceMotion {
                        Capsule().fill(UpdateBrand.gradient).opacity(0.6)
                    } else {
                        sweep(width: proxy.size.width)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            if let label {
                Text(label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(label ?? String(localized: "In progress"))
    }

    private func sweep(width: CGFloat) -> some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            Capsule()
                .fill(UpdateBrand.gradient)
                .frame(width: width * 0.35)
                .offset(x: (width * 1.35) * phase - width * 0.35)
        }
    }
}
