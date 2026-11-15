// Prints the window number(s) of the given app's normal windows (used by screenshot.sh).
import CoreGraphics

let owner = CommandLine.arguments.dropFirst().first ?? "Sylvra"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == owner {
    if window[kCGWindowLayer as String] as? Int == 0, let number = window[kCGWindowNumber as String] {
        print(number)
    }
}
