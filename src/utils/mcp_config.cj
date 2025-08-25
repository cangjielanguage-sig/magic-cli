package cli.utils

import std.fs.{exists, File, Path}
import std.collection.{HashMap, ArrayList}
import stdx.encoding.json.*
import std.env.getVariable

import magic.mcp.{StdioMCPClient, SseMCPClient}
import magic.log.LogUtils
import magic.agent.ConversationAgent

import cli.core.config.CliConfig

public enum MCPServerType {
    | StdioType(String, Array<String>, HashMap<String, String>)
    | SseType(String)
}

public struct MCPServerConfig {
    public let name: String
    public let serverType: MCPServerType
    
    public init(name: String, serverType: MCPServerType) {
        this.name = name
        this.serverType = serverType
    }
}

public class MCPConfigManager {
    private let configPath: Path
    private var loadedServers: HashMap<String, MCPServerConfig> = HashMap<String, MCPServerConfig>()
    private var serverTools: HashMap<String, Array<String>> = HashMap<String, Array<String>>()
    
    public init() {
        this.configPath = CliConfig.dotDir.join("settings.json")
    }
    
    public func loadMCPConfigs(): HashMap<String, MCPServerConfig> {
        let configs = HashMap<String, MCPServerConfig>()
        
        if (!exists(configPath)) {
            LogUtils.info("MCP config file not found at ${configPath}, skipping MCP server loading")
            return configs
        }
        
        try {
            let content = String.fromUtf8(File.readFrom(configPath))
            let jsonValue = JsonValue.fromStr(content)
            
            match (jsonValue.kind()) {
                case JsonKind.JsObject =>
                    let rootObj = jsonValue.asObject()
                    match (rootObj.get("mcpServers")) {
                        case Some(mcpServersValue) =>
                            match (mcpServersValue.kind()) {
                                case JsonKind.JsObject =>
                                    let mcpServersObj = mcpServersValue.asObject()
                                    for ((serverName, serverValue) in mcpServersObj.getFields()) {
                                        this.parseServerConfig(serverValue, serverName, configs)
                                    }
                                case _ =>
                                    LogUtils.info("mcpServers is not a valid JSON object")
                            }
                        case _ =>
                            LogUtils.info("No mcpServers found in config")
                    }
                case _ =>
                    LogUtils.info("Config file is not a valid JSON object")
            }
        } catch (e: Exception) {
            LogUtils.error("Failed to load MCP config: ${e}")
        }
        
        return configs
    }
    
    private func parseServerConfig(serverValue: JsonValue, serverName: String, configs: HashMap<String, MCPServerConfig>): Unit {
        match (serverValue.kind()) {
            case JsonKind.JsObject =>
                let serverConfigObj = serverValue.asObject()
                
                match (serverConfigObj.get("url")) {
                    case Some(urlValue) =>
                        match (urlValue.kind()) {
                            case JsonKind.JsString =>
                                let url = urlValue.asString().getValue()
                                let serverType = SseType(url)
                                configs[serverName] = MCPServerConfig(serverName, serverType)
                                LogUtils.info("Loaded SSE MCP server config: ${serverName}")
                                return
                            case _ => ()
                        }
                    case _ => ()
                }
                
                var command = ""
                var args = Array<String>()
                var env = HashMap<String, String>()
                
                match (serverConfigObj.get("command")) {
                    case Some(cmdValue) =>
                        match (cmdValue.kind()) {
                            case JsonKind.JsString =>
                                command = cmdValue.asString().getValue()
                            case _ => ()
                        }
                    case _ => ()
                }
                
                match (serverConfigObj.get("args")) {
                    case Some(argsValue) =>
                        match (argsValue.kind()) {
                            case JsonKind.JsArray =>
                                let argsArray = argsValue.asArray()
                                let argsList = ArrayList<String>()
                                for (argValue in argsArray.getItems()) {
                                    match (argValue.kind()) {
                                        case JsonKind.JsString =>
                                            argsList.add(argValue.asString().getValue())
                                        case _ => ()
                                    }
                                }
                                args = argsList.toArray()
                            case _ => ()
                        }
                    case _ => ()
                }
                
                match (serverConfigObj.get("env")) {
                    case Some(envValue) =>
                        match (envValue.kind()) {
                            case JsonKind.JsArray =>
                                let envArray = envValue.asArray()
                                for (pairValue in envArray.getItems()) {
                                    match (pairValue.kind()) {
                                        case JsonKind.JsArray =>
                                            let pairArray = pairValue.asArray()
                                            if (pairArray.size() >= 2) {
                                                let items = pairArray.getItems()
                                                match (items[0].kind()) {
                                                    case JsonKind.JsString =>
                                                        match (items[1].kind()) {
                                                            case JsonKind.JsString =>
                                                                let key = items[0].asString().getValue()
                                                                let value = items[1].asString().getValue()
                                                                env[key] = value
                                                            case _ => ()
                                                        }
                                                    case _ => ()
                                                }
                                            }
                                        case _ => ()
                                    }
                                }
                            case JsonKind.JsObject =>
                                let envObj = envValue.asObject()
                                for ((key, value) in envObj.getFields()) {
                                    match (value.kind()) {
                                        case JsonKind.JsString =>
                                            env[key] = value.asString().getValue()
                                        case _ => ()
                                    }
                                }
                            case _ => ()
                        }
                    case _ => ()
                }
                
                if (!command.isEmpty()) {
                    let serverType = StdioType(command, args, env)
                    configs[serverName] = MCPServerConfig(serverName, serverType)
                    LogUtils.info("Loaded Stdio MCP server config: ${serverName}")
                } else {
                    LogUtils.info("Invalid MCP server config: ${serverName} - missing command or url")
                }
                
            case _ =>
                LogUtils.info("Invalid server config format for: ${serverName}")
        }
    }

