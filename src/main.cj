package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.interaction.ConsolePrinter
import std.env.*

import cli.core.*
import cli.core.utils.*
import cli.cli.*
import cli.cli.utils.*

main(): Int64 {
    Config.env["ARK_API_KEY"] = "f3c853c7-2505-4219-b9d5-73f4a945707a"
    Config.env["OPENROUTER_API_KEY"] = "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"
    Config.env["ZHIPU_API_KEY"] = "19c5cf5bbdd04b819cd41338f3b31ecc.P2zmdLtoCnoR46UW"
    Config.logFile = "./cli-agent.log"
    Config.logLevel = "INFO"

    initialShow()

    let agent = CliAgent()
    let conversation = Conversation()

    while (true) {
        let input = getUserInput()

        if (input == "exit") {
            break
        }

        let response = agent.chat(
            AgentRequest(input, conversation: conversation)
        )

        printPrompt("Agent")
        println(response.content)

        conversation.addChatRound(response.execution.chatRound)
    }

    return 0    
}