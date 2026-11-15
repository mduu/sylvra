// Prints the window number(s) of a process's normal windows (used by screenshot.sh).
//   window-id <pid>   or   window-id <app name>
import CoreGraphics

let target = CommandLine.arguments.dropFirst().first ?? "Sylvra"
let pid = Int32(target)
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    let matches =
        pid.map { window[kCGWindowOwnerPID as String] as? Int32 == $0 }
        ?? (window[kCGWindowOwnerName as String] as? String == target)
    if matches, window[kCGWindowLayer as String] as? Int == 0, let number = window[kCGWindowNumber as String] {
        print(number)
    }
}
