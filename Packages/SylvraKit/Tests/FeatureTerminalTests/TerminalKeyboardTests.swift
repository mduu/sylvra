import AppKit
import SwiftTerm
import Testing

@testable import FeatureTerminal

/// Real key events through SwiftTerm's view, configured like Sylvra's sessions: what reaches the shell.
@MainActor
struct TerminalKeyboardTests {
    private final class Recorder: TerminalViewDelegate {
        var sent: [UInt8] = []
        func send(source: TerminalView, data: ArraySlice<UInt8>) { sent += data }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    // Device-dependent bits of the modifier flags (IOKit's NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK).
    private static let leftOption: UInt = 0x20
    private static let rightOption: UInt = 0x40

    private func view() -> (TerminalView, Recorder) {
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 240))
        let recorder = Recorder()
        view.terminalDelegate = recorder
        TerminalViewStore.configure(view)
        return (view, recorder)
    }

    private func key(
        _ characters: String, ignoringModifiers: String, code: UInt16, flags: NSEvent.ModifierFlags = [],
        device: UInt = 0
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: flags.rawValue | device), timestamp: 0,
                windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: ignoringModifiers, isARepeat: false, keyCode: code))
    }

    @Test func shiftEnterIsANewLineOnceClaudeCodeAsksForTheKittyKeyboard() throws {
        let (view, recorder) = view()
        // What Claude Code sends at start (seen in a PTY): push "disambiguate + alternate keys".
        view.feed(text: "\u{1b}[>5u")
        view.keyDown(with: try key("\r", ignoringModifiers: "\r", code: 36, flags: .shift))
        #expect(String(decoding: recorder.sent, as: UTF8.self) == "\u{1b}[13;2u")
    }

    @Test func leftOptionIsMeta() throws {
        let (view, recorder) = view()
        view.keyDown(with: try key("∫", ignoringModifiers: "b", code: 11, flags: .option, device: Self.leftOption))
        #expect(recorder.sent == [0x1b, UInt8(ascii: "b")])
    }

    @Test func rightOptionTypesTheLayoutsCharacter() throws {
        let (view, recorder) = view()
        // Right ⌥5 on the Swiss layout is "[".
        view.keyDown(with: try key("[", ignoringModifiers: "5", code: 23, flags: .option, device: Self.rightOption))
        #expect(String(decoding: recorder.sent, as: UTF8.self) == "[")
    }

    @Test func rightOptionArrowStillJumpsAWord() throws {
        let (view, recorder) = view()
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        view.keyDown(
            with: try key(
                left, ignoringModifiers: left, code: 123, flags: [.option, .numericPad, .function],
                device: Self.rightOption))
        #expect(recorder.sent.first == 0x1b)
    }
}
