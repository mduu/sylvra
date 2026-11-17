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
        // The review window of the two-window layout exists in the background in every layout; skip it.
        let isReviewWindow = window[kCGWindowName as String] as? String == "Sylvra Review"
        return matches && window[kCGWindowLayer as String] as? Int == 0 && !isReviewWindow
    }
}

func number(_ window: [String: Any]) -> Int { window[kCGWindowNumber as String] as? Int ?? .max }

// Visible windows first, otherwise any (e.g. on another Space). The main window is created first, so
// the lowest number wins over the review window when its name isn't set yet.
let visible = windows([.optionOnScreenOnly])
let candidates = visible.isEmpty ? windows([.optionAll]) : visible
for window in candidates.sorted(by: { number($0) < number($1) }) {
    print(number(window))
}
