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
        description: "Executes a shell command in the specified directory and returns the execution result. Includes automatic timeout protection to prevent hanging on long-running or daemon processes like 'python3 -m http.server'.",
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
            // Use executeWithTimeout with 3-minute default timeout to prevent hanging on daemon processes
            let (exitCode, stdOutData, stdErrData) = ShellUtils.executeWithTimeout(
                [command],
                workDir: Path(path),
                timeoutSeconds: 180
            )

            if (exitCode == 0) {
                let outString = String.fromUtf8(stdOutData).trimAscii()
                return "Command executed successfully, output:\n${outString}"
            } else {
                let errString = String.fromUtf8(stdErrData).trimAscii()
                return "Command execution failed, error output:\n${errString}"
            }
        } catch (e: ShellTimeoutException) {
            return "Command execution timeout after 3 minutes: ${e.message}\n\nThe command appears to be a daemon/server process or is taking too long to execute.\n\nSuggestions:\n1. If this is a server/daemon (like 'python3 -m http.server'), it should be run in the background manually\n2. If the command legitimately needs more time, consider breaking it into smaller steps\n3. Check if the command is stuck waiting for input or has encountered an error"
        } catch (e: Exception) {
            return "Exception occurred while executing command: ${e}\nCommand: ${command}"
        }
    }
}