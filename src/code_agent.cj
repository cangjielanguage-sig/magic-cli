package cli

import magic.dsl.*
import magic.prelude.*
import magic.config.Config

@agent[model: "deepseek:deepseek-chat"]
class CodeAgent {
    @prompt(
        "你是一个AI代码助手，可以利用各种工具来完成用户的需求。\n"
        "你的职责包括但不限于：\n"
        "1. 解答用户有关代码的问题\n"
        "2. 生成代码片段\n"
        "3. 执行代码并返回结果\n"
        "4. 调试代码\n"
        "5. 提供编程建议\n\n"
        "你有两个Agent来辅助你的工作，一个是文件系统Agent（FSAgent），另一个是BashAgent。\n"
        "Agent的具体能力如下：\n"
        "1. FSAgent：可以创建、删除文件和目录，读取和写入文件内容，对文件的特定内容进行修改，列出目录内容，基于模式匹配查找文件，搜索文件内容，查询或修改文件权限\n"
        "2. BashAgent：可以执行命令行指令。\n\n"
        "对于用户较为简单的需求，你可以直接利用工具完成\n"
        "请注意！对于较为复杂的需求，你需要先给出一个任务规划，之后不断迭代完成需求。在此过程中，你可以随时调用FSAgent和BashAgent来帮助你完成任务。你需要不断将当前的进度反馈给用户，并根据用户的反馈进行调整。\n"
    )

    let bashAgent = BashAgent()
    let fsAgent = FSAgent()

    @tool[
        description: "调用BashAgent执行Shell命令",
        parameters: { request: "传给BashAgent的需求描述" }
    ]
    public func executeBashAgent(request: String): String {
        return bashAgent.chat(request)
    }

    @tool[
        description: "调用FSAgent执行文件系统操作",
        parameters: { request: "传给FSAgent的需求描述" }
    ]
    public func executeFSAgent(request: String): String {
        return fsAgent.chat(request)
    }

}