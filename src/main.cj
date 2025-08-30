package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.agent.ConversationAgent
import magic.interaction.ConsolePrinter
import magic.log.LogUtils
import magic.core.message.Conversation
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

main(args: Array<String>): Int64 {
    if (!parseArgs(args)) {
        printHelp()
        return 0
    }
    setConfig()
    PrintUtils.printWelcome()

    // register global context
    let context = Context()
    context.registerHooks()
    setContext(context)

    // Start the event loop
    while (true) {
        let input = InputUtils.getUserInput(mode: context.mode)
        if (input == String.empty) {
            continue
        }
        match (context.mode) {
            case AGENTIC => match (input) {
                case "/exit" | "exit" =>
                    PrintUtils.printExitMessage()
                    break
                case _ => agenticProcess(input, context)
            }
            case CHATTING => chattingProcess(input, context)
            case _ => terminalProcess(input, context)
        }
    }
    return 0
}

private func agenticProcess(input: String, context: Context) {
    let agent = context.agent
    let mcpManager = context.mcpManager
    let conversationManager = context.conversationManager
    match (input) {
        case "/help" | "help" => PrintUtils.printHelpMessage()
        case "/compact" | "compact" => conversationManager.compact(manual: true)
        case "/clear" | "clear" =>
            conversationManager.clearConversation()
            PrintUtils.clearScreen()
            PrintUtils.printLogo()
        case "/memory" | "memory" =>
            let userRules = CliConfig.userRules
            if (userRules.isEmpty()) {
                PrintUtils.printTool("User Memory (MAGIC.md)", "📝 No MAGIC.md file found in current directory")
                println("Create a MAGIC.md file in your project to set custom rules and context for Magic-cli to use.")
            } else {
                PrintUtils.printTool("User Memory (MAGIC.md)", "📝 Current MAGIC.md content:")
                println(userRules)
            }
        case "!" => context.changeMode(CliMode.TERMINAL)
        case _ =>
            if (input.startsWith("/mcp") || input.startsWith("mcp")) {
                mcpManager.handleCommand(input.split(" "), agent)
            } else if (input.startsWith("/conversation") || input.startsWith("conversation")) {
                conversationManager.handleCommand(input.split(" "))
            } else {
                context.changeMode(CHATTING)
                spawn {
                    let thread = Thread.currentThread
                    try {
                        if (!context.startConversation(thread.id)) {
                            return
                        }
                        let response = agent.chat(AgentRequest(input))
                        if (!context.interrupted(thread.id)) {
                            PrintUtils.printAgentResponse(response)
                            conversationManager.compact()
                        }
                    } finally {
                        context.endConversation(thread.id)
                    }
                }
            }
    }
}

private func chattingProcess(input: String, context: Context) {
    if (input != "\u{1B}") {
        return
    }
    // interrupt
    context.interrupt()
}

private func terminalProcess(command: String, context: Context) {
    match (command) {
        case "/exit" | "exit" | "!" =>
            context.changeMode(CliMode.AGENTIC)
            return
        case _ =>
            let (exitCode, stdOutData, stdErrData) = TerminalUtils.execute(command, context.workspace)
            let output = if (exitCode == 0) {
                String.fromUtf8(stdOutData).trimAscii()
            } else {
                String.fromUtf8(stdErrData).trimAscii()
            }
            PrintUtils.printTerminalResponse(output)
    }
}
