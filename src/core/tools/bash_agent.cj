package cli.core.tools

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import std.fs.*
import std.process.*
import std.io.*
import std.env.*

@agent[model: "deepseek:deepseek-chat"]
class BashAgent {
    @prompt(
        "你是一个能够执行shell命令的AI助手，你的职责就是执行用户的shell命令并返回结果。\n"
        "请注意，如果命令的执行遇到了错误，包括但不限于语法错误、权限问题等，你需要将错误信息简洁易懂地反馈给用户，并提供解决方案，寻求用户的确认。\n"
        "具体来说，你需要：\n"
        "1. 根据用户输入提炼出需要执行的shell命令\n"
        "2. 向用户确认执行该命令的意图\n"
        "3. 用户同意后，执行命令并返回结果；用户不同意则直接退出Agent，返回'用户取消执行命令'。\n"
        "4. 如果执行过程中出现错误，反馈错误信息并提供解决方案，重复以上步骤\n"
    )

    @tool[
        description: "执行Bash命令，返回运行结果",
        parameters: { command: "要执行的shell命令" }
    ]
    public func executeBashCommand(command: String): String {
        try {
            let osName = getVariable("OS") ?? "Unknown"
            let isWindows = osName.toAsciiLower().contains("windows")
            
            let process = if (isWindows) {
                launch("powershell", ["-Command", command], stdOut: ProcessRedirect.Pipe)
            } else {
                launch("/bin/bash", ["-c", command], stdOut: ProcessRedirect.Pipe)
            }

            let outReader = StringReader<InputStream>(process.stdOutPipe)
            let output = outReader.readToEnd()
            let exitCode = process.wait()

            var result = "命令: ${command}\n" + "退出码: ${exitCode}\n" + "输出:\n${output}\n"
            if (exitCode == 0) {
                result += "状态: 执行成功"
            } else {
                result += "状态: 执行失败"
            }

            return result
            
        } catch (e: Exception) {
            return "执行命令时发生异常: ${e.message}\n命令: ${command}"
        }
    }

    @tool[
        description: "请求用户确认是否执行命令，返回用户意见",
        parameters: { message: "需要用户确认的消息，里面必须包含即将要执行的命令" }
    ]
    public func requestUserConfirmation(message: String): String {
        println(message)
        print("用户是否同意执行？(yes/no): ")
        var response = readln()
        if (response.isEmpty()) {
            response = "yes"
        }
        return response
    }

}