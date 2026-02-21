import Foundation
import CoreGraphics

// MARK: - Tool Execution Context

struct ToolExecutionContext {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bounds: CGRect
    let retinaScale: CGFloat
    let windowTracker: WindowTracker
    let overlayManager: OverlayManager?

    @MainActor var targetContext: TargetContext {
        TargetContext(
            windowID: windowID,
            ownerPID: ownerPID,
            bounds: windowTracker.currentBounds(),
            retinaScale: retinaScale
        )
    }
}

// MARK: - Agent Tool Protocol

@MainActor
protocol AgentTool {
    var name: String { get }
    var definition: ToolDefinition { get }
    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock
}

// MARK: - Tool Registry

@MainActor
class ToolRegistry {
    private var tools: [String: AgentTool] = [:]

    func register(_ tool: AgentTool) {
        tools[tool.name] = tool
    }

    var definitions: [ToolDefinition] {
        tools.values.map { $0.definition }
    }

    func execute(name: String, input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        guard let tool = tools[name] else {
            return .toolResult(toolUseId: toolId, content: [.text("Unknown tool: \(name)")], isError: true)
        }
        return await tool.execute(input: input, toolId: toolId, context: context)
    }
}
