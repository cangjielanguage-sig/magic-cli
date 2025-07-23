package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.interaction.ConsolePrinter

main(): Int64 {
    Config.env["DEEPSEEK_API_KEY"] = "sk-58bf671cc604489c85abfe66c5af0bec"

    let agent = FSAgent()

    print("用户: ")
    let input = readln()

    // let asyncResp = agent.asyncChat(input, verbose: true)
    // ConsolePrinter.print(asyncResp, verbose: true)

    let response = agent.chat(input)
    println("助手: ${response}\n")

    return 0    
}