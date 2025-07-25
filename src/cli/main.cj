package cli.cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.interaction.ConsolePrinter
import std.env.*

main(): Int64 {
    Config.env["DEEPSEEK_API_KEY"] = "sk-58bf671cc604489c85abfe66c5af0bec"

    let agent = CodeAgent()
    let conversation = Conversation()

    while (true) {
        print("用户: ")
        let input = readln()

        if (input.contains("exit")) {
            println("退出程序")
            break
        }

        // let asyncResp = agent.asyncChat(AgentRequest(input, verbose: true))
        // ConsolePrinter.print(asyncResp, verbose: true)

        let response = agent.chat(
            AgentRequest(input, conversation: conversation)
        )
        conversation.addChatRound(response.execution.chatRound)
        println("助手: ${response.content}\n")
    }

    return 0    
}