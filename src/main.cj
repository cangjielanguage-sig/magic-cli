package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.agent.ConversationAgent
import magic.interaction.ConsolePrinter
import magic.log.LogUtils

import cli.core.agents.CodeAgent
import cli.core.config.CliConfig
import cli.utils.{InputUtils, PrintUtils}

import std.argopt.{parseArguments, ArgumentSpec, ArgumentMode, ArgumentParseException}
import std.fs.{exists, File, FSException, Path}
import std.regex.Regex

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
                let value = md.matchString(2)
                LogUtils.info("[ENV Set] ${key}=${value}")
                Config.env[key] = value
            }
        }
    } catch (e: Exception) {
        LogUtils.error("Failed to read .env file")
    }
}

main(args: Array<String>): Int64 {
    if (!parseArgs(args)) {
        printHelp()
        return 0
    }
    // Set your API key in the .env file
    loadEnvFile()
    Config.logFile = CliConfig.logFile.toString()
    Config.logLevel = "INFO"
    Config.modelRequestDir = CliConfig.dotDir.join("model-requests").toString()
    Config.enableFunctionCall = true

    PrintUtils.printWelcome()

    let agent = ConversationAgent(CodeAgent())

    while (true) {
        let input = InputUtils.getUserInput()
        match (input) {
            case "exit" =>
                PrintUtils.printExitMessage()
                break
            case "help" =>
                PrintUtils.printHelpMessage()
            case "clear" =>
                PrintUtils.clearScreen()
                PrintUtils.printLogo()
            case _ =>
                let response = agent.chat(AgentRequest(input))
                PrintUtils.printAgentResponse(response)
        }
    }
    return 0
}
