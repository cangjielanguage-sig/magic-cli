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
import cli.core.config.CliConfig

//==============================================================================
// CLAIM
// Some prompts in this file are copied from Gemini Cli
// https://github.com/google-gemini/gemini-cli/tree/main/packages/core/src/tools
//==============================================================================

@toolset
public class FSTool {

    // Predefined black-list of directories
    static let IGNORED_DIR = [".git", ".cache", "node_modules", "bower_components", "build", "target"]
    static func ignored(path: Path): Bool {
        return path.fileName.startsWith(".") || IGNORED_DIR.contains(path.fileName)
    }

    @tool[
        description: "Creates a directory recursively and returns the creation result",
        parameters: { path: "Directory path, must be an absolute path" }
    ]
    public func createDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "Directory path must be absolute"
        }

        let message = path
        if (let Deny(userInput) <- InputUtils.confirm("Create Directory", message)) {
            return "User cancelled the operation, feedback: ${userInput}"
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
        if (let Deny(userInput) <- InputUtils.confirm("Create File", message)) {
            return "User cancelled the operation, feedback: ${userInput}"
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
        if (let Deny(userInput) <- InputUtils.confirm("Delete File or Directory", message)) {
            return "User cancelled the operation, feedback: ${userInput}"
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
            let osName = getVariable("OS") ?? "Unknown"
            let isWindows = osName.toAsciiLower().contains("windows")

            let (exitCode, stdOutData, stdErrData) = if (isWindows) {
                executeWithOutput("powershell", ["-Command", "dir"], workingDirectory: Path(path))
            } else {
                executeWithOutput("/bin/bash", ["-c", "ls -la"], workingDirectory: Path(path))
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
        description: "Reads the content of a single file and returns the file content",
        parameters: { filePath: "File path, must be an absolute path" }
    ]
    public func readFile(filePath: String): String {
        let message = filePath
        PrintUtils.printTool("Read File", message)

        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }

        try {
            let fileContent = File.readFrom(filePath)
            return "File content:\n${String.fromUtf8(fileContent)}"
        } catch (e: FSException) {
            return "File path is empty, file is not readable, or file reading failed"
        } catch (e: IllegalArgumentException) {
            return "File path contains null characters"
        } catch (e: Exception) {
            return "Failed to read file: ${e}"
        }
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
        if (let Deny(userInput) <- InputUtils.confirm("Write File", message)) {
            return "User cancelled the operation, feedback: ${userInput}"
        }

        try {
            let file = File(filePath, Write)
            file.write(content.toArray())
            file.close()
            return "File ${filePath} written successfully!"
        } catch (e: FSException) {
            return "Parent directory does not exist, cannot open file, write failed, partial write, or file is not writable"
        } catch (e: IllegalArgumentException) {
            return "File path is empty or contains null characters"
        } catch (e: Exception) {
            return "Failed to write file: ${e}"
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

        return grep(pattern, path, include)
    }

    @tool[
        description: "Modifies file content, must modify at least one function's content at a time, returns modification result. You should put as many modifications as possible into one tool use to improve efficiency",
        parameters: {
            filePath: "File path, must be an absolute path",
            oldContent: "Original file content, must be a part that appears in the file, must contain at least one function from the original file",
            newContent: "Content to overwrite with"
        }
    ]
    public func editFile(filePath: String, oldContent: String, newContent: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }

        let message = filePath + "\nold content:\n" + oldContent + "\nnew content:\n" + newContent
        if (let Deny(userInput) <- InputUtils.confirm("Edit File Content", message)) {
            return "User cancelled the operation, feedback: ${userInput}"
        }

        try {
            let content = String.fromUtf8(File.readFrom(filePath))
            if (!content.contains(oldContent)) {
                return "File ${filePath} does not contain the specified content '${oldContent}', cannot modify"
            }
            let updatedContent = content.replace(oldContent, newContent)
            let file = File(filePath, Write)
            file.write(updatedContent.toArray())
            file.close()
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
        description: "Lists the directory structure recursively from the given path, showing files and subdirectories in a tree-like format. Useful for understanding the overall layout and hierarchy of a project or folder.",
        parameters: {
            path: "The absolute path to the directory to visualize."
        }
    ]
    public func tree(path: String): String {
        let treePath = Path(path)
        if (!treePath.isAbsolute()) {
            return "Path must be absolute"
        } else if (!exists(treePath)) {
            return "${path} does not exist"
        }

        PrintUtils.printTool("Tree", "path: ${treePath}")

        if (!exists(treePath)) {
            return "Directory does not exist: ${treePath}"
        }

        let builder = StringBuilder()
        treeRecursive(treePath, "", true, builder)
        return builder.toString()
    }

    private func treeRecursive(currentPath: Path, prefix: String, isLast: Bool, builder: StringBuilder): Unit {
        if (!exists(currentPath)) {
            return
        }
        let itemName = currentPath.fileName

        if (prefix.size > 0) {
            builder.append(prefix)
            if (isLast) {
                builder.append("└── ")
            } else {
                builder.append("├── ")
            }
        }

        builder.append(itemName)
        builder.append("\n")

        if (FileInfo(currentPath).isRegular()) {
            return
        }

        let items = ArrayList<FileInfo>()
        for (item in Directory.readFrom(currentPath)) {
            if (!ignored(item.path)) {
                items.add(item)
            }
        }

        sort(items, by: { a, b => a.path.fileName.compare(b.path.fileName) })

        for (i in 0..items.size) {
            let item = items[i]
            let isLastItem = i == items.size - 1
            let newPrefix = prefix + if (isLast) { "    " } else { "│   " }
            treeRecursive(item.path, newPrefix, isLastItem, builder)
        }
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

    @tool[
        description: "Reads and returns the full content of a single file with line numbers. Similar to Unix cat -n command, shows content with line numbers for easy reference.",
        parameters: {
            filePath: "The absolute path to the file to read"
        }
    ]
    public func catFile(filePath: String): String {
        let message = "filePath: ${filePath}"
        PrintUtils.printTool("Cat", message)

        return cat(filePath)
    }

    @tool[
        description: "Reads and returns a specific range of lines from a file with line numbers. Useful for viewing specific sections of large files.",
        parameters: {
            filePath: "The absolute path to the file to read",
            startLine: "Starting line number (1-based, inclusive)",
            endLine: "Optional: Ending line number (1-based, inclusive). If not provided, reads to end of file"
        }
    ]
    public func catRangeFile(filePath: String, startLine: Int64, endLine: Option<Int64>): String {
        let message = "filePath: ${filePath}\nstartLine: ${startLine}\nendLine: ${endLine.map { n => n.toString() } ?? "end of file"}"
        PrintUtils.printTool("Cat Range", message)

        return catRange(filePath, startLine, endLine: endLine ?? 0)
    }
}