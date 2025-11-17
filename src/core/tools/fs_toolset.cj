package cli.core.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*
import magic.log.LogUtils

import cli.utils.{InfoUtils, ShellUtils}
import cli.io.{InputUtils, PrintUtils, Confirmation}
import cli.core.tools.fs_utils.*
import cli.core.tools.code_compression.*
import cli.core.config.CliConfig

import std.collection.{map, collectArray, fold}
import std.fs.{Path, File, Directory, remove, exists, FSException}

//----------------------------------------------------------------------------------
// Read only tools
//----------------------------------------------------------------------------------

@tool[
    description: "Lists all files and subdirectories in a directory and returns the list",
    parameters: { path: "Directory path, must be an absolute path" }
]
protected func listDirectory(path: String): String {
    if (!Path(path).isAbsolute()) {
        return "Directory path must be absolute"
    }

    let message = path
    PrintUtils.printTool("List Directory", message)

    try {
        let (exitCode, stdout, stderr) = if (InfoUtils.os == "windows") {
            ShellUtils.execute(["dir"], workDir: Path(path))
        } else { //linux or ohos
            ShellUtils.execute(["ls", "-l"], workDir: Path(path))
        }

        if (exitCode == 0) {
            let outString = stdout.trimAscii()
            PrintUtils.printToolResult(outString)
            return "Directory contents:\n${outString}"
        } else {
            let errString = stderr.trimAscii()
            let result = "Failed to get directory contents, error output:\n${errString}"
            PrintUtils.printToolResult(result)
            return result
        }
    } catch (e: Exception) {
        PrintUtils.printToolResult("Failed to list directory")
        return "Failed to list directory: ${e}"
    }
}

@tool[
    description: "Reads and returns a specific range of lines from a file with line numbers. If startLine and endLine is omitted, the entire file will be read.",
    parameters: {
        filePath: "The absolute path to the file to read",
        startLine: "Optional: Starting line number (1-based, inclusive). If not provided, reads from start of file",
        endLine: "Optional: Ending line number (1-based, inclusive). If not provided, reads to end of file"
    }
]
protected func readFile(filePath: String, startLine: Option<Int64>, endLine: Option<Int64>): String {
    let start = startLine ?? 1
    let end = endLine.map { n => n.toString() } ?? "EOF"
    let message = "${filePath} (${start}-${end})"
    PrintUtils.printTool("Read File", message)
    var content = catRange(filePath, startLine ?? 1, endLine: endLine ?? Int64.Max)

    if (content.size > getCompressionThreshold(false)) {
        content = compressCode(filePath, startLine: startLine ?? 1, endLine: endLine ?? Int64.Max, originalContent: content)
    }

    PrintUtils.printToolResult(content)
    let startInfo = startLine.map { n => " start=${n}" } ?? ""
    let endInfo = endLine.map { n => " end=${n}" } ?? ""
    return "<file-content path=${filePath}${startInfo}${endInfo}>\n${content}\n</file-content>"
}

@tool[
    description: 'Searches for a regular expression pattern within the content of files in a specified directory (or current working directory). Can filter files by a glob pattern. Returns the lines containing matches, along with their file paths and line numbers.',
    parameters: {
        pattern: "The regular expression (regex) pattern to search for within file contents (e.g., 'func \\s+foo', 'import\\s+\\{.*\\}\\s+.*').",
        path: "Optional: The absolute path to the directory to search within. If omitted, searches the current working directory.",
        fileType: "Optional: A glob pattern to filter which files are searched (e.g., '*.js', '*.{ts,tsx}', 'src/**'). If omitted, searches all files (respecting potential global ignores).",
    }
]
func grepSearch(pattern: String, path: Option<String>, include: Option<String>): String {
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
        PrintUtils.printToolResult("Nothing found")
        return "Nothing found"
    } else {
        PrintUtils.printToolResult(result)
        return result
    }
}

