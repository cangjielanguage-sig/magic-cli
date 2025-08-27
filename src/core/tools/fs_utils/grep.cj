package cli.core.tools.fs_utils

import std.fs.*
import std.process.*
import std.io.*
import std.env.*
import std.collection.*
import std.sort.sort

import magic.prelude.*
import magic.log.LogUtils

import cli.utils.*
import cli.core.config.CliConfig

/**
 * Main grep function that searches for a regular expression pattern within file contents.
 * Supports filtering by file types and searching in specific directories.
 *
 * @param pattern The regular expression pattern to search for
 * @param path Optional directory path to search in (defaults to current working directory)
 * @param include Optional glob pattern to filter files (e.g., "*.cj", "*.{ts,tsx}")
 * @return String containing matching lines with file paths and line numbers
 */
public func grep(pattern: String, path: Option<String>, include: Option<String>): String {
    try {
        let command = if (InfoUtils.os == "windows") {
            let includeArg = include.map { s => '-Include "${s}"'} ?? ""
            "Get-ChildItem -Recurse ${includeArg} | Select-String -Pattern \"${pattern}\" | Select-Object Path, LineNumber, Line"
        } else {
            let grepCmd = ArrayList<String>(["grep", '-r', '-n', '-H', '-E'])
            for (dir in IGNORED_DIR) {
                grepCmd.add("--exclude-dir=${dir}")
            }
            if (let Some(include) <- include) {
                grepCmd.add("--include=${include}");
            }
            grepCmd.add(pattern)
            grepCmd.add(".")
            String.join(grepCmd.toArray(), delimiter: " ")
        }
        LogUtils.debug("[Run command] ${command}")

        let workingDir = path.map { s => Path(s) } ?? CliConfig.cwd
        let (exitCode, stdOutData, stdErrData) = if (InfoUtils.os == "windows") {
            executeWithOutput("powershell", ["-Command", command], workingDirectory: workingDir)
        } else {
            executeWithOutput("/bin/bash", ["-c", command], workingDirectory: workingDir)
        }

        if (exitCode == 0) {
            let outString = String.fromUtf8(stdOutData).trimAscii()
            return parseGrepOutput(outString, workingDir)
        } else {
            let errString = String.fromUtf8(stdErrData).trimAscii()
            return errString
        }
    } catch (e: Exception) {
        return "Failed to execute grep: ${e}"
    }
}

/**
 * Parses raw grep output and converts relative paths to absolute paths.
 *
 * @param rawOutput Raw output from grep command
 * @param workingDir Working directory used for path resolution
 * @return Formatted output with absolute paths
 */
private func parseGrepOutput(rawOutput: String, workingDir: Path): String {
    return String.join(
        rawOutput.split("\n") |>
            map { line: String =>
                // Grep returns "path:line-number:content"
                let items = line.split(":", 3, removeEmpty: false)
                if (items.size != 3) {
                    return line
                }
                // If the found result is a relative path of "."
                // Convert it to absolute path
                let path = if (items[0].startsWith("./")) {
                    canonicalize(workingDir.join(items[0]))
                } else {
                    canonicalize(items[0])
                }
                let number = items[1]
                let content = items[2]
                return String.join([path.toString(), number, content], delimiter: ":")
            } |>
            collectArray,
        delimiter: "\n"
    )
}