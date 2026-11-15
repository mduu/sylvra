import DesignSystem
import SwiftUI

/// Toolbar activity indicator with a popover listing running jobs (container).
public struct ActivityToolbarPanel: View {
    private let center: ActivityCenter
    @State private var isShowingPopover = false

    public init(center: ActivityCenter) {
        self.center = center
    }

    public var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            ActivityIndicatorView(isBusy: center.isBusy)
        }
        .help(center.isBusy ? "Working in the background" : "No background work")
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Background activity").font(.headline)
                if center.running.isEmpty {
                    Text("Nothing running.").foregroundStyle(.secondary)
                }
                ForEach(center.running) { job in
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(job.title)
                    }
                }
            }
            .padding()
            .frame(minWidth: 240, alignment: .leading)
        }
    }
}

/// A calm ring that turns into a rotating gold arc while work is running (pure).
struct ActivityIndicatorView: View {
    let isBusy: Bool
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.3), lineWidth: 2.5)
            if isBusy {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(SylvraColor.accentGold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { rotation = 360 }
                    }
            }
        }
        .frame(width: 15, height: 15)
        .accessibilityLabel(Text(isBusy ? "Working" : "Idle"))
    }
}

/// Notification toggles per job type (pure container for the settings window).
public struct NotificationSettingsView: View {
    private let center: ActivityCenter
    @State private var refreshToken = 0

    public init(center: ActivityCenter) {
        self.center = center
    }

    public var body: some View {
        Form {
            Section {
                ForEach(ActivityJob.Kind.allCases, id: \.self) { kind in
                    Toggle(
                        kind.title,
                        isOn: Binding(
                            get: {
                                _ = refreshToken; return center.notificationsEnabled(for: kind)
                            },
                            set: {
                                center.setNotificationsEnabled($0, for: kind)
                                refreshToken += 1
                            }))
                }
            } footer: {
                Text("Sylvra notifies you when background work finishes while the app is not in front.")
            }
        }
        .formStyle(.grouped)
    }
}
