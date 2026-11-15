/// One file in the AI-suggested reading order of a pull request.
public struct ReadingStep: Hashable, Sendable, Codable {
    public let path: String
    /// Why to read it at this point ("core change", "risky: rounding").
    public let reason: String
    /// Marked as a risky area by the agent.
    public let isRisky: Bool

    public init(path: String, reason: String, isRisky: Bool = false) {
        self.path = path
        self.reason = reason
        self.isRisky = isRisky
    }
}
