import AppKit
import Testing

@testable import FeatureTerminal

struct TerminalPasteFilesTests {
    @Test func pathsAreEscapedLikeTerminalApp() {
        #expect(
            TerminalPasteFiles.text(for: ["/Users/me/Screen Shot (1).png", "/tmp/a&b"])
                == #"/Users/me/Screen\ Shot\ \(1\).png /tmp/a\&b"#)
    }

    @Test func savesImagesAndRemovesOldOnes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "paste-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try TerminalPasteFiles.save(png: Data([1, 2, 3]), in: directory)
        let old = Date.now.addingTimeInterval(-2 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: first.path)
        let second = try TerminalPasteFiles.save(png: Data([4]), in: directory)
        #expect(second.pathExtension == "png")
        #expect(try Data(contentsOf: second) == Data([4]))
        #expect(!FileManager.default.fileExists(atPath: first.path))
    }
}

/// Drops on the terminal view, through a private pasteboard (never the user's clipboard).
@MainActor
struct TerminalDropTests {
    private func pasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("sylvra-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    @Test func droppedFilesGiveTheirPaths() {
        let board = pasteboard()
        board.writeObjects([URL(fileURLWithPath: "/tmp/a.png") as NSURL, URL(fileURLWithPath: "/tmp/b c.txt") as NSURL])
        let view = SylvraTerminalView(frame: .zero)
        #expect(view.paths(from: board) == ["/tmp/a.png", "/tmp/b c.txt"])
    }

    @Test func aDroppedImageBecomesAFile() throws {
        let board = pasteboard()
        let image = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        board.setData(try #require(image?.tiffRepresentation), forType: .tiff)
        let paths = SylvraTerminalView(frame: .zero).paths(from: board)
        let path = try #require(paths.first)
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(path.hasSuffix(".png"))
        #expect(path.hasPrefix(TerminalPasteFiles.directory.path))
        #expect(NSImage(contentsOfFile: path) != nil)
    }

    @Test func textIsNoImage() {
        let board = pasteboard()
        board.setString("hello", forType: .string)
        #expect(SylvraTerminalView(frame: .zero).paths(from: board).isEmpty)
    }
}
