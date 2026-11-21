import AppKit
import DesignSystem
import SwiftUI

/// *About Sylvra*: the app on a brand canvas (like a splash), a link to the project, the open-source software it
/// ships with (each with its full license text) and the author as a footnote (pure).
///
/// Dark: the deep violet canvas with lavender glows. Light: a pale lavender canvas with violet ink.
public struct AboutView: View {
    let icon: Image
    let version: String
    let build: String?
    let copyright: String
    let author: String
    let projectURL: URL?
    let licenseURL: URL?
    let acknowledgements: [Acknowledgement]
    let checkForUpdates: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var expanded: Acknowledgement.ID?

    public init(
        icon: Image, version: String, build: String?, copyright: String, author: String, projectURL: URL?,
        licenseURL: URL?,
        acknowledgements: [Acknowledgement] = Acknowledgement.all, checkForUpdates: @escaping () -> Void
    ) {
        self.icon = icon
        self.version = version
        self.build = build
        self.copyright = copyright
        self.author = author
        self.projectURL = projectURL
        self.licenseURL = licenseURL
        self.acknowledgements = acknowledgements
        self.checkForUpdates = checkForUpdates
    }

    public static let width: CGFloat = 440

    private var ink: AboutInk { AboutInk(colorScheme) }

    public var body: some View {
        VStack(spacing: 0) {
            hero
                .padding(.top, 40)
                .padding(.bottom, 24)
            actions
                .padding(.bottom, 26)
            AboutHairline()
            openSource
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            AboutHairline()
            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
        }
        .frame(width: Self.width)
        .background(AboutBackground())
        .animation(.snappy(duration: 0.25), value: expanded)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(SylvraColor.brandPrimary.opacity(ink.isDark ? 0.45 : 0.35))
                    .frame(width: 120, height: 120)
                    .blur(radius: 38)
                Circle()
                    .fill(SylvraColor.accentGold.opacity(ink.isDark ? 0.18 : 0.3))
                    .frame(width: 60, height: 60)
                    .blur(radius: 26)
                    .offset(x: 34, y: -30)
                icon
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 128, height: 128)
                    .shadow(color: ink.shadow, radius: 18, y: 10)
            }
            .accessibilityHidden(true)
            .padding(.bottom, 14)

            Text("Sylvra")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: ink.titleColors, startPoint: .top, endPoint: .bottom))
            Text("A quiet place for focused review.")
                .font(.system(.callout, design: .serif).italic())
                .foregroundStyle(ink.text(0.62))
                .padding(.top, 2)
            facts
                .padding(.top, 24)
        }
    }

    /// The version as type alone: a small label over large thin figures, the build below them.
    private var facts: some View {
        VStack(spacing: 2) {
            Text("VERSION")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(ink.label)
            VStack(spacing: 0) {
                Text(version)
                    .font(.system(size: 30, weight: .thin, design: .rounded).monospacedDigit())
                    .foregroundStyle(LinearGradient(colors: ink.versionColors, startPoint: .top, endPoint: .bottom))
                if let build {
                    Text("build \(build)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ink.text(0.42))
                }
            }
            .textSelection(.enabled)
        }
        .fixedSize()
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 10) {
            if let projectURL {
                Button {
                    openURL(projectURL)
                } label: {
                    Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(AboutCapsuleButtonStyle(isProminent: true))
                .help(projectURL.absoluteString)
            }
            Button(action: checkForUpdates) {
                Label("Check for Updates", systemImage: "arrow.down.circle")
            }
            .buttonStyle(AboutCapsuleButtonStyle(isProminent: false))
        }
    }

    // MARK: Open source

    private var openSource: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Open source")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink.text(1))
                Spacer()
                Text("Thank you!")
                    .font(.caption)
                    .foregroundStyle(ink.text(0.45))
            }
            Text("Sylvra builds on this open-source software:")
                .font(.caption)
                .foregroundStyle(ink.text(0.6))
            ForEach(acknowledgements) { acknowledgement in
                AcknowledgementCard(
                    acknowledgement: acknowledgement,
                    isExpanded: expanded == acknowledgement.id,
                    toggle: { expanded = expanded == acknowledgement.id ? nil : acknowledgement.id },
                    open: { openURL($0) })
            }
            Text("Works with Git, the GitHub CLI and Claude Code, installed separately.")
                .font(.caption2)
                .foregroundStyle(ink.text(0.45))
                .padding(.top, 2)
        }
    }

    // MARK: Footer

    /// The author as a footnote, then the copyright and Sylvra's license.
    private var footer: some View {
        VStack(spacing: 3) {
            Text("Made by \(author)")
                .foregroundStyle(ink.text(0.62))
            HStack(spacing: 6) {
                Text(copyright)
                Text("·")
                if let licenseURL {
                    Button("MIT License") { openURL(licenseURL) }
                        .buttonStyle(.link)
                        .tint(SylvraColor.brandPrimary)
                } else {
                    Text("MIT License")
                }
            }
            .foregroundStyle(ink.text(0.45))
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }
}

#Preview("About") {
    AboutView(
        icon: Image(nsImage: NSApplication.shared.applicationIconImage),
        version: "0.6.6",
        build: "48",
        copyright: "© 2026 Marc Dürst",
        author: "Marc Dürst",
        projectURL: URL(string: "https://github.com/mduu/sylvra"),
        licenseURL: URL(string: "https://github.com/mduu/sylvra/blob/main/LICENSE"),
        checkForUpdates: {})
}

#Preview("About, light") {
    AboutView(
        icon: Image(nsImage: NSApplication.shared.applicationIconImage),
        version: "0.6.6",
        build: "48",
        copyright: "© 2026 Marc Dürst",
        author: "Marc Dürst",
        projectURL: URL(string: "https://github.com/mduu/sylvra"),
        licenseURL: URL(string: "https://github.com/mduu/sylvra/blob/main/LICENSE"),
        checkForUpdates: {}
    )
    .preferredColorScheme(.light)
}
