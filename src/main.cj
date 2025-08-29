package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.agent.ConversationAgent
import magic.interaction.ConsolePrinter
import magic.log.LogUtils
import magic.core.message.Conversation
import magic.core.interaction.EventResponse
import magic.interaction.{EventHandlerManager, PromptValidateEvent, ToolCallEvent}
import cli.core.agents.{GeneralCodeAgent, CangjieCodeAgent, Compactor}
import cli.core.config.CliConfig
import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.context.*
import cli.bean.CliMode
import cli.utils.*
import std.collection.ArrayList
import std.argopt.{parseArguments, ArgumentSpec, ArgumentMode, ArgumentParseException}
import std.fs.{exists, File, FSException, Path}
import std.regex.Regex
import std.env.atExit
import std.sync.AtomicOptionReference
import std.console.*

private func printHelp(): Unit {
    println("Magic Cli")
    println("  --auto            The agent runs autonomously")
    println("  --language, -l    Specify languages in [Cangjie, General(Default)]")
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
        Full("language", r"l", RequiredValue),
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
    if (let Some(language) <- result.options.get("language") && language.toAsciiUpper() == 'CANGJIE') {
        CliConfig.language = 'Cangjie'
    } else if (let Some(language) <- result.options.get("l") && language.toAsciiUpper() == 'CANGJIE') {
        CliConfig.language = 'Cangjie'
    } else {
        CliConfig.language = 'General'
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

private func initCliContext() {
    let agent = if (CliConfig.language.toAsciiLower() == 'cangjie') {
        ConversationAgent(CangjieCodeAgent())
    } else {
        ConversationAgent(GeneralCodeAgent())
    }

    // Initialize conversation manager
    let conversationManager = ConversationManager()

    // Register the callback to auto-save conversation
    atExit({
        => conversationManager.autoSave(agent)
    })

    // Load MCP servers and add their tools to the agent
    let mcpManager = MCPConfigManager()
    try {
        agent.toolManager.addTools(mcpManager.loadMCPServers())
    } catch (e: Exception) {
        LogUtils.error("Failed to load MCP servers: ${e.message}")
        PrintUtils.printTool("MCP Loading", "❗ Warning: Failed to load MCP servers, continuing without MCP tools")
    }

    // Initialize the conversation compactor to use
    let compactor = Compactor()

    // Register event handlers to display the indicator of using models
    let indicator = AtomicOptionReference<WorkingIndicator>()
    // Although we cannot precisely insert instrumentation before and after using the model,
    // since the agent operates in a tool-loop mode (i.e., "model-tool" cycle),
    // we can implement event handling as follows:
    // The PromptValidateEvent happens before using the model
    EventHandlerManager
        .global
        .addHandler {
            evt: PromptValidateEvent =>
            // There may be other agents during the execution.
            // Only show the indicator of the main agent
            if (evt.agent.name == agent.name) {
                indicator.store(PrintUtils.printWorkingIndicator(message: "💭 Thinking"))
            }
            EventResponse.Continue
        }
    // The ToolCallEvent happens after the model giving its reply
    EventHandlerManager
        .global
        .addHandler {
            evt: ToolCallEvent =>
            if (evt.agent.name == agent.name && let Some(i) <- indicator.load()) {
                i.stop()
            }
            EventResponse.Continue
        }
    setContext(Context(agent, compactor, conversationManager, mcpManager, CliConfig.cwd, mode: CliMode.AGENTIC))
    return getContext()
}

main(args: Array<String>): Int64 {
    if (!parseArgs(args)) {
        printHelp()
        return 0
    }
    setConfig()
    PrintUtils.printWelcome()

    let context = initCliContext()

    // Start the event loop
    while (true) {
        let input = InputUtils.getUserInput(mode: context.mode)
        match (input) {
            case "/exit" | "exit" =>
                PrintUtils.printExitMessage()
                break
            case _ => match (context.mode) {
                case AGENTIC => agenticProcess(input, context)
                case CHATTING => chattingProcess(input, context)
                case _ => terminalProcess(input, context)
            }
        }
    }
    return 0
}

private func agenticProcess(input: String, context: Context) {
    let agent = context.agent
    let compactor = context.compactor
    let conversationManager = context.conversationManager
    let mcpManager = context.mcpManager
    match (input) {
        case "/help" | "help" => PrintUtils.printHelpMessage()
        case "/clear" | "clear" =>
            conversationManager.clearConversation(agent)
            PrintUtils.clearScreen()
            PrintUtils.printLogo()
        case "/compact" | "compact" =>
            if (let Some(index) <- compactor.calculateCompactIndex(agent.conversation)) {
                PrintUtils.printTool("Compacting conversation...", "🚀 Working on it...")
                agent.conversation.compactBy(compactor, firstN: index, keepOrigin: false)
                PrintUtils.printTool("Compacting conversation...", "🥳 Compacted successfully!")
            } else {
                PrintUtils.printTool("Compacting conversation...",
                    "🌱 Conversation context is short enough, no need to compact!")
            }
        case "/memory" | "memory" =>
            let userRules = CliConfig.userRules
            if (userRules.isEmpty()) {
                PrintUtils.printTool("User Memory (MAGIC.md)", "📝 No MAGIC.md file found in current directory")
                println("Create a MAGIC.md file in your project to set custom rules and context for Magic-cli to use.")
            } else {
                PrintUtils.printTool("User Memory (MAGIC.md)", "📝 Current MAGIC.md content:")
                println(userRules)
            }
        case "!" => 
            context.changeMode(CliMode.TERMINAL)
        case _ =>
            if (input.startsWith("/mcp") || input.startsWith("mcp")) {
                mcpManager.handleCommand(input.split(" "), agent)
            } else if (input.startsWith("/conversation") || input.startsWith("conversation")) {
                conversationManager.handleCommand(input.split(" "), agent)
            } else {
                context.changeMode(CHATTING)
                spawn {
                    try {
                        sleep(100 * Duration.second)
                        PrintUtils.printAgentResponse(AgentResponse("OKOK!"))
                    } finally {
                        //context.changeMode(AGENTIC)
                    }
                }
                LogUtils.info("MESSAGE FROM MAIN")
            }
    }
}

private func chattingProcess(input: String, context: Context) {
    if (input != "\u{1B}") {
        return
    }
    // interrupt
    return context.changeMode(AGENTIC)
}

private func terminalProcess(command: String, context: Context) {
    if (command == "!") {
        context.changeMode(CliMode.AGENTIC)
        return
    }
    let (exitCode, stdOutData, stdErrData) = TerminalUtils.execute(command, context.workspace)
    let output = if (exitCode == 0) {
        String.fromUtf8(stdOutData).trimAscii()
    } else {
        String.fromUtf8(stdErrData).trimAscii()
    }
    PrintUtils.printTerminalResponse(output)
}
