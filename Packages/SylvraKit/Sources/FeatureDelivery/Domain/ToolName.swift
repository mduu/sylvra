import Foundation

/// Agent tool names as people read them: `mcp__datadog__analyze_datadog_logs` → "datadog · analyze_datadog_logs".
enum ToolName {
    static func short(_ name: String) -> String {
        guard name.hasPrefix("mcp__") else { return name }
        let parts = name.dropFirst(5).components(separatedBy: "__")
        guard parts.count >= 2 else { return String(name.dropFirst(5)) }
        let server = parts[0].replacingOccurrences(of: "plugin_", with: "").replacingOccurrences(
            of: "claude_ai_", with: "")
        return "\(server) · \(parts.dropFirst().joined(separator: "__"))"
    }
}
