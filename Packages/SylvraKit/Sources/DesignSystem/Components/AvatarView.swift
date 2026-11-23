import AppKit
import SwiftUI
import SylvraCore

/// Circular user avatar with initials as fallback. Avatars come from `AvatarCache`: one seen before draws in the
/// same frame, without loading or decoding it again.
public struct AvatarView: View {
    private let user: UserRef
    private let size: CGFloat
    /// The image loaded by this view, with its URL (a reused row may still hold the previous user's).
    @State private var loaded: (url: URL, image: NSImage)?

    public init(_ user: UserRef, size: CGFloat = 24) {
        self.user = user
        self.size = size
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.primary.opacity(0.08)))
        .accessibilityLabel(Text(user.displayName))
        .task(id: user.avatarURL) {
            guard let url = user.avatarURL, AvatarCache.shared.cachedImage(for: url) == nil else { return }
            if let image = await AvatarCache.shared.image(for: url) { loaded = (url, image) }
        }
    }

    private var image: NSImage? {
        guard let url = user.avatarURL else { return nil }
        return AvatarCache.shared.cachedImage(for: url) ?? (loaded?.url == url ? loaded?.image : nil)
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Self.color(for: user.login).gradient)
            Text(user.initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    /// Stable, pleasant color per login.
    static func color(for login: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.48, green: 0.36, blue: 0.84),
            Color(red: 0.18, green: 0.54, blue: 0.52),
            Color(red: 0.71, green: 0.35, blue: 0.24),
            Color(red: 0.29, green: 0.16, blue: 0.54),
            Color(red: 0.35, green: 0.48, blue: 0.18),
            Color(red: 0.54, green: 0.24, blue: 0.47),
        ]
        let hash = login.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}

#Preview {
    HStack {
        AvatarView(UserRef(login: "lkeller", name: "Lena Keller"), size: 32)
        AvatarView(UserRef(login: "jm"), size: 32)
    }
    .padding()
}
