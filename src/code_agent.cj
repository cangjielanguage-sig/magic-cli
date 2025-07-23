package cli

// import magic.dsl.*
// import magic.prelude.*
// import magic.config.Config

// @agent[model: "deepseek:deepseek-chat"]
// class CodeAgent {
//     @prompt(
//         "你是一个AI代码助手，可以利用各种工具来完成用户的需求。\n"
//         "你的职责包括但不限于：\n"
//         "1. 解答用户有关代码的问题\n"
//         "2. 生成代码片段\n"
//         "3. 执行代码并返回结果\n"
//         "4. 调试代码\n"
//         "5. 提供编程建议\n\n"
//         "请根据用户的需求，使用合适的工具和方法来完成任务。\n"
//     )

//     let bashAgent = BashAgent()

//     @tool[description: "执行命令行指令"]
//     func executeShellCommand(command: String): String

// }