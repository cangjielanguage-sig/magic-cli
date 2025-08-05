package cli.core.tools

import std.fs.*
import std.process.*
import std.io.*
import std.env.*

import magic.dsl.*
import magic.prelude.*

@toolset[]
public class ShellTool {
    @tool[
        description: "在指定目录下执行Shell命令，返回运行结果",
        parameters: { path: "执行命令的目录路径，必须是绝对路径", command: "要执行的shell命令" }
    ]
    public func execute(path: String, command: String): String {
        let message = "即将执行以下命令：\n${command}\n"
        let confirmation = ConfirmTool.confirm(message)
        if (confirmation != "yes") {
            return "用户取消执行该操作，用户意见反馈：${confirmation}"
        }

        try {
            let osName = getVariable("OS") ?? "Unknown"
            let isWindows = osName.toAsciiLower().contains("windows")
            
            let (exitCode, stdOutData, stdErrData) = if (isWindows) {
                executeWithOutput("powershell", ["-Command", command], workingDirectory: Path(path))
            } else {
                executeWithOutput("/bin/bash", ["-c", command], workingDirectory: Path(path))
            }

            if (exitCode == 0) {
                let outString = String.fromUtf8(stdOutData).trimAscii()
                return "命令执行成功，输出:\n${outString}"
            } else {
                let errString = String.fromUtf8(stdErrData).trimAscii()
                return "命令执行失败，错误输出:\n${errString}"
            }
        } catch (e: Exception) {
            return "执行命令时发生异常: ${e}\n命令: ${command}"
        }
    }
}