package cli.core.tools.cj_utils

import cli.io.removeAnsiEscape

import std.fs.Path
import std.process.{executeWithOutput, ProcessException}

protected func cjpmRun(args: Array<String>, projectDir: Path): String {
    return execCommand("cjpm", args, projectDir)
}

protected func cjcRun(args: Array<String>, projectDir: Path): String {
    return execCommand("cjc", args, projectDir)
}

protected func cjpmBuild(projectDir: Path): String {
    let output = cjpmRun(["build", "-i"], projectDir)
    let errors = output.split("error: ")
    // Only return the first error if there are multiple errors
    if (errors.size > 1) {
        return "${errors[0]}error: ${errors[1]}"
    } else {
        return output
    }
}

private func execCommand(command: String, args: Array<String>, projectDir: Path): String {
    try {
        let (exitCode, stdOut, stdErr) = executeWithOutput(command, args, workingDirectory: projectDir)

        if (exitCode == 0) {
            let output = String.fromUtf8(stdOut)
            if (output.trimAscii().isEmpty()) {
                return "Execute '${command} ${String.join(args, delimiter: " ")}' successfully."
            } else {
                return removeAnsiEscape(output)
            }
        } else {
            return removeAnsiEscape(String.fromUtf8(stdErr))
        }
    } catch (e: ProcessException) {
        return "Process execution error: ${e}"
    } catch (e: Exception) {
        return "Unknown error occurred: ${e}"
    }
}