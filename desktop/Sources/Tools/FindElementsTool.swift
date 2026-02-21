import Foundation

struct FindElementsTool: AgentTool {
    let name = "find_elements"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
                Search the entire accessibility tree for elements matching a query. \
                Searches across role, title, description, value, and subrole fields (case-insensitive). \
                Use this to find specific UI elements like "Source Control", "git", "search", "close", etc. \
                Returns matching elements with their labels and frames. Much more effective than \
                dumping the full tree — use this first when looking for a specific element.
                """,
            inputSchema: ToolSchema(
                properties: [
                    "query": ToolProperty(type: "string", description: "Search term to match against element labels, roles, and descriptions", enumValues: nil)
                ],
                required: ["query"]
            )
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        guard let query = input["query"]?.stringValue, !query.isEmpty else {
            return .toolResult(toolUseId: toolId, content: [.text("Missing required 'query' parameter")], isError: true)
        }

        guard let tree = ActiveAppState.shared.contextTree else {
            return .toolResult(toolUseId: toolId, content: [.text("No accessibility tree available")], isError: true)
        }

        let matches = tree.search(query: query)

        if matches.isEmpty {
            return .toolResult(toolUseId: toolId, content: [.text("No elements found matching '\(query)'. Try a different search term or a broader query.")], isError: false)
        }

        // Format results with index numbers for easy reference
        let items: [[String: Any]] = matches.prefix(30).enumerated().map { (index, node) in
            var item: [String: Any] = [
                "index": index + 1,
                "role": node.role
            ]
            if let t = node.title { item["title"] = t }
            if let d = node.description { item["description"] = d }
            if let rd = node.roleDescription { item["roleDescription"] = rd }
            if let v = node.value { item["value"] = v }
            if let sr = node.subrole { item["subrole"] = sr }
            if let f = node.frame {
                item["frame"] = ["x": Int(f.origin.x), "y": Int(f.origin.y), "w": Int(f.width), "h": Int(f.height)]
            }
            item["hasFrame"] = node.frame != nil
            return item
        }

        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]),
              let jsonString = String(data: data, encoding: .utf8)
        else {
            return .toolResult(toolUseId: toolId, content: [.text("Failed to serialize results")], isError: true)
        }

        let total = matches.count
        let shown = min(total, 30)
        let header = "Found \(total) elements matching '\(query)' (showing \(shown)):"
        return .toolResult(toolUseId: toolId, content: [.text("\(header)\n\(jsonString)")], isError: false)
    }
}
