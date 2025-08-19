package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.agent.ConversationAgent
import magic.interaction.ConsolePrinter
import std.env.*

import cli.core.agents.*
import cli.utils.*
import cli.core.config.CliConfig

main(): Int64 {
    // Config.env["ARK_API_KEY"] = "f3c853c7-2505-4219-b9d5-73f4a945707a"
    Config.env["OPENROUTER_API_KEY"] = "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"
    Config.env["ZHIPU_API_KEY"] = "19c5cf5bbdd04b819cd41338f3b31ecc.P2zmdLtoCnoR46UW"
    Config.logFile = CliConfig.logFile.toString()
    Config.logLevel = "INFO"
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
                println(
                    wrapBox("${InputUtils.buildPrompt("🔮 Agent")}${response.content}")
                )
        }
    }
    return 0
}
