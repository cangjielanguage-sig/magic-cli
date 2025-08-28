package cli.core.mcp

import magic.dsl.jsonable
import magic.mcp.{MCPClient, StdioMCPClient, SseMCPClient, StdioMCPInitParams, SseMCPInitParams}
import magic.log.LogUtils
import magic.core.tool.Tool
import magic.agent.ConversationAgent
import magic.jsonable.*

import cli.core.config.CliConfig
import cli.utils.*

import std.fs.{exists, File, Path}
import std.collection.{HashMap, ArrayList, filter, collectArray}
import std.env.getVariable
import stdx.encoding.json.*

@jsonable
private class Setting {
    let mcpServers: Option<JsonObject>
}

private enum MCPServerType {
    | Stdio(StdioMCPInitParams)
    | Sse(SseMCPInitParams)

    /**
     * Check and parse the server type from the initial parameters
     */
    static func parse(initParams: JsonObject): MCPServerType {
        if (let Some(_) <- initParams.get("url")) {
            return MCPServerType.Sse(SseMCPInitParams.fromJsonValue(initParams))
        } else {
            return MCPServerType.Stdio(StdioMCPInitParams.fromJsonValue(initParams))
        }
    }
}

private struct MCPServerConfig {
    public let name: String
    public let serverType: MCPServerType

    public init(name: String, serverType: MCPServerType) {
        this.name = name
        this.serverType = serverType
    }
}

public class MCPConfigManager {
    private let configPath: Path

    /**
     * Server name -> Server init configs
     */
    private var mcpServers: HashMap<String, MCPServerConfig> = HashMap<String, MCPServerConfig>()

    /**
     * Server name -> its client
     */
    private var mcpClients: HashMap<String, MCPClient> = HashMap<String, MCPClient>()

    public init() {
        this.configPath = CliConfig.dotDir.join("settings.json")
    }

    /**
     * Standard Json does not support comments,
     * we add // as Json comment.
     */
    private func loadJsonFile(path: Path): String {
        return String.join(
            String.fromUtf8(File.readFrom(configPath)).split("\n") |>
                filter { line => !line.trimAscii().startsWith("//") } |>
                collectArray,
            delimiter: "\n"
        )
    }

    private func loadMCPConfigs(): HashMap<String, MCPServerConfig> {
        let configs = HashMap<String, MCPServerConfig>()

        if (!exists(configPath)) {
            LogUtils.info("MCP config file not found at ${configPath}, skipping MCP server loading")
            return configs
        }

        try {
            let content = this.loadJsonFile(configPath)
            let jsonValue = JsonValue.fromStr(content)
            let setting = Setting.fromJsonValue(jsonValue)
            if (let Some(jo) <- setting.mcpServers) {
                for ((serverName, initParams) in jo.getFields()) {
                    if (let Some(config) <- this.parseServerConfig(serverName, initParams)) {
                        configs[serverName] = config
                    }
                }
            }
        } catch (ex: JsonableException) {
            LogUtils.info("mcpServers is not a valid JSON object")
        } catch (ex: JsonException) {
            LogUtils.info("Config file is not a valid JSON object")
        } catch (ex: Exception) {
            LogUtils.error("Failed to load MCP config: ${ex}")
        }

        return configs
    }

    private func parseServerConfig(serverName: String, serverInitParams: JsonValue): Option<MCPServerConfig> {
        try {
            let jo = serverInitParams.asObject()
            return MCPServerConfig(serverName, MCPServerType.parse(jo))
        } catch (ex: JsonException) {
            LogUtils.info("Invalid server config format for: ${serverName}")
            return None
        } catch (ex: JsonableException) {
            LogUtils.info("Invalid MCP server config: ${serverName}")
            return None
        }
    }

    public func loadMCPServers(): Array<Tool> {
        this.mcpServers = loadMCPConfigs()
        let clients = ArrayList<MCPClient>()
        let tools = ArrayList<Tool>()

        for ((serverName, config) in this.mcpServers) {
            let client: MCPClient = match (config.serverType) {
                case Stdio(initParam) =>
                    var fullCommand = initParam.command
                    if (!initParam.args.isEmpty()) {
                        fullCommand = "${initParam.command} ${String.join(initParam.args, delimiter: " ")}"
                    }
                    // Windows use cmd /c to wrap the command
                    let finalCommand = if (InfoUtils.os == "windows") {
                        "cmd /c \"${fullCommand}\""
                    } else {
                        fullCommand
                    }
                    LogUtils.info("Creating Stdio MCP client for ${serverName} with command: ${finalCommand}")
                    StdioMCPClient(finalCommand, env: initParam.env.toArray())
                case Sse(initParam) =>
                    LogUtils.info("Creating SSE MCP client for ${serverName} with URL: ${initParam.url}")
                    SseMCPClient(initParam.url)
            }

            clients.add(client)
            for (tool in client.tools) {
                tools.add(MCPToolWrapper(serverName, tool))
            }
            this.mcpClients[serverName] = client
            LogUtils.info("Successfully loaded SSE MCP server: ${serverName}")
        }

        return tools.toArray()
    }

    public func showLoadedMCPTools(agent: ConversationAgent): Unit {
        PrintUtils.printTool("MCP Servers and Tools", "🔌Total MCP tools loaded: ")

        if (this.mcpClients.isEmpty()) {
            println("No MCP servers currently loaded")
            return
        }

        var totalMcpTools = 0
        for ((serverName, client) in this.mcpClients) {
            let serverType = match (this.mcpServers.get(serverName)) {
                case Some(config) =>
                    match (config.serverType) {
                        case Stdio(_) => "Stdio"
                        case Sse(_) => "SSE"
                    }
                case _ => "Unknown"
            }

            let tools = client.tools
            println("📡 ${serverName} (${serverType}) - ${tools.size} tools:")
            for (tool in tools) {
                println("  • ${tool.name}")
            }
            totalMcpTools += tools.size
            println("")
        }

        println("Total MCP tools: ${totalMcpTools}")
    }
}
