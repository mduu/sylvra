import SwiftUI
import SylvraCore

/// Circular user avatar with initials as fallback.
public struct AvatarView: View {
    private let user: UserRef
    private let size: CGFloat

    public init(_ user: UserRef, size: CGFloat = 24) {
        self.user = user
        self.size = size
    }

    public var body: some View {
        AsyncImage(url: user.avatarURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.primary.opacity(0.08)))
        .accessibilityLabel(Text(user.displayName))
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