    public func loadMCPServersForAgent(agent: ConversationAgent): Unit {
        let configs = loadMCPConfigs()
        this.loadedServers = configs
        
        for ((serverName, config) in configs) {
            try {
                match (config.serverType) {
                    case StdioType(command, args, env) =>
                        var fullCommand = command
                        if (!args.isEmpty()) {
                            fullCommand = "${command} ${String.join(args, delimiter: " ")}"
                        }
                        
                        // Windows use cmd /c to wrap command
                        let osName = getVariable("OS") ?? "Unknown"
                        let isWindows = osName.toAsciiLower().contains("windows")
                        
                        let finalCommand = if (isWindows) {
                            "cmd /c \"${fullCommand}\""
                        } else {
                            fullCommand
                        }
                        
                        let envArray = ArrayList<(String, String)>()
                        for ((key, value) in env) {
                            envArray.add((key, value))
                        }
                        
                        LogUtils.info("Creating Stdio MCP client for ${serverName} with command: ${finalCommand}")
                        let mcpClient = StdioMCPClient(finalCommand, env: envArray.toArray())
                        agent.toolManager.addTools(mcpClient.tools)
                        
                        let toolNames = ArrayList<String>()
                        for (tool in mcpClient.tools) {
                            toolNames.add(tool.name)
                        }
                        this.serverTools[serverName] = toolNames.toArray()
                        
                        LogUtils.info("Successfully loaded Stdio MCP server: ${serverName}")
                        
                    case SseType(url) =>
                        LogUtils.info("Creating SSE MCP client for ${serverName} with URL: ${url}")
                        let mcpClient = SseMCPClient(url)
                        agent.toolManager.addTools(mcpClient.tools)
                        
                        let toolNames = ArrayList<String>()
                        for (tool in mcpClient.tools) {
                            toolNames.add(tool.name)
                        }
                        this.serverTools[serverName] = toolNames.toArray()
                        
                        LogUtils.info("Successfully loaded SSE MCP server: ${serverName}")
                }
                
            } catch (e: Exception) {
                LogUtils.error("Failed to create MCP client for ${serverName}: ${e}")
            }
        }
    }
    
    public func showLoadedMCPTools(agent: ConversationAgent): Unit {
        PrintUtils.printTool("MCP Servers and Tools", "🔌Total MCP tools loaded: ")
        
        if (this.serverTools.isEmpty()) {
            println("No MCP servers currently loaded")
            return
        }
        
        var totalMcpTools = 0
        for ((serverName, toolNames) in this.serverTools) {
            if (!toolNames.isEmpty()) {
                let serverType = match (this.loadedServers.get(serverName)) {
                    case Some(config) =>
                        match (config.serverType) {
                            case StdioType(_, _, _) => "Stdio"
                            case SseType(_) => "SSE"
                        }
                    case _ => "Unknown"
                }
                
                println("📡 ${serverName} (${serverType}) - ${toolNames.size} tools:")
                for (toolName in toolNames) {
                    println("  • ${toolName}")
                }
                totalMcpTools += toolNames.size
                println("")
            }
        }
        
        println("Total MCP tools: ${totalMcpTools}")
    }
}
