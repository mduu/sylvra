import Foundation
import OSLog
import Observation
import Platform

/// The user's custom tools, persisted as JSON in UserDefaults.
@MainActor
@Observable
public final class CustomToolStore {
    public static let storageKey = "customTools.tools"

    public private(set) var tools: [CustomTool]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = SylvraLog.logger("customTools")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                tools = try JSONDecoder().decode([CustomTool].self, from: data)
            } catch {
                tools = CustomTool.examples
                logger.error("Could not decode custom tools: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            tools = CustomTool.examples
        }
    }

    public func tools(for scope: CustomTool.Scope) -> [CustomTool] {
        tools.filter { $0.scope == scope }
    }

    /// Adds `tool` or replaces the tool with the same id.
    public func save(_ tool: CustomTool) {
        if let index = tools.firstIndex(where: { $0.id == tool.id }) {
            tools[index] = tool
        } else {
            tools.append(tool)
        }
        persist()
    }

    public func delete(_ id: CustomTool.ID) {
        tools.removeAll { $0.id == id }
        persist()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        tools.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(tools), forKey: Self.storageKey)
        } catch {
            logger.error("Could not save custom tools: \(error.localizedDescription, privacy: .public)")
        }
    }
}
