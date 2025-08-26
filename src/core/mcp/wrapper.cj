package cli.core.mcp

import magic.core.tool.*
import magic.jsonable.TypeSchema

import cli.utils.PrintUtils

import std.collection.{HashMap, map, collectArray}
import stdx.encoding.json.JsonValue

/**
 * Wrap tools from MCP servers to print execution info
 */
protected class MCPToolWrapper <: Tool {
    private let serverName: String

    private let mcpTool: Tool

    public init(serverName: String, mcpTool: Tool) {
        this.serverName = serverName
        this.mcpTool = mcpTool
    }

    public prop name: String {
        get() { this.mcpTool.name }
    }

    public prop description: String {
        get() { this.mcpTool.description }
    }

    public prop parameters: Array<ToolParameter> {
        get() { this.mcpTool.parameters }
    }

    public prop retType: TypeSchema {
        get() { this.mcpTool.retType }
    }

    public prop examples: Array<String> {
        get() { this.mcpTool.examples }
    }

    public prop extra: HashMap<String, String> {
        get() { this.mcpTool.extra }
    }

    override public func invoke(args: HashMap<String, JsonValue>): ToolResponse {
        let message = String.join(
            args.iterator() |> map { kv => "${kv[0]}: ${kv[1]}" } |> collectArray,
            delimiter: "\n"
        )
        PrintUtils.printTool("📦 MCP Server: ${this.serverName} | 🔧 ${this.mcpTool.name}", message)
        return this.mcpTool.invoke(args)
    }

    override public func toJsonValue(): JsonValue {
        this.mcpTool.toJsonValue()
    }
}