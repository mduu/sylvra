import DesignSystem
import SwiftUI

/// The update card (pure): announces a new version with its changes and walks through download, check and
/// relaunch. Brand colors only — an update is not AI content.
public struct UpdateCardView: View {
    let state: UpdateModel.State
    let currentVersion: String
    let canInstallInPlace: Bool
    let icon: Image
    let install: () -> Void
    let later: () -> Void
    let skip: () -> Void
    let openPage: (URL) -> Void

    public init(
        state: UpdateModel.State, currentVersion: String, canInstallInPlace: Bool, icon: Image,
        install: @escaping () -> Void, later: @escaping () -> Void, skip: @escaping () -> Void,
        openPage: @escaping (URL) -> Void
    ) {
        self.state = state
        self.currentVersion = currentVersion
        self.canInstallInPlace = canInstallInPlace
        self.icon = icon
        self.install = install
        self.later = later
        self.skip = skip
        self.openPage = openPage
    }

    public static let width: CGFloat = 380

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            if let release, showsNotes {
                Divider().overlay(SylvraColor.codeHairline)
                notes(release)
            }
            Divider().overlay(SylvraColor.codeHairline)
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: Self.width)
        .background(UpdateCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(UpdateBrand.border, lineWidth: 1)
        }
        .shadow(color: SylvraColor.canvasDeep.opacity(0.28), radius: 24, y: 10)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            UpdateIconHalo(icon: icon, isActive: isActive)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: later) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(release == nil ? "Close" : "Remind me later")
            .accessibilityLabel(release == nil ? "Close" : "Later")
            .disabled(isBusy)
            .opacity(isBusy ? 0 : 1)
        }
    }

    private var title: String {
        switch state {
        case .idle, .checking: String(localized: "Checking for updates…")
        case .upToDate: String(localized: "You're up to date")
        case .failed(nil, _): String(localized: "Couldn't check for updates")
        case .failed(.some(let release), _): String(localized: "Sylvra \(release.version.description) didn't install")
        case .available(let release): String(localized: "Sylvra \(release.version.description) is here")
        case .downloading(let release, _): String(localized: "Downloading Sylvra \(release.version.description)")
        case .verifying: String(localized: "Checking the signature…")
        case .relaunching: String(localized: "Restarting Sylvra…")
        case .downloaded(let release): String(localized: "Sylvra \(release.version.description) is downloaded")
        }
    }

    private var subtitle: String {
        switch state {
        case .idle, .checking: String(localized: "Looking at the latest release on GitHub.")
        case .upToDate: String(localized: "Sylvra \(currentVersion) is the newest version.")
        case .failed(_, let message): message
        case .available(let release), .downloading(let release, _):
            [String(localized: "You have \(currentVersion)"), Self.size(of: release), Self.date(of: release)]
                .compactMap { $0 }.joined(separator: " · ")
        case .verifying: String(localized: "Making sure the new version comes from the Sylvra team.")
        case .relaunching: String(localized: "The new version opens in a moment.")
        case .downloaded:
            String(
                localized: "Sylvra isn't in your Applications folder: drag the new version there from the disk image.")
        }
    }

    // MARK: What's new

    private var showsNotes: Bool {
        switch state {
        case .available, .downloading: true
        default: false
        }
    }

    private func notes(_ release: AppRelease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("What's new", systemImage: "sparkle")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(SylvraColor.brandPrimary)
                    .labelStyle(.titleAndIcon)
                Spacer()
                if let page = release.page {
                    Button("Release Notes") { openPage(page) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            ScrollView {
                MarkdownView(text: release.notes.isEmpty ? String(localized: "Fixes and improvements.") : release.notes)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: 200)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(SylvraColor.surfacePrimary.opacity(0.55))
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        switch state {
        case .available:
            HStack(spacing: 8) {
                Button("Skip This Version", action: skip)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer(minLength: 0)
                Button("Later", action: later)
                installButton(canInstallInPlace ? "Install & Relaunch" : "Download")
            }
        case .downloading(_, let progress):
            UpdateProgressBar(fraction: progress, label: Self.percent(progress))
        case .verifying, .relaunching, .checking, .idle:
            UpdateProgressBar(fraction: nil, label: nil)
        case .upToDate, .downloaded:
            HStack {
                Spacer()
                Button("OK", action: later).keyboardShortcut(.defaultAction)
            }
        case .failed(let release, _):
            HStack(spacing: 8) {
                if let page = release?.page {
                    Button("Open on GitHub") { openPage(page) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Close", action: later)
                if release != nil { installButton("Try Again") }
            }
        }
    }

    private func installButton(_ title: LocalizedStringKey) -> some View {
        Button(action: install) {
            Text(title).padding(.horizontal, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(SylvraColor.brandPrimary)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: Helpers

    private var release: AppRelease? {
        switch state {
        case .available(let release), .downloading(let release, _), .verifying(let release),
            .relaunching(let release), .downloaded(let release):
            release
        case .failed(let release, _): release
        case .idle, .checking, .upToDate: nil
        }
    }

    private var isBusy: Bool {
        switch state {
        case .downloading, .verifying, .relaunching: true
        default: false
        }
    }

    private var isActive: Bool {
        switch state {
        case .checking, .downloading, .verifying, .relaunching: true
        default: false
        }
    }

    static func size(of release: AppRelease) -> String? {
        guard release.diskImageSize > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: release.diskImageSize, countStyle: .file)
    }

    static func date(of release: AppRelease) -> String? {
        release.publishedAt.map { $0.formatted(.relative(presentation: .named)) }
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

#Preview("Update card") {
    ScrollView {
        VStack(spacing: 20) {
            ForEach(["available", "downloading", "verifying", "upToDate", "failed", "downloaded"], id: \.self) { name in
                if let demo = DemoUpdates.state(named: name) {
                    UpdateCardView(
                        state: demo.state, currentVersion: "0.5.35", canInstallInPlace: true,
                        icon: Image(systemName: "leaf.fill"), install: {}, later: {}, skip: {}, openPage: { _ in })
                }
            }
        }
        .padding(30)
    }
    .frame(height: 900)
    .background(SylvraColor.surfacePrimary)
}
