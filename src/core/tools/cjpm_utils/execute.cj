package cli.core.tools.cjpm_utils

import std.fs.Path
import std.process.{executeWithOutput, ProcessException}

protected func cjpmRun(args: Array<String>, projectDir: Path): String {
    return execCommand("cjpm", args, projectDir)
}

protected func cjcRun(args: Array<String>, projectDir: Path): String {
    return execCommand("cjc", args, projectDir)
}

private func execCommand(command: String, args: Array<String>, projectDir: Path): String {
    try {
        let (exitCode, stdOut, stdErr) = executeWithOutput(command, args, workingDirectory: projectDir)

        if (exitCode == 0) {
            let output = String.fromUtf8(stdOut)
            if (output.trimAscii().isEmpty()) {
                return "Execute '${command} ${String.join(args, delimiter: " ")}' successfully."
            } else {
                return output
            }
        } else {
            return "Error: ${String.fromUtf8(stdErr)}"
        }
    } catch (e: ProcessException) {
        return "Process execution error: ${e}"
    } catch (e: Exception) {
        return "Unknown error occurred: ${e}"
    }
}