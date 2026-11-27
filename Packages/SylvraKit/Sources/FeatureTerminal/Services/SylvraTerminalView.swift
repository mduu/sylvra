import AppKit
import OSLog
import Platform
@preconcurrency import SwiftTerm

/// SwiftTerm's terminal view plus images and files: ⌘V with an image (a screenshot) and no text, or a drop of
/// files or an image, types the path — Claude Code then reads the image. Images without a file are written to
/// `TerminalPasteFiles.directory` first.
final class SylvraTerminalView: LocalProcessTerminalView {
    private let logger = SylvraLog.logger("terminal")

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func paste(_ sender: Any) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.string(forType: .string) == nil, let path = imagePath(from: pasteboard) else {
            super.paste(sender)
            return
        }
        pasteText(TerminalPasteFiles.text(for: [path]))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        paths(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let paths = paths(from: sender.draggingPasteboard)
        guard !paths.isEmpty else { return false }
        window?.makeFirstResponder(self)
        pasteText(TerminalPasteFiles.text(for: paths))
        return true
    }

    /// Dropped files, else a dropped image written to a file.
    func paths(from pasteboard: NSPasteboard) -> [String] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        let files = urls.compactMap { ($0 as? URL)?.path }
        if !files.isEmpty { return files }
        return imagePath(from: pasteboard).map { [$0] } ?? []
    }

    private func imagePath(from pasteboard: NSPasteboard) -> String? {
        guard let png = Self.png(from: pasteboard) else { return nil }
        do {
            return try TerminalPasteFiles.save(png: png).path
        } catch {
            logger.error("Could not save a pasted image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func png(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let image = NSBitmapImageRep(data: tiff) else { return nil }
        return image.representation(using: .png, properties: [:])
    }
}
