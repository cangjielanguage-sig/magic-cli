package cli.utils

import magic.log.LogUtils

import std.process.*
import std.fs.Path
import std.collection.ArrayList
import std.time.*
import std.sync.*
import std.io.*

// Timeout exception for shell command execution
public class ShellTimeoutException <: Exception {
    public init(message: String) {
        super(message)
    }
}

public class ShellUtils {
    private static func buildCommandArgs(command: Array<String>, withWrap: Bool): (String, Array<String>) {
        if (!withWrap) {
            let args: Array<String> = if (command.size > 1) { command[1..] } else { [] }
            return (command[0], args)
        }
        let cmdArgs = ArrayList<String>()
        if (InfoUtils.os == "windows") {
            cmdArgs.add("/c")
            return ("cmd", ["/c", String.join(command, delimiter: " ")])
        } else {
            return ("sh", ["-c", String.join(command, delimiter: " ")])
        }
    }

    public static func execute(command: Array<String>,
                               timeout!: Option<Duration> = None,
                               workDir!: Option<Path> = None,
                               withWrap!: Bool = true): (Int64, String, String) {
        let (cmd, cmdArgs) = buildCommandArgs(command, withWrap)

        let process = launch(
            cmd,
            cmdArgs,
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe,
            workingDirectory: workDir
        )
        try {
            let stdoutReader = StringReader(process.stdOutPipe)
            let stderrReader = StringReader(process.stdErrPipe)
            let stdout = stdoutReader.readToEnd()
            let stderr = stderrReader.readToEnd()

            let exitCode = process.wait(timeout: timeout)
            if (exitCode != 0) {
                LogUtils.error("Shell command execution failed: ${exitCode}")
                LogUtils.error("  ${cmd} ${String.join(cmdArgs, delimiter: ' ')}")
            }
            return (exitCode, stdout, stderr)
        } catch(ex: TimeoutException) {
            throw ShellTimeoutException("Shell command execution timed out")
        }
    }
}
