package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.interaction.ConsolePrinter
import std.env.*

main(): Int64 {
    // 从环境变量读取 API 密钥
    let apiKey = getVariable("DEEPSEEK_API_KEY")
    if (apiKey.isSome()) {
        Config.env["DEEPSEEK_API_KEY"] = apiKey.get()
    } else {
        println("错误: 未找到 DEEPSEEK_API_KEY 环境变量")
        return 1
    }

    let agent = FSAgent()

    print("用户: ")
    let input = readln()

    // let asyncResp = agent.asyncChat(input, verbose: true)
    // ConsolePrinter.print(asyncResp, verbose: true)

    let response = agent.chat(input)
    println("助手: ${response}\n")

    return 0    
}