package cli.core.tools

import std.fs.*
import std.process.*
import std.io.*
import std.env.*
import std.posix.*
import std.collection.*
import std.regex.Regex
import std.sort.sort

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils

import cli.utils.*
import cli.io.{InputUtils, PrintUtils, Confirmation}
import cli.core.tools.fs_utils.*
import cli.core.config.CliConfig

//==============================================================================
// CLAIM
// Some prompts in this file are copied from Gemini Cli
// https://github.com/google-gemini/gemini-cli/tree/main/packages/core/src/tools
//==============================================================================

let EDIT_FILE_DESCRIPTION = """
Replaces text within a file. By default, replaces a single occurrence.
This tool requires providing significant context around the change to ensure precise targeting. Always use the readFile or readFileRange tool to examine the file's current content before attempting a text replacement.

Expectation for required parameters:
1. path MUST be an absolute path; otherwise an error will be thrown.
2. oldContent MUST be the exact literal text to replace (including all whitespace, indentation, newlines, and surrounding code etc.).
3. newContent MUST be the exact literal text to replace `oldContent` with (also including all whitespace, indentation, newlines, and surrounding code etc.). Ensure the resulting code is correct and idiomatic.
4. NEVER escape `oldContent` or `newContent`, that would break the exact literal text requirement.
**Important:** If ANY of the above are not satisfied, the tool will fail. CRITICAL for `oldContent`: Must uniquely identify the single instance to change. Include at least 3 lines of context BEFORE and AFTER the target text, matching whitespace and indentation precisely. If this string matches multiple locations, or does not match exactly, the tool will fail.
"""

