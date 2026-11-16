import AppKit
import DesignSystem
import SwiftUI

/// Sideways scrolling for the diff's code: the rows are in a vertical lazy stack, so horizontal wheel and
/// trackpad events (also ⇧ + mouse wheel) are taken while the pointer is over the diff and shift all code
/// together, leaving the gutters in place.
struct HorizontalWheelScrolling: ViewModifier {
    let scroll: (CGFloat) -> Void
    @State private var monitor = WheelMonitor()

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                if case .active = phase { monitor.isPointerInside = true } else { monitor.isPointerInside = false }
            }
            .onAppear { monitor.start(scroll) }
            .onDisappear { monitor.stop() }
    }
}

/// Holds the event monitor (reference type: the closure must outlive view updates).
@MainActor
private final class WheelMonitor {
    var isPointerInside = false
    private var token: Any?

    func start(_ scroll: @escaping (CGFloat) -> Void) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isPointerInside,
                abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            else { return event }
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            scroll(-event.scrollingDeltaX * factor)
            return nil
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

/// A slim scroll bar at the bottom of the diff while lines are wider than the view (drag to scroll).
struct HorizontalScrollIndicator: View {
    let offset: CGFloat
    let maxOffset: CGFloat
    let codeWidth: CGFloat
    let scroll: (CGFloat) -> Void
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let track = geometry.size.width
            let thumb = max(track * codeWidth / (codeWidth + maxOffset), 36)
            let position = maxOffset > 0 ? (track - thumb) * offset / maxOffset : 0
            Capsule()
                .fill(Color.secondary.opacity(isDragging ? 0.7 : 0.45))
                .frame(width: thumb, height: 6)
                .offset(x: position)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let ratio = maxOffset / max(track - thumb, 1)
                            scroll((position + value.translation.width) * ratio - offset)
                        }
                        .onEnded { _ in isDragging = false }
                )
        }
        .frame(height: 6)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .help("Scroll sideways — or swipe sideways / ⇧ + mouse wheel")
    }
}

extension View {
    func horizontalWheelScrolling(_ scroll: @escaping (CGFloat) -> Void) -> some View {
        modifier(HorizontalWheelScrolling(scroll: scroll))
    }
}
