import SwiftUI

/// "Tools ▸ …" submenu for context menus and toolbar menus (pure). Renders nothing without tools.
public struct CustomToolsMenu: View {
    private let tools: [CustomTool]
    private let run: (CustomTool) -> Void

    public init(tools: [CustomTool], run: @escaping (CustomTool) -> Void) {
        self.tools = tools
        self.run = run
    }

    public var body: some View {
        if !tools.isEmpty {
            Menu {
                CustomToolsMenuItems(tools: tools, run: run)
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
            }
        }
    }
}

/// The tool buttons themselves, for menus that already are the "Tools" menu (pure).
public struct CustomToolsMenuItems: View {
    private let tools: [CustomTool]
    private let run: (CustomTool) -> Void

    public init(tools: [CustomTool], run: @escaping (CustomTool) -> Void) {
        self.tools = tools
        self.run = run
    }

    public var body: some View {
        ForEach(tools) { tool in
            Button(tool.name) { run(tool) }
        }
    }
}

#Preview {
    Menu("Context") {
        CustomToolsMenu(tools: CustomTool.examples) { _ in }
    }
    .padding()
}
