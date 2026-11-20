import DesignSystem
import SwiftUI

/// While the agent works on a chat answer: a pulsing sparkle with a turning ring, a shimmering status that
/// changes every few seconds ("Reading the diff…", "Weighing edge cases…") and the time waited so far.
/// Reduce Motion keeps the sparkle and text still; the status still changes.
struct ChatThinkingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    /// Each answer starts somewhere else in the list.
    @State private var offset = Int.random(in: 0..<ChatThinkingView.phrases.count)

    static let phrases: [LocalizedStringResource] = [
        "Reading the diff",
        "Following the call chain",
        "Weighing edge cases",
        "Squinting at the types",
        "Consulting the tests",
        "Untangling the logic",
        "Connecting the dots",
        "Checking the history",
        "Mulling it over",
        "Brewing an answer",
        "Sharpening the wording",
    ]

    /// Seconds each status stays.
    nonisolated static let phraseDuration: TimeInterval = 2.8

    /// The status after `elapsed` seconds, starting at `offset` in the list.
    nonisolated static func phraseIndex(elapsed: TimeInterval, offset: Int, count: Int) -> Int {
        (offset + Int(max(elapsed, 0) / phraseDuration)) % max(count, 1)
    }

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let index = Self.phraseIndex(elapsed: elapsed, offset: offset, count: Self.phrases.count)
            HStack(spacing: 8) {
                ThinkingOrb(isAnimated: !reduceMotion)
                ShimmerText(text: Text("\(Text(Self.phrases[index]))…"), isAnimated: !reduceMotion)
                    .id(index)
                    .transition(.push(from: .bottom).combined(with: .opacity))
                if elapsed >= 3 {
                    Text(Duration.seconds(Int(elapsed)), format: .units(allowed: [.minutes, .seconds], width: .narrow))
                        .aiFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: index)
            .animation(reduceMotion ? nil : .default, value: Int(elapsed))
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Thinking"))
    }
}

/// A sparkle that pulses inside a slowly turning ring of the AI colors.
private struct ThinkingOrb: View {
    let isAnimated: Bool
    @State private var isTurning = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.78)
                .stroke(
                    AngularGradient(colors: AIAccent.colors + [AIAccent.colors[0]], center: .center),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                .rotationEffect(.degrees(isTurning ? 360 : 0))
            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(AIAccent.border)
                .symbolEffect(.pulse, isActive: isAnimated)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            guard isAnimated else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { isTurning = true }
        }
    }
}

/// Text in the AI colors with a light band sweeping across it.
private struct ShimmerText: View {
    let text: Text
    let isAnimated: Bool
    @State private var phase: CGFloat = -1

    var body: some View {
        text
            .aiFont(.caption, weight: .medium)
            .foregroundStyle(AIAccent.lineGradient(opacity: 1))
            .overlay {
                if isAnimated {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 60)
                    .offset(x: phase * 120)
                    .blendMode(.plusLighter)
                    .mask(text.aiFont(.caption, weight: .medium))
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard isAnimated else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ChatThinkingView()
    }
    .padding()
}
