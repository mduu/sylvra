import DesignSystem
import SwiftUI

/// The About window's ink for the current appearance: white on the deep canvas, deep violet on the light one.
struct AboutInk {
    let isDark: Bool

    init(_ colorScheme: ColorScheme) {
        isDark = colorScheme == .dark
    }

    /// Text and strokes at the given strength.
    func text(_ opacity: Double) -> Color {
        (isDark ? Color.white : SylvraColor.canvasDeep).opacity(opacity)
    }

    /// Small caps labels: gold on the dark canvas; violet in light mode, where gold is too faint to read.
    var label: Color { isDark ? SylvraColor.accentGold.opacity(0.85) : SylvraColor.brandPrimary }

    var titleColors: [Color] {
        isDark
            ? [.white, SylvraColor.terminalForeground, SylvraColor.brandPrimary]
            : [SylvraColor.brandPrimary, SylvraColor.canvasDeep]
    }

    var versionColors: [Color] {
        isDark ? [.white, SylvraColor.accentGoldSoft] : [SylvraColor.canvasDeep, SylvraColor.brandPrimary]
    }

    var shadow: Color { isDark ? .black.opacity(0.45) : SylvraColor.brandPrimary.opacity(0.28) }
}

/// One bundled project: name, purpose, license chip, link, and its license text on demand.
struct AcknowledgementCard: View {
    let acknowledgement: Acknowledgement
    let isExpanded: Bool
    let toggle: () -> Void
    let open: (URL) -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = AboutInk(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(SylvraColor.brandPrimary)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(SylvraColor.brandPrimary.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(acknowledgement.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(ink.text(1))
                        Text(acknowledgement.purpose)
                            .font(.caption)
                            .foregroundStyle(ink.text(0.58))
                    }
                    Spacer(minLength: 8)
                    Text(acknowledgement.license)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ink.isDark ? SylvraColor.accentGold : ink.text(0.75))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(SylvraColor.accentGold.opacity(ink.isDark ? 0.12 : 0.3)))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ink.text(0.45))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide the license" : "Show the license")
            .accessibilityLabel("\(acknowledgement.name), \(acknowledgement.license)")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        Text(acknowledgement.notice)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ink.text(0.72))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 150)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ink.isDark ? Color.black.opacity(0.28) : ink.text(0.05)))
                    if let url = acknowledgement.url {
                        Button {
                            open(url)
                        } label: {
                            Label(
                                url.absoluteString.replacingOccurrences(of: "https://", with: ""),
                                systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .tint(SylvraColor.brandPrimary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardFill(ink))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ink.text(ink.isDark ? 0.08 : 0.1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private func cardFill(_ ink: AboutInk) -> Color {
        let isLifted = isHovering || isExpanded
        return ink.isDark
            ? .white.opacity(isLifted ? 0.075 : 0.045)
            : SylvraColor.surfaceElevated.opacity(isLifted ? 0.95 : 0.7)
    }
}

/// The brand canvas with a violet glow behind the icon and a faint gold one. The glows drift slowly on their
/// own (a calm, barely noticeable movement); with Reduce Motion they stand still.
struct AboutBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if reduceMotion {
                canvas(time: 0)
            } else {
                // A low frame rate is plenty for a drift this slow.
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    canvas(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func canvas(time: TimeInterval) -> some View {
        let isDark = colorScheme == .dark
        // Incommensurate periods (about 13, 17 and 23 s), so the pattern never visibly repeats.
        let main = UnitPoint(x: 0.5 + 0.10 * sin(time / 13 * 2 * .pi), y: 0.08 + 0.05 * cos(time / 17 * 2 * .pi))
        let gold = UnitPoint(x: 0.88 + 0.10 * cos(time / 23 * 2 * .pi), y: 0.02 + 0.06 * sin(time / 13 * 2 * .pi))
        let deep = UnitPoint(x: 0.05 + 0.15 * sin(time / 17 * 2 * .pi), y: 0.95 - 0.08 * cos(time / 23 * 2 * .pi))
        let breathe = 1 + 0.06 * sin(time / 11 * 2 * .pi)
        return ZStack {
            isDark ? SylvraColor.canvasDeep : SylvraColor.surfacePrimary
            RadialGradient(
                colors: [SylvraColor.brandPrimary.opacity(isDark ? 0.32 : 0.22), .clear],
                center: main, startRadius: 0, endRadius: 330 * breathe)
            RadialGradient(
                colors: [SylvraColor.accentGold.opacity(isDark ? 0.10 : 0.22), .clear],
                center: gold, startRadius: 0, endRadius: 220)
            RadialGradient(
                colors: [
                    (isDark ? SylvraColor.brandSecondary : SylvraColor.brandTint).opacity(isDark ? 0.45 : 1), .clear,
                ],
                center: deep, startRadius: 0, endRadius: 300 / breathe)
        }
    }
}

/// A hairline that fades out towards both ends.
struct AboutHairline: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: [.clear, AboutInk(colorScheme).text(0.12), .clear], startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }
}

/// Capsule buttons on the canvas: the prominent one in brand violet, the other glassy.
struct AboutCapsuleButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        AboutCapsule(configuration: configuration, isProminent: isProminent)
    }

    private struct AboutCapsule: View {
        let configuration: Configuration
        let isProminent: Bool
        @State private var isHovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let ink = AboutInk(colorScheme)
            configuration.label
                .font(.callout.weight(.medium))
                .foregroundStyle(isProminent ? Color.white : ink.text(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    if isProminent {
                        // Dark: royal violet lifted with lavender. Light: Sylvra violet with a lavender sheen.
                        // White text stays readable on both.
                        Capsule().fill(ink.isDark ? SylvraColor.brandSecondary : SylvraColor.brandPrimary)
                            .overlay(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [
                                            (ink.isDark ? SylvraColor.brandPrimary : SylvraColor.brandSecondary)
                                                .opacity(0.55), .clear,
                                        ],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)))
                    } else {
                        Capsule().fill(
                            ink.isDark
                                ? Color.white.opacity(isHovering ? 0.12 : 0.07)
                                : SylvraColor.surfaceElevated.opacity(isHovering ? 1 : 0.75))
                    }
                }
                .overlay(
                    Capsule().strokeBorder(
                        isProminent ? Color.white.opacity(ink.isDark ? 0.22 : 0.3) : ink.text(ink.isDark ? 0.12 : 0.12)
                    )
                )
                .shadow(
                    color: isProminent ? SylvraColor.brandPrimary.opacity(isHovering ? 0.5 : 0.3) : .clear,
                    radius: isHovering ? 12 : 8, y: 3
                )
                .brightness(isProminent && isHovering ? 0.06 : 0)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .contentShape(Capsule())
                .onHover { hovering in
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { isHovering = hovering }
                }
        }
    }
}