@toolset
public class FSToolset {
    @tool[
        description: "Creates a directory recursively and returns the creation result",
        parameters: { path: "Directory path, must be an absolute path" }
    ]
    public func createDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "Directory path must be absolute"
        }

        let message = path
        if (InputUtils.confirm("Create Directory", message) == Confirmation.Deny) {
            return "User denied the operation"
        }

        try {
            Directory.create(path, recursive: true)
            return "Directory ${path} created successfully!"
        } catch (e: FSException) {
            return "Directory already exists"
        } catch (e: IllegalArgumentException) {
            return "Directory is empty, current directory, root directory, or contains null characters"
        } catch (e: Exception) {
            return "Failed to create directory: ${e}"
        }
    }

    @tool[
        description: "Creates a file with content and returns the creation result",
        parameters: {
            content: "File content",
            filePath: "File path, must be an absolute path"
        }
    ]
    public func createFile(content: String, filePath: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }

        let message = filePath + "\n" + content
        if (InputUtils.confirm("Create File", message) == Confirmation.Deny) {
            return "User denied the operation"
        }

        try {
            let file = File(filePath, Write)
            file.write(content.toArray())
            file.close()
            return "File ${filePath} created successfully!"
        } catch (e: Exception) {
            return "Failed to create file: ${e}"
        }
    }

    @tool[
        description: "Deletes a file or directory recursively and returns the deletion result",
        parameters: { path: "File or directory path, must be an absolute path" }
    ]
    public func deleteFileOrDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "File or directory path must be absolute"
        }

        let message = path
        if (InputUtils.confirm("Delete File or Directory", message) == Confirmation.Deny) {
            return "User denied the operation"
        }

        try {
            remove(path, recursive: true)
            return "File or directory ${path} deleted successfully!"
        } catch (e: FSException) {
            return "Specified directory does not exist or deletion failed"
        } catch (e: IllegalArgumentException) {
            return "Path is empty or contains null terminator"
        } catch (e: Exception) {
            return "Failed to delete file or directory: ${e}"
        }
    }

    @tool[
        description: "Lists all files and subdirectories in a directory and returns the list",
        parameters: { path: "Directory path, must be an absolute path" }
    ]
    public func listDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "Directory path must be absolute"
        }

        let message = path
        PrintUtils.printTool("List Directory", message)

        try {
            let (exitCode, stdOutData, stdErrData) = if (InfoUtils.os == "windows") {
                TerminalUtils.execute(["dir"], workDir: Path(path))
            } else { //linux or ohos
                TerminalUtils.execute(["ls", "-la"], workDir: Path(path))
            }

            if (exitCode == 0) {
                let outString = String.fromUtf8(stdOutData).trimAscii()
                return "Directory contents:\n${outString}"
            } else {
                let errString = String.fromUtf8(stdErrData).trimAscii()
                return "Failed to get directory contents, error output:\n${errString}"
            }
        } catch (e: Exception) {
            return "Failed to list directory: ${e}"
        }
    }

    @tool[
        description: "Reads and returns a specific range of lines from a file with line numbers.",
        parameters: {
            filePath: "The absolute path to the file to read",
            startLine: "Optional: Starting line number (1-based, inclusive). If not provided, reads from start of file",
            endLine: "Optional: Ending line number (1-based, inclusive). If not provided, reads to end of file"
        }
    ]
    public func readFile(filePath: String, startLine: Option<Int64>, endLine: Option<Int64>): String {
        let message = "filePath: ${filePath}\nstart: ${startLine ?? 1}\nend: ${endLine.map { n => n.toString() } ?? "end of file"}"
        PrintUtils.printTool("Read File Range", message)

        return catRange(filePath, startLine ?? 1, endLine: endLine ?? Int64.Max)
    }

    @tool[
        description: "Writes content to a single file and returns the write result",
        parameters: { filePath: "File path, must be an absolute path", content: "Content to write" }
    ]
    public func writeFile(filePath: String, content: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }

        let message = filePath + "\n" + content
        if (InputUtils.confirm("Write File", message) == Confirmation.Deny) {
            return "User denied the operation"
        }
        return writeFileBasic(filePath, content)
    }

    @tool[
        description: "${EDIT_FILE_DESCRIPTION}",
        parameters: {
            filePath: "File path, must be an absolute path",
            oldContent: "The exact literal text to replace, preferably unescaped. For single replacements (default), include at least 3 lines of context BEFORE and AFTER the target text, matching whitespace and indentation precisely. For multiple replacements, specify expected_replacements parameter. If this string is not the exact literal text (i.e. you escaped it) or does not match exactly, the tool will fail.",
            newContent: "The exact literal text to replace `oldContent` with, preferably unescaped. Provide the EXACT text. Ensure the resulting code is correct and idiomatic."
        }
    ]
    public func editFile(filePath: String, oldContent: String, newContent: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }

        try {
            let oldFileContent = String.fromUtf8(File.readFrom(filePath))
            if (!oldFileContent.contains(oldContent)) {
                return "File ${filePath} does not contain the specified content '${oldContent}', cannot modify"
            }
            let newFileContent = oldFileContent.replace(oldContent, newContent)

            let message = diff(oldFileContent, newFileContent) |> PrintUtils.renderDiff
            if (InputUtils.confirm("Edit File (${filePath})", message) == Confirmation.Deny) {
                return "User denied the operation"
            }

            File.writeTo(filePath, newFileContent.toArray())
            return "File ${filePath} content modified successfully"
        } catch (e: FSException) {
            return "File path error or file is not readable/writable"
        } catch (e: IllegalArgumentException) {
            return "File path is empty or contains illegal characters"
        } catch (e: Exception) {
            return "Failed to modify file content: ${e}"
        }
    }

    @tool[
        description: 'Searches for a regular expression pattern within the content of files in a specified directory (or current working directory). Can filter files by a glob pattern. Returns the lines containing matches, along with their file paths and line numbers.',
        parameters: {
            pattern: "The regular expression (regex) pattern to search for within file contents (e.g., 'func \\s+foo', 'import\\s+\\{.*\\}\\s+.*').",
            path: "Optional: The absolute path to the directory to search within. If omitted, searches the current working directory.",
            fileType: "Optional: A glob pattern to filter which files are searched (e.g., '*.js', '*.{ts,tsx}', 'src/**'). If omitted, searches all files (respecting potential global ignores).",
        }
    ]
    public func grepSearch(pattern: String, path: Option<String>, include: Option<String>): String {
        // Construct the info message
        let strBuilder = StringBuilder("pattern: ${pattern}")
        if (let Some(path) <- path) {
            strBuilder.append("\npath: ${path}")
        }
        if (let Some(include) <- include) {
            strBuilder.append("\ninclude: ${include}")
        }
        PrintUtils.printTool("Grep", strBuilder.toString())

        let result = grep(pattern, path, include)
        if (result.isEmpty()) {
            return "Nothing found"
        } else {
            return result
        }
    }

    @tool[
        description: "Lists the directory structure recursively from the given path, showing files and subdirectories in a tree-like format. Useful for understanding the overall layout and hierarchy of a project or folder.",
        parameters: {
            path: "The absolute path to the directory to visualize."
        }
    ]
    public func tree(path: String): String {
        PrintUtils.printTool("Tree", "path: ${path}")
        return listTree(path)
    }

    @tool[
        description: "Efficiently finds files matching specific extensions patterns (e.g., `src/**/*.ts`, `**/*.md`), returning absolute paths. Ideal for quickly locating files based on their extension name, especially in large codebases.",
        parameters: {
            pattern: "Glob pattern to match (e.g., '*.cj' for Cangjie files, '**/test*.cj' for test files recursively)",
            path: "Optional: absolute directory path to search in. Defaults to current working directory."
        }
    ]
    public func globSearch(pattern: String, path: Option<String>): String {
        let searchPath = path ?? CliConfig.cwd.toString()
        if (!Path(searchPath).isAbsolute()) {
            return "Path must be absolute"
        }
        if (!exists(searchPath)) {
            return "Path does not exist: ${searchPath}"
        }

        let message = "pattern: ${pattern}\npath: ${searchPath}"
        PrintUtils.printTool("Glob Search", message)

        try {
            let results = glob(pattern, searchPath)

            if (results.isEmpty()) {
                return "No files matching pattern '${pattern}' found"
            }

            let strBuilder = StringBuilder("Found ${results.size} matches:\n")
            for (file in results) {
                strBuilder.append("- ${file}\n")
            }
            return strBuilder.toString()
        } catch (e: Exception) {
            return "Error during glob search: ${e}"
        }
    }

    @tool[
        description: "Returns the first N lines of a file with line numbers. Useful for quickly inspecting the beginning of large files without loading the entire content.",
        parameters: {
            filePath: "The absolute path to the file to read",
            lines: "Optional: Number of lines to return (defaults to 10)"
        }
    ]
    public func headFile(filePath: String, lines: Option<Int64>): String {
        let message = "filePath: ${filePath}\nlines: ${lines.map { n => n.toString() } ?? "10 (default)"}"
        PrintUtils.printTool("Head", message)

        return head(filePath, lines: lines ?? 10)
    }
}