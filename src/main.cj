package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.interaction.ConsolePrinter
import std.env.*

import cli.core.*
import cli.core.utils.*

main(): Int64 {
    Config.env["ARK_API_KEY"] = "c41e4017-e9fe-47e0-9b35-eca879eb4a13"
    Config.logFile = "./cli-agent.log"
    Config.logLevel = "DEBUG"

    let agent = CodeAgent()
    let conversation = Conversation()
    let banner = Banner()
    banner.printBanner()
    println("欢迎使用Cangjie CLI助手！")
    println("输入 'exit' 退出程序")

    while (true) {
        print("用户: ")
        let input = readln()

        if (input.contains("exit")) {
            println("退出程序")
            break
        }

        // let response = agent.chat(
        //     AgentRequest(input, conversation: conversation)
        // )
        // conversation.addChatRound(response.execution.chatRound)
        // println("助手: ${response.content}\n")

        let asyncResp = agent.asyncChat(
            AgentRequest(input, verbose: true, conversation: conversation)
        )
        ConsolePrinter.print(asyncResp, verbose: true)
        conversation.addChatRound(asyncResp.execution.chatRound)
    }

    return 0    
}