// @tool[
//     description: "Lists the directory structure recursively from the given path, showing files and subdirectories in a tree-like format. Useful for understanding the overall layout and hierarchy of a project or folder.",
//     parameters: {
//         path: "The absolute path to the directory to visualize."
//     }
// ]
// public func tree(path: String): String {
//     PrintUtils.printTool("Tree", "path: ${path}")
//     return listTree(path)
// }

/**
 * Maximum number of glob results to return (prevents context overflow)
 */
const MAX_GLOB_RESULTS: Int64 = 100

@tool[
    description: "Efficiently finds files matching specific extensions patterns (e.g., `src/**/*.ts`, `**/*.md`), returning absolute paths. Ideal for quickly locating files based on their extension name, especially in large codebases.",
    parameters: {
        pattern: "Glob pattern to match (e.g., '*.cj' for Cangjie files, '**/test*.cj' for test files recursively)",
        path: "Optional: absolute directory path to search in. Defaults to current working directory."
    }
]
func globSearch(pattern: String, path: Option<String>): String {
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
            PrintUtils.printToolResult("Nothing found")
            return "No files matching pattern '${pattern}' found"
        }

        let totalMatches = results.size
        let shouldTruncate = totalMatches > MAX_GLOB_RESULTS
        let resultsToShow = if (shouldTruncate) {
            results[0..MAX_GLOB_RESULTS]
        } else {
            results
        }

        let found = String.join(
            resultsToShow |> map { file => "- ${file}" } |> collectArray,
            delimiter: "\n"
        )
        PrintUtils.printToolResult(found)

        if (shouldTruncate) {
            let remaining = totalMatches - MAX_GLOB_RESULTS
            return "Found ${totalMatches} matches (showing first ${MAX_GLOB_RESULTS}):\n${found}\n\n[Truncated: ${remaining} more files not shown. Use a more specific pattern to reduce results.]"
        } else {
            return "Found ${totalMatches} matches:\n${found}"
        }
    } catch (e: Exception) {
        return "Error during glob search: ${e}"
    }
}

/**
 * Read multiple files in parallel
 */
@tool[
    description: "${BATCH_READ_FILE_DESCRIPTION}",
    parameters: {
        filePaths: "Array of JSON objects, each containing the absolute path to the file to read, optional startLine, and optional endLine."
    }
]
protected func batchReadFiles(files: Array<ReadFileParam>): String {
    // Construct the info message
    let paths = files |> map { param: ReadFileParam =>
            let start = param.startLine ?? 1
            let end = param.endLine.map { n => n.toString() } ?? "EOF"
            "${param.filePath} (${start}-${end})"
        } |> collectArray

    let message = String.join(paths, delimiter: "\n")
    PrintUtils.printTool("Batch Read Files", message)

    // Validate input
    if (files.isEmpty()) {
        let errorResult = HashMap<String, JsonValue>()
        errorResult["error"] = JsonString("No file paths provided")
        errorResult["files"] = JsonArray([])
        return JsonObject(errorResult).toJsonString()
    }

    let results = batchRead(files)

    //code compression
    var totalChars = results |> fold(0) { sum: Int, r: ?String => sum + (r?.size ?? 0) }
    for (i in 0..files.size) {
        if (totalChars <= getCompressionThreshold(true)) {
            break
        }
        let filePath = files[i].filePath
        if (let Some(fileContent) <- results[i]) {
            let old = fileContent.size
            let newContent = compressCode(filePath, originalContent: fileContent)
            results[i] = newContent
            let new = newContent.size
            totalChars += (new - old)
        }
    }

    // Merge all file content
    let result = mergeBatchResults(files, results)

    PrintUtils.printToolResult(result)
    return result
}

//----------------------------------------------------------------------------------

/**
 * Read-only file system tools
 */
@toolset[
    tools: [listDirectory, readFile, batchReadFiles, grepSearch, globSearch]
]
public class ReadOnlyFSToolset {
}

/**
 * General file system tools
 */
