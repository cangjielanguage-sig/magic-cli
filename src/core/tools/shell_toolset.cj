package cli.core.tools

import cli.utils.*

import magic.dsl.*
import magic.prelude.*

import std.fs.*
import std.io.*
import std.env.*

@toolset
public class ShellTool {
    @tool[
        description: "Executes a shell command in the specified directory and returns the execution result",
        parameters: {
            path: "Directory path for command execution, must be an absolute path",
            command: "Shell command to execute"
        }
    ]
    public func shellExecute(path: String, command: String): String {
        let message = command
        if (let Deny(userInput) <- InputUtils.confirm("Execute Shell Command", message)) {
            return "User cancelled the operation, feedback: ${userInput}"
        }

        try {
            let (exitCode, stdOutData, stdErrData) = TerminalUtils.execute(command, Path(path))
            if (exitCode == 0) {
                let outString = String.fromUtf8(stdOutData).trimAscii()
                return "Command executed successfully, output:\n${outString}"
            } else {
                let errString = String.fromUtf8(stdErrData).trimAscii()
                return "Command execution failed, error output:\n${errString}"
            }
        } catch (e: Exception) {
            return "Exception occurred while executing command: ${e}\nCommand: ${command}"
        }
    }
}