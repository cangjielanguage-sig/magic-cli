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
                case Some(config) => match (config.serverType) {
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

    private func parseArgsAndEnv(parts: Array<String>, startIndex!: Int64): (Array<String>, Array<(String, String)>) {
        let args = ArrayList<String>()
        let envVars = ArrayList<(String, String)>()

        var foundEnv = false
        for (i in startIndex..parts.size) {
            if (parts[i] == "--env") {
                foundEnv = true
                continue
            }

            if (foundEnv) {
                // Parse environment variable KEY=VALUE
                if (let Some(eqIndex) <- parts[i].indexOf("=")) {
                    let runes = parts[i].toRuneArray()
                    let keyRunes = Array<Rune>(Int64(eqIndex), {idx => runes[idx]})
                    let valueRunes = Array<Rune>(runes.size - Int64(eqIndex) - 1, {idx => runes[idx + Int64(eqIndex) + 1]})
                    let key = String(keyRunes)
                    let value = String(valueRunes)
                    envVars.add((key, value))
                }
            } else {
                args.add(parts[i])
            }
        }

        return (args.toArray(), envVars.toArray())
    }

    public func handleCommand(parts: Array<String>, agent: ConversationAgent): Unit {
        if (parts.size == 1) {
            // Just "/mcp" or "mcp" - show current loaded tools
            showLoadedMCPTools(agent)
            return
        }
        // parts[1] is add or remove mcp server command
        match (parts[1]) {
            case "add" =>
                if (parts.size < 4) {
                    println("Usage: /mcp add <name> <command> [args...] [--env KEY=VALUE ...]")
                    println("Example: /mcp add myserver npx @some/mcp-server")
                    println("Example: /mcp add myserver uvx myserver-mcp --env ENV_API_KEY=your_key")
                    return
                }
                let (args, envVars) = this.parseArgsAndEnv(parts, startIndex: 4)
                // parts[2] is server name, parts[3] is command
                addStdioServer(parts[2], parts[3], args, envVars)
            case "add-sse" =>
                if (parts.size != 4) {
                    println("Usage: /mcp add-sse <name> <url>")
                    println("Example: /mcp add-sse myserver http://localhost:3000/sse")
                    return
                }
                // parts[2] is server name, parts[3] is url
                addSseServer(parts[2], parts[3])
            case "remove" =>
                if (parts.size != 3) {
                    println("Usage: /mcp remove <name>")
                    println("Example: /mcp remove myserver")
                    return
                }
                // parts[2] is server name
                removeServer(parts[2])
            case _ =>
                println("Unknown MCP command: ${parts[1]}")
                println("Available commands:")
                println("  add      - Add a new stdio MCP server")
                println("  add-sse  - Add a new SSE MCP server")
                println("  remove   - Remove an existing MCP server")
        }
    }

    /**
     * Add SSE type MCP server
     */
    public func addSseServer(name: String, url: String): Bool {
        try {
            println("🔧 Adding SSE MCP server '${name}' with URL '${url}'")

            let (config, mcpServers) = loadMcpServersConfig()

            if (serverExists(mcpServers, name)) {
                println("❌ MCP server '${name}' already exists. Use '/mcp remove ${name}' first to replace it.")
                return false
            }

            // Create SSE server configuration
            let serverConfig = JsonObject()
            serverConfig.put("url", JsonString(url))

            // Add to mcpServers
            mcpServers.put(name, serverConfig)

            // Save configuration
            if (saveConfig(config)) {
                println("✅ Added SSE MCP server: ${name}")
                println("   URL: ${url}")
                println("Note: Restart the CLI to load the new SSE MCP server")
                return true
            }
            return false
        } catch (ex: Exception) {
            LogUtils.error("Failed to add SSE MCP server '${name}': ${ex}")
            println("❌ Failed to add SSE MCP server: ${ex.message}")
            return false
        }
    }

    /**
     * Add stdio type MCP server
     */
    public func addStdioServer(name: String, command: String, args: Array<String>, env: Array<(String, String)>): Bool {
        try {
            println("🔧 Adding stdio MCP server '${name}' with command '${command}'")

            let (config, mcpServers) = loadMcpServersConfig()

            if (serverExists(mcpServers, name)) {
                println("❌ MCP server '${name}' already exists. Use '/mcp remove ${name}' first to replace it.")
                return false
            }

            // Create stdio server configuration
            let serverConfig = JsonObject()
            serverConfig.put("command", JsonString(command))

            // Add args
            if (!args.isEmpty()) {
                let argsArray = JsonArray()
                for (arg in args) {
                    argsArray.add(JsonString(arg))
                }
                serverConfig.put("args", argsArray)
            }

            // Add env
            if (!env.isEmpty()) {
                let envObject = JsonObject()
                for ((key, value) in env) {
                    envObject.put(key, JsonString(value))
                }
                serverConfig.put("env", envObject)
            }

            mcpServers.put(name, serverConfig)

            if (saveConfig(config)) {
                println("✅ Added stdio MCP server: ${name}")
                println("   Command: ${command}")
                if (!args.isEmpty()) {
                    println("   Args: ${String.join(args, delimiter: " ")}")
                }
                if (!env.isEmpty()) {
                    println("   Env vars: ${env.size} variables")
                    for ((key, value) in env) {
                        println("     ${key}=${value}")
                    }
                }
                println("Note: Restart the CLI to load the new MCP server")
                return true
            }
            return false
        } catch (ex: Exception) {
            LogUtils.error("Failed to add stdio MCP server '${name}': ${ex}")
            println("❌ Failed to add stdio MCP server: ${ex.message}")
            return false
        }
    }

    /**
     * Remove an existing MCP server configuration
     */
    public func removeServer(name: String): Bool {
        try {
            println("🔧 Removing MCP server '${name}'")

            if (!exists(configPath)) {
                println("❌ No MCP servers configured")
                return false
            }

            let (config, mcpServers) = loadMcpServersConfig()

            // Check if server exists
            if (!serverExists(mcpServers, name)) {
                println("❌ MCP server '${name}' not found")
                return false
            }

            // Create new mcpServers object without the target server
            let newMcpServers = JsonObject()
            for ((serverName, serverConfig) in mcpServers.getFields()) {
                if (serverName != name) {
                    newMcpServers.put(serverName, serverConfig)
                }
            }

            // Update config
            config.put("mcpServers", newMcpServers)

            if (saveConfig(config)) {
                println("✅ Removed MCP server: ${name}")
                println("Note: Restart the CLI to unload the removed MCP server")
                return true
            }
            return false
        } catch (ex: Exception) {
            LogUtils.error("Failed to remove MCP server '${name}': ${ex}")
            println("❌ Failed to remove MCP server: ${ex.message}")
            return false
        }
    }

    private func loadMcpServersConfig(): (JsonObject, JsonObject) {
        let config = if (exists(configPath)) {
            try {
                let content = this.loadJsonFile(configPath)
                let jsonValue = JsonValue.fromStr(content)
                jsonValue.asObject()
            } catch (ex: Exception) {
                LogUtils.error("Failed to parse existing config: ${ex}")
                let newConfig = JsonObject()
                newConfig.put("mcpServers", JsonObject())
                newConfig
            }
        } else {
            let newConfig = JsonObject()
            newConfig.put("mcpServers", JsonObject())
            newConfig
        }

        let mcpServers = if (let Some(mcpServersValue) <- config.get("mcpServers")) {
            try {
                mcpServersValue.asObject()
            } catch (ex: Exception) {
                LogUtils.error("Failed to parse mcpServers object: ${ex}")
                let newMcpServers = JsonObject()
                config.put("mcpServers", newMcpServers)
                newMcpServers
            }
        } else {
            let newMcpServers = JsonObject()
            config.put("mcpServers", newMcpServers)
            newMcpServers
        }

        return (config, mcpServers)
    }

    /**
     * Check if a server with given name exists
     */
    private func serverExists(mcpServers: JsonObject, name: String): Bool {
        for ((serverName, _) in mcpServers.getFields()) {
            if (serverName == name) {
                return true
            }
        }
        return false
    }

    /**
     * Save configuration to file
     */
    private func saveConfig(config: JsonObject): Bool {
        try {
            let jsonStr = config.toJsonValue().toJsonString()
            File.writeTo(configPath, jsonStr.toArray())
            return true
        } catch (ex: Exception) {
            LogUtils.error("Failed to save config: ${ex}")
            return false
        }
    }
}
