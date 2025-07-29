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

            // let cmd = if (isWindows) {
            //     "powershell"
            // } else {
            //     "/bin/bash"
            // }

            // let args = if (isWindows) {
            //     ["-Command", command]
            // } else {
            //     ["-c", command]
            // }

            // let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

            // if (exitCode == 0) {
            //     let outputString = String.fromUtf8(stdOutData)
            //     if (outputString.trimAscii().size == 0) {
            //         return "命令执行成功"
            //     } else {
            //         return outputString
            //     }
            // } else {
            //     let errorString = String.fromUtf8(stdErrData)
            //     return "命令执行错误: " + errorString
            // }
            
            let process = if (isWindows) {
                launch("powershell", ["-Command", command], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            } else {
                launch("/bin/bash", ["-c", command], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            }

            let outReader = StringReader<InputStream>(process.stdOutPipe)
            let output = outReader.readToEnd()
            let errReader = StringReader<InputStream>(process.stdErrPipe)
            let errorOutput = errReader.readToEnd()
            let exitCode = process.wait()

            var result = "命令: ${command}\n" + "退出码: ${exitCode}\n"
            if (!output.isEmpty()) {
                result += "输出:\n${output}\n"
            }
            if (!errorOutput.isEmpty()) {
                result += "错误输出:\n${errorOutput}\n"
            }
            if (exitCode == 0) {
                result += "状态: 执行成功"
            } else {
                result += "状态: 执行失败"
            }

            return result
            
        } catch (e: Exception) {
            return "执行命令时发生异常: ${e}\n命令: ${command}"
        }
    }
}