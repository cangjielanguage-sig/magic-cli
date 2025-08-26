package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.agent.ConversationAgent
import magic.interaction.ConsolePrinter
import magic.log.LogUtils
import magic.core.message.Conversation

import cli.core.agents.{CodeAgent, Compactor}
import cli.core.config.CliConfig
import cli.core.mcp.MCPConfigManager
import cli.utils.{InputUtils, PrintUtils}

import std.argopt.{parseArguments, ArgumentSpec, ArgumentMode, ArgumentParseException}
import std.fs.{exists, File, FSException, Path}
import std.regex.Regex
import std.env.atExit

private func printHelp(): Unit {
    println("Magic Cli")
    println("  --auto             The agent runs autonomously")
    println("  --model <model>   Set the chat model")
    println("  --help, -h        Print this help message")
}

/**
 * Parse the command line arguments
 */
private func parseArgs(args: Array<String>): Bool {
    let argSpecs = [
        Long("auto", NoValue),
        Long("model", RequiredValue),
        Full("help", r"h", NoValue)
    ]
    let result = try {
        parseArguments(args, argSpecs)
    } catch (ex: ArgumentParseException) {
        println(ex.message)
        return false
    }
    if (result.options.contains("help") || result.options.contains("h")) {
        return false
    }
    if (result.options.contains("auto")) {
        CliConfig.auto = true
    }
    if (let Some(model) <- result.options.get("model")) {
        CliConfig.model = model
    }
    return true
}

private func loadEnvFile(): Unit {
    let path = Path("./.env")
    if (!exists(path)) {
        return
    }
    try {
        let content = String.fromUtf8(File.readFrom(path))
        let regex = Regex("^\\s*([\\w.]+)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^#]*)\\s*(?:#.*)?$")
        for (line in content.split("\n")) {
            if (let Some(md) <- regex.find(line, group: true)) {
                let key = md.matchString(1)
                var value = md.matchString(2)
                // strip quote marks if necessary
                if (value.startsWith('"')) {
                    value = value.replace('"', "")
                } else if (value.startsWith("'")) {
                    value = value.replace("'", "")
                }
                LogUtils.info("[ENV Set] ${key}=${value}")
                Config.env[key] = value
            }
        }
    } catch (e: Exception) {
        LogUtils.error("Failed to read .env file")
    }
}

private func setConfig(): Unit {
    Config.logFile = CliConfig.logFile.toString()
    Config.logLevel = "INFO"
    Config.modelRequestDir = CliConfig.dotDir.join("model-requests").toString()
    Config.enableFunctionCall = true
    let magicPath = Path(Config.env['MAGIC_PATH'].getOrThrow({=> Exception("MAGIC_PATH not set")}))
    Config.resourceDir = magicPath.join("resource").toString()
    // Set your API key in the .env file
    loadEnvFile()
}

main(args: Array<String>): Int64 {
    if (!parseArgs(args)) {
        printHelp()
        return 0
    }
    setConfig()
    PrintUtils.printWelcome()

    // Load previous conversation if necessary
    let savedConversation: Option<Conversation> = if (exists(CliConfig.conversationFile)) {
        Conversation.load(CliConfig.conversationFile)
    } else {
        None
    }
    let agent = ConversationAgent(CodeAgent(), conversation: savedConversation)

    // Register the callback to save conversation
    atExit({ =>
        agent.conversation.save(CliConfig.conversationFile)
    })

    // Load MCP servers and add their tools to the agent
    let mcpManager = MCPConfigManager()
    agent.toolManager.addTools(mcpManager.loadMCPServers())

    // Initialize the conversation compactor to use
    let compactor = Compactor()

    // Start the event loop
    while (true) {
        let input = InputUtils.getUserInput()
        match (input) {
            case "/exit" | "exit" =>
                PrintUtils.printExitMessage()
                break
            case "/help" | "help" =>
                PrintUtils.printHelpMessage()
            case "/clear" | "clear" =>
                PrintUtils.clearScreen()
                PrintUtils.printLogo()
            case "/compact" | "compact" =>
                if (let Some(index) <- compactor.calculateCompactIndex(agent.conversation)) {
                    PrintUtils.printTool("Compacting conversation...", "🚀 Working on it...")
                    agent.conversation.compactBy(compactor, firstN: index, keepOrigin: false)
                    PrintUtils.printTool("Compacting conversation...", "🥳 Compacted successfully!")
                } else {
                    PrintUtils.printTool("Compacting conversation...", "🌱 Conversation context is still short, no need to compact!")
                }
            case "/mcp" | "mcp" =>
                mcpManager.showLoadedMCPTools(agent)
            case _ =>
                let response = agent.chat(AgentRequest(input))
                PrintUtils.printAgentResponse(response)
                if (let Some(index) <- compactor.calculateCompactIndex(agent.conversation)) {
                    PrintUtils.printTool("Compacting conversation...", "🚀 Working on it...")
                    agent.conversation.compactBy(compactor, firstN: index, keepOrigin: false)
                    PrintUtils.printTool("Compacting conversation...", "🥳 Compacted successfully!")
                }
        }
    }
    return 0
}
