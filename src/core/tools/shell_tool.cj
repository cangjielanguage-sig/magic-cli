package cli.core.tools

import std.fs.*
import std.process.*
import std.io.*
import std.env.*

public class ShellTool {
    // execute shell command
    // need confirmation : true

    public static func confirm(message: String): Bool { // 前端可以实现一个confirm对话框，之后直接调用
        println(message)
        print("用户是否同意执行？(yes/no): ")
        var response = readln()
        if (response.isEmpty()) {
            response = "yes"
        }
        if (response.toAsciiLower().contains("yes")) {
            return true
        } else {
            return false
        }
    }

    public static func execute(command: String): String {
        let message = "即将执行以下命令：\n${command}\n"
        if (!confirm(message)) {
            return "用户取消执行命令"
        }

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
}