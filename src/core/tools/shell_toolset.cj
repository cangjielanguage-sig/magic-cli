package cli.core.tools

import magic.dsl.*
import magic.prelude.*

import cli.io.{InputUtils, PrintUtils, Confirmation}
import cli.utils.*

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
        if (InputUtils.confirm("Execute Shell Command", message) == Confirmation.Deny) {
            return "User denied the operation"
        }

        try {
            let (exitCode, stdOutData, stdErrData) = ShellUtils.execute([command], workDir: Path(path))
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