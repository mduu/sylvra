import AppKit

/// The combination of connected screens (laptop only, 34", 49", two 27"…), so window and column layouts can
/// be remembered per setup.
public struct DisplaySetup: Hashable, Sendable {
    /// One screen: its name and size in points (not its position, so rearranging screens is the same setup).
    public struct Display: Hashable, Sendable, Comparable {
        public let name: String
        public let width: Int
        public let height: Int

        public init(name: String, width: Int, height: Int) {
            self.name = name
            self.width = width
            self.height = height
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.name, lhs.width, lhs.height) < (rhs.name, rhs.width, rhs.height)
        }
    }

    /// Sorted, so the order macOS lists the screens in doesn't matter.
    public let displays: [Display]

    public init(displays: [Display]) {
        self.displays = displays.sorted()
    }

    /// Stable and readable (it is part of UserDefaults keys), e.g. `Built-in Retina Display 1512x982`.
    public var key: String {
        displays.map { "\($0.name) \($0.width)x\($0.height)" }.joined(separator: " + ")
    }

    /// The screens connected right now.
    @MainActor public static var current: DisplaySetup {
        DisplaySetup(
            displays: NSScreen.screens.map {
                Display(
                    name: $0.localizedName, width: Int($0.frame.width.rounded()),
                    height: Int($0.frame.height.rounded()))
            })
    }
}

/// Layout values (column widths, window layout, window frames) stored per `DisplaySetup` in UserDefaults.
///
/// Numbers fall back to the value last saved in any setup, so a new setup starts like the last one; text
/// values (layout mode, window frames) only exist per setup.
public struct DisplayLayoutMemory {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(_ name: String, setup: DisplaySetup) -> String { "layout.setup.\(setup.key).\(name)" }

    /// Also the key the values had before they were stored per setup.
    static func lastKey(_ name: String) -> String { "layout.\(name)" }

    public func number(_ name: String, for setup: DisplaySetup) -> Double? {
        let value =
            defaults.object(forKey: Self.key(name, setup: setup)) as? Double
            ?? defaults.object(forKey: Self.lastKey(name)) as? Double
        return value.flatMap { $0 > 0 ? $0 : nil }
    }

    public func setNumber(_ value: Double, _ name: String, for setup: DisplaySetup) {
        defaults.set(value, forKey: Self.key(name, setup: setup))
        defaults.set(value, forKey: Self.lastKey(name))
    }

    public func text(_ name: String, for setup: DisplaySetup) -> String? {
        defaults.string(forKey: Self.key(name, setup: setup))
    }

    public func setText(_ value: String, _ name: String, for setup: DisplaySetup) {
        defaults.set(value, forKey: Self.key(name, setup: setup))
    }
}
