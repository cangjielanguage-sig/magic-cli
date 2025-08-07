package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.interaction.ConsolePrinter
import std.env.*

import cli.core.*
import cli.core.utils.*

main(): Int64 {
    Config.env["ARK_API_KEY"] = "f3c853c7-2505-4219-b9d5-73f4a945707a"
    Config.env["OPENROUTER_API_KEY"] = "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"
    Config.env["ZHIPU_API_KEY"] = "19c5cf5bbdd04b819cd41338f3b31ecc.P2zmdLtoCnoR46UW"
    Config.logFile = "./cli-agent.log"
    Config.logLevel = "INFO"

    let banner = Banner()
    banner.printBanner()
    let agent = CliAgent()
    let conversation = Conversation()
    println("欢迎使用Cangjie CLI助手！")
    println("输入 'exit' 退出程序")

    while (true) {
        print("用户: ")
        let input = readln()

        if (input.contains("exit")) {
            println("退出程序")
            break
        }

        let asyncResp = agent.asyncChat(
            AgentRequest(input, verbose: true, conversation: conversation)
        )
        ConsolePrinter.print(asyncResp, verbose: true)
        conversation.addChatRound(asyncResp.execution.chatRound)
    }

    return 0    
}