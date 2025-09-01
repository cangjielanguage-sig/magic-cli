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
import cli.core.agents.CodeAnalyzer
import cli.context.*
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
    let context = CliContext()
    context.registerHooks()
    setContext(context)

    // Start the event loop
    while (true) {
        let input = InputUtils.getUserInput(mode: context.mode)
        if (input.isEmpty()) {
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

private func agenticProcess(input: String, context: CliContext) {
    let agent = context.agent
    let mcpManager = context.mcpManager
    let conversationManager = context.conversationManager
    let customCommandManager = context.customCommandManager
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
        case "/init" | "init" =>
            initMagicFile()
        case "!" | "！" => 
            context.changeMode(CliMode.TERMINAL)
        case _ =>
            if (input.startsWith("/cmd")) {
                customCommandManager.handleCommand(input, agent)
            } else if (input.startsWith("/mcp") || input.startsWith("mcp")) {
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

private func chattingProcess(input: String, context: CliContext) {
    if (input != "\u{1B}") {
        return
    }
    // interrupt
    context.interrupt()
}

private func terminalProcess(command: String, context: CliContext) {
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

private func initMagicFile(): Unit {
    let agent = CodeAnalyzer()
    let magicFilePath = CliConfig.uerRuleFile
    
    if (exists(magicFilePath)) {
        if(let Deny(userInput) <- InputUtils.confirm("MAGIC.md already exists.", "Overwrite?")){
            return
        }
    }
    
    let prompt = """
Please analyze the current project directory and generate practical MAGIC.md configuration file content.

Requirements:
1. Analyze project type, programming languages, frameworks, and tools in depth
2. Identify project structure, important files, and configurations
3. Infer appropriate coding standards and best practices
4. Generate project-specific development guidelines and considerations
5. Include specific guidance for AI assistant behavior

Output format requirements:
- Return the complete MAGIC.md file content directly, no explanatory text
- Use Markdown format
- Include sections: project info, coding standards, development guide, AI assistant guidance
- Content should be specific and practical to guide future AI assistance work
- DO NOT create or write any files, only return the content

Please start analyzing the project and return the MAGIC.md content:"""
    
    PrintUtils.printTool("MAGIC.md Init", "🔍 Analyzing project structure and generating MAGIC.md...")
    let response = agent.chat(AgentRequest(prompt))
    
    try {
        File.writeTo(magicFilePath, response.content.toArray())
        PrintUtils.printTool("MAGIC.md Init", "✅ MAGIC.md initialized successfully!")
        
        let preview = if (response.content.size > 300) {
            response.content[0..300] + "..."
        } else {
            response.content
        }
        println("📝 Content preview:")
        println(preview)
        println("\n💡 Use '/memory' to view the full content anytime!")
    } catch (e: Exception) {
        println("❌ Failed to write MAGIC.md: ${e.message}")
    }
}