@toolset[
    tools: [listDirectory, readFile, batchReadFiles, grepSearch, globSearch]
]
public class FSToolset {
    @tool[
        description: "Creates a file with content and returns the creation result",
        parameters: {
            filePath: "File path, must be an absolute path",
            content: "File content"
        }
    ]
    func createFile(filePath: String, content: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }

        if (InputUtils.confirm("Create File ${filePath}", content) == Confirmation.Deny) {
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
        description: "Writes content to a single file and returns the write result",
        parameters: { filePath: "File path, must be an absolute path", content: "Content to write" }
    ]
    func writeFile(filePath: String, content: String): String {
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
            oldContent: "The exact literal text to replace, preferably unescaped. Including at least 3 lines of context BEFORE and AFTER the target text, matching whitespace and indentation precisely. If this string is not the exact literal text (i.e. you escaped it) or does not match exactly, the tool will fail.",
            newContent: "The exact literal text to replace `oldContent` with, preferably unescaped. Provide the EXACT text. newContent MUST be different from oldContent; otherwise, the tool will fail."
        }
    ]
    func editFile(filePath: String, oldContent: String, newContent: String): String {
        return multiEditFileImpl(
            "Edit File", filePath, [MultiEditParam(oldContent: oldContent, newContent: newContent)]
        )
    }

    @tool[
        description: "${MULTI_EDIT_FILE_DESCRIPTION}",
        parameters: {
            filePath: "File path, must be an absolute path",
            edits: "Array of edit operations to perform sequentially on the file"
        }
    ]
    func multiEditFile(filePath: String, edits: Array<MultiEditParam>): String {
        return multiEditFileImpl("Multi-Edit File", filePath, edits)
    }

    private func multiEditFileImpl(toolName: String, filePath: String, edits: Array<MultiEditParam>): String {
        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }

        try {
            // Load the original file content
            let oldFileContent = String.fromUtf8(File.readFrom(filePath))

            // Apply each edit sequentially
            var currFileContent = oldFileContent
            for (edit in edits) {
                let oldContent = edit.oldContent
                let newContent = edit.newContent
                if (!currFileContent.contains(oldContent)) {
                    let hint = checkLineEndingMismatch(oldContent, currFileContent)
                    PrintUtils.printToolFailure(
                        "${toolName} (${filePath})",
                        failureInfo: "File does not contain the specified content. ${hint}"
                    )
                    return "Failed to edit. File ${filePath} does not contain the specified content '${oldContent}'. ${hint}"
                }
                currFileContent = currFileContent.replace(oldContent, newContent)
            }

            // Check if the content has changed
            let newFileContent = currFileContent
            if (oldFileContent == newFileContent) {
                PrintUtils.printToolFailure(
                    "${toolName} (${filePath})",
                    failureInfo: "File content is not modified"
                )
                return "No changes to apply. The oldContent and newContent are identical in file: ${filePath}"
            }
            // Render the diff message
            let message = diff(oldFileContent, newFileContent) |> PrintUtils.renderDiff
            if (InputUtils.confirm("${toolName} (${filePath})", message) == Confirmation.Deny) {
                return "User denied the operation"
            }
            // Write the modified content to the file
            File.writeTo(filePath, newFileContent.toArray())
            return "File ${filePath} content modified successfully"
        } catch (ex: FSException) {
            return "File path error or file is not readable/writable"
        } catch (ex: IllegalArgumentException) {
            return "File path is empty or contains illegal characters"
        }
    }

    /**
    * Check if line ending mismatch exists between oldContent and fileContent
    * Returns hint information without modifying content
    */
    private static func checkLineEndingMismatch(oldContent: String, fileContent: String): String {
        if (fileContent.contains("\r\n") && !oldContent.contains("\r\n")) {
            return "File uses Windows line endings (CRLF), but your content uses Unix (LF). Consider using \\r\\n instead of \\n."
        } else if (!fileContent.contains("\r\n") && oldContent.contains("\r\n")) {
            return "File uses Unix line endings (LF), but your content uses Windows (CRLF). Consider using \\n instead of \\r\\n."
        }
        return ""
    }
}