// Prints the window number(s) of a process's normal windows (used by screenshot.sh).
//   window-id <pid>   or   window-id <app name>
import CoreGraphics

let target = CommandLine.arguments.dropFirst().first ?? "Sylvra"
let pid = Int32(target)
/// Normal windows of the target; with `options` `.optionAll` also those on another Space (still capturable).
func windows(_ options: CGWindowListOption) -> [[String: Any]] {
    let all = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    return all.filter { window in
        let matches =
            pid.map { window[kCGWindowOwnerPID as String] as? Int32 == $0 }
            ?? (window[kCGWindowOwnerName as String] as? String == target)
        return matches && window[kCGWindowLayer as String] as? Int == 0
    }
}

func area(_ window: [String: Any]) -> Double {
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    return (bounds["Width"] as? Double ?? 0) * (bounds["Height"] as? Double ?? 0)
}

// Visible windows first; otherwise the largest (the main window) wherever it is.
let visible = windows([.optionOnScreenOnly])
for window in visible.isEmpty ? windows([.optionAll]).sorted(by: { area($0) > area($1) }) : visible {
    if let number = window[kCGWindowNumber as String] { print(number) }
}
