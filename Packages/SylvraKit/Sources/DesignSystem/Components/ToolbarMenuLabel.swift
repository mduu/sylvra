import AppKit
import SwiftUI

extension Image {
    /// An SF Symbol with transparent room on its left, for toolbar menus with a primary action
    /// (icon + chevron): macOS puts their icon right at the capsule's edge and ignores SwiftUI padding,
    /// so the room has to be part of the image.
    @MainActor
    public static func toolbarSymbol(_ name: String, leading: CGFloat = 9) -> Image {
        guard let image = ToolbarSymbolCache.image(name, leading: leading) else { return Image(systemName: name) }
        return Image(nsImage: image)
    }
}

/// Padded toolbar symbols, made once per name. A new `NSImage` on every view update makes AppKit
/// re-measure the toolbar item each time, which can loop the window's constraint pass until AppKit aborts.
@MainActor
enum ToolbarSymbolCache {
    private static var images: [String: NSImage] = [:]

    static func image(_ name: String, leading: CGFloat) -> NSImage? {
        let key = "\(name)|\(leading)"
        if let image = images[key] { return image }
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)
        guard
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else { return nil }
        let size = NSSize(width: symbol.size.width + leading, height: symbol.size.height)
        let padded = NSImage(size: size, flipped: false) { _ in
            symbol.draw(in: NSRect(origin: NSPoint(x: leading, y: 0), size: symbol.size))
            return true
        }
        padded.isTemplate = true
        images[key] = padded
        return padded
    }
}
