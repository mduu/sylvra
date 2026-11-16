import AppKit
import SwiftUI

extension Image {
    /// An SF Symbol with transparent room on its left, for toolbar menus with a primary action
    /// (icon + chevron): macOS puts their icon right at the capsule's edge and ignores SwiftUI padding,
    /// so the room has to be part of the image.
    public static func toolbarSymbol(_ name: String, leading: CGFloat = 5) -> Image {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)
        guard
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else { return Image(systemName: name) }
        let size = NSSize(width: symbol.size.width + leading, height: symbol.size.height)
        let padded = NSImage(size: size, flipped: false) { _ in
            symbol.draw(in: NSRect(origin: NSPoint(x: leading, y: 0), size: symbol.size))
            return true
        }
        padded.isTemplate = true
        return Image(nsImage: padded)
    }
}
