import Foundation

/// An AI highlight on new-side lines (see specs/ux.md §7.3). Set by the app from AI findings.
public struct LineHighlight: Hashable, Sendable {
    public let path: String
    public let lines: ClosedRange<Int>
    /// 0…1, scales the gradient opacity (e.g. by severity).
    public let intensity: Double
    public let isSelected: Bool

    public init(path: String, lines: ClosedRange<Int>, intensity: Double, isSelected: Bool) {
        self.path = path
        self.lines = lines
        self.intensity = intensity
        self.isSelected = isSelected
    }
}
