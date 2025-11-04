package cli.core.tools.cj_utils

import magic.log.LogUtils
import magic.utils.readFile
import magic.dsl.jsonable
import magic.jsonable.*
import magic.parser.ParserUtils

import cli.io.removeAnsiEscape
import std.unicode.UnicodeStringExtension
import cli.core.config.CliConfig

import std.collection.{ArrayList, HashMap}
import std.fs.{Path, File, OpenMode, copy, remove}
import std.io.StringWriter
import std.process.{executeWithOutput, ProcessException}
import stdx.encoding.json.*

protected func cjpmRun(args: Array<String>, projectDir: Path): String {
    return execCommand("cjpm", args, projectDir)
}

protected func cjcRun(args: Array<String>, projectDir: Path): String {
    return execCommand("cjc", args, projectDir)
}

@jsonable
class BuildResult {
    let Diags: ArrayList<Diagnostic>

    /**
     * Filter out only same error diagnostics
     */
    func filterSameErrors(): Unit {
        // Filter out only error diagnostics
        this.Diags.removeIf ({ diag => diag.Severity != "error" })
        if (this.Diags.isEmpty()) {
            return
        }
        let error = this.Diags[0].Message
        this.Diags.removeIf ({ diag => diag.Message != error })
    }

    func toString(): String {
        let writer = StringBuilder()
        for (diag in this.Diags) {
            let msg = if (diag.MainHint.Content.isEmpty()) {
                diag.Message
            } else {
                "${diag.Message}; ${diag.MainHint.Content}"
            }
            writer.append("Location: ${diag.Location.File}:${diag.Location.Line}\n")
            writer.append("Error: ${msg}\n\n")
        }
        return writer.toString()
    }
}

@jsonable
class Diagnostic {
    let DiagKind: String
    let Severity: String
    let Message: String
    let Location: DiagLocation
    let MainHint: DiagHint
}

@jsonable
class DiagLocation {
    let File: String
    let Line: Int64
    let Column: Int64
}

@jsonable
class DiagHint {
    let Content: String
}

/**
 * Backup the original cjpm.toml file
 */
private func backupCjpmToml(projectDir: Path): Bool {
    let originalPath = projectDir.join("cjpm.toml")
    let backupPath = CliConfig.dotDir.join("cjpm.toml.backup")

    try {
        copy(originalPath, to: backupPath, overwrite: true)
        return true
    } catch (ex: Exception) {
        LogUtils.error("Failed to backup cjpm.toml: ${ex}")
        return false
    }
}

/**
 * Restore cjpm.toml from backup
 */
protected func restoreCjpmToml(projectDir: Path): Bool {
    let originalPath = projectDir.join("cjpm.toml")
    let backupPath = CliConfig.dotDir.join("cjpm.toml.backup")

    try {
        // Restore original file
        copy(backupPath, to: originalPath, overwrite: true)

        // Remove backup file
        remove(backupPath)
        return true
    } catch (e: Exception) {
        LogUtils.error("Failed to restore cjpm.toml: ${e}")
        return false
    }
}

/**
 * Modify cjpm.toml to add --diagnostic-format=json to compile-option
 */
protected func modifyCjpmToml(projectDir: Path): Bool {
    // Backup cjpm.toml first
    if (!backupCjpmToml(projectDir)) {
        return false
    }

    let tomlPath = projectDir.join("cjpm.toml")

    try {
        // Read original file
        let content = readFile(tomlPath)

        // Find and modify the compile-option line
        let lines = content.split('\n')
        let modifiedContent = StringBuilder()
        var found = false

        for (i in 0..lines.size) {
            let line = lines[i]
            if (line.contains("override-compile-option")) {
                // Parse existing compile-option value
                let parts = line.split('=', 2)
                if (parts.size == 2) {
                    let key = parts[0].trimAscii()
                    let value = parts[1].trimAscii()

                    // Remove quotes if present
                    var unquotedValue = value
                    if (value.startsWith('"') || value.startsWith("'")) {
                        unquotedValue = value[1..(value.size - 1)].trimAscii()
                    }

                    // Add --diagnostic-format=json if not already present
                    if (!unquotedValue.contains("--diagnostic-format=json")) {
                        unquotedValue += " --diagnostic-format=json"
                    }

                    // Add --error-count-limit=all if not already present
                    if (!unquotedValue.contains("--error-count-limit=all")) {
                        unquotedValue += " --error-count-limit=all"
                    }

                    modifiedContent.append("${key} = \"${unquotedValue}\"")

                    // Re-quote the value
                    found = true
                } else {
                    modifiedContent.append(line)
                }
            } else {
                modifiedContent.append(line)
            }

            if (i < lines.size - 1) {
                modifiedContent.append('\n')
            }
        }
        // Add the override-compile-option if not found
        var newCjpmToml = modifiedContent.toString()
        if (!found) {
            newCjpmToml = newCjpmToml.replace(
                "[package]",
                "[package]\n  override-compile-option = \"--diagnostic-format=json --error-count-limit=all\"\n")
        }
        // Overwrite the current toml file
        try (file = File(tomlPath, OpenMode.Write)) {
            let writer = StringWriter(file)
            writer.write(newCjpmToml)
            writer.flush()
        }
        return true
    } catch (ex: Exception) {
        LogUtils.error("Failed to modify cjpm.toml: ${ex}")
        // If modified failed, restore original cjpm.toml
        restoreCjpmToml(projectDir)
        return false
    }
}

protected func cjpmBuild(projectDir: Path, outputJson!: Bool = false): String {
    // Execute the build
    let output = cjpmRun(["build", "-i"], projectDir)
    // Check if build succeeded; if so, return success message
    if (output.contains("cjpm build success")) {
        return "cjpm build success"
    }
    if (outputJson) {
        try {
            let result = ParserUtils.extractFirstValue<BuildResult>(output)
            result.filterSameErrors()
            if (!result.Diags.isEmpty()) {
                return "<compile error>\n${result.toString()}\n</compile error>"
            }
        } catch (ex: Exception) {
            LogUtils.error("Failed to parse cjpm build Json output\n```\n${output}\n```")
        }
    }

    // Process the output as plain text if the build output is not Json
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