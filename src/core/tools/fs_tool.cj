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
        description: "创建目录，可递归创建，返回创建结果",
        parameters: { path: "目录路径，必须是绝对路径" }
    ]
    public func createDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "目录路径必须是绝对路径"
        }

        let message = path
        if (let Deny(userInput) <- InputUtils.confirm("Create Directory", message)) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            Directory.create(path, recursive: true)
            return "目录 ${path} 创建成功！"
        } catch (e: FSException) {
            return "目录已存在"
        } catch (e: IllegalArgumentException) {
            return "目录为空、目录为当前目录、目录为根目录或目录中存在空字符"
        } catch (e: Exception) {
            return "创建目录失败：${e}"
        }
    }

    @tool[
        description: "创建文件并写入内容，返回创建结果",
        parameters: {
            content: "文件内容",
            filePath: "文件路径，必须是绝对路径"
        }
    ]
    public func createFile(content: String, filePath: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "文件路径必须是绝对路径"
        }

        let message = filePath + "\n" + content
        if (let Deny(userInput) <- InputUtils.confirm("Create File", message)) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            let file = File(filePath, Write)
            file.write(content.toArray())
            file.close()
            return "文件 ${filePath} 创建成功！"
        } catch (e: Exception) {
            return "创建文件失败：${e}"
        }
    }

    @tool[
        description: "删除文件或目录，删除目录为递归删除，返回删除结果",
        parameters: { path: "文件或目录路径，必须是绝对路径" }
    ]
    public func deleteFileOrDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "文件或目录路径必须是绝对路径"
        }

        let message = path
        if (let Deny(userInput) <- InputUtils.confirm("Delete File or Directory", message)) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            remove(path, recursive: true)
            return "文件或目录 ${path} 删除成功！"
        } catch (e: FSException) {
            return "指定目录不存在或删除失败"
        } catch (e: IllegalArgumentException) {
            return "路径为空或包含字符串结束符"
        } catch (e: Exception) {
            return "删除文件或目录失败：${e}"
        }
    }

    @tool[
        description: "列出目录下的所有文件和子目录，返回列表",
        parameters: { path: "目录路径，必须是绝对路径" }
    ]
    public func listDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "目录路径必须是绝对路径"
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
                return "目录内容如下：\n${outString}"
            } else {
                let errString = String.fromUtf8(stdErrData).trimAscii()
                return "获取目录内容失败，错误输出:\n${errString}"
            }
        } catch (e: Exception) {
            return "列出目录失败：${e}"
        }
    }

    @tool[
        description: "读取单个文件的内容，返回文件内容",
        parameters: { filePath: "文件路径，必须是绝对路径" }
    ]
    public func readFile(filePath: String): String {
        let message = filePath
        PrintUtils.printTool("Read File", message)

        return load(filePath)
    }

    @tool[
        description: "写入内容到单个文件，返回写入结果",
        parameters: { filePath: "文件路径，必须是绝对路径", content: "要写入的内容" }
    ]
    public func writeFile(filePath: String, content: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "文件路径必须是绝对路径"
        }

        let message = filePath + "\n" + content
        if (let Deny(userInput) <- InputUtils.confirm("Write File", message)) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            let file = File(filePath, Write)
            file.write(content.toArray())
            file.close()
            return "文件 ${filePath} 写入成功！"
        } catch (e: FSException) {
            return "文件的父目录不存在、其他原因导致无法打开文件、写入失败、只写入了部分数据或文件不可写"
        } catch (e: IllegalArgumentException) {
            return "文件路径为空或文件路径包含空字符"
        } catch (e: Exception) {
            return "写入文件失败：${e}"
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

    public func find(rootPath: String, pattern: String): ArrayList<String> {
        let results = ArrayList<String>()
        let root = Path(rootPath)

        if (!exists(root)) {
            return results
        }

        let regex = Regex(pattern)
        findRecursive(root, regex, results)

        return results
    }

    private func findRecursive(currentPath: Path, pattern: Regex, results: ArrayList<String>): Unit {
        for (item in Directory.readFrom(currentPath)) {
            let itemName = item.name
            let itemPath = item.path

            if (pattern.matches(itemName)) {
                results.add(itemPath.toString())
            }

            if (item.isDirectory() && !ignored(itemPath)) {
                findRecursive(itemPath, pattern, results)
            }
        }
    }

    @tool[
        description: "修改文件内容，必须一次至少修改一个函数的内容，返回修改结果，你需要将尽可能多的修改放到一次工具中使用，这样可以提升修改效率",
        parameters: {
            filePath: "文件路径，必须是绝对路径",
            oldContent: "原本文件的内容，必须是文件里出现的部分，必须至少包含原文件中的一个函数",
            newContent: "即将覆盖的内容"
        }
    ]
    public func editFile(filePath: String, oldContent: String, newContent: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "文件路径必须是绝对路径"
        }

        let message = filePath + "\nold content:\n" + oldContent + "\nnew content:\n" + newContent
        if (let Deny(userInput) <- InputUtils.confirm("Edit File Content", message)) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            let content = String.fromUtf8(File.readFrom(filePath))
            if (!content.contains(oldContent)) {
                return "文件 ${filePath} 中不包含指定的内容 '${oldContent}'，无法进行修改"
            }
            let updatedContent = content.replace(oldContent, newContent)
            let file = File(filePath, Write)
            file.write(updatedContent.toArray())
            file.close()
            return "文件 ${filePath} 内容已成功修改"
        } catch (e: FSException) {
            return "文件路径错误或文件不可读写"
        } catch (e: IllegalArgumentException) {
            return "文件路径为空或包含非法字符"
        } catch (e: Exception) {
            return "修改文件内容失败：${e}"
        }
    }

    public static func load(filePath: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "文件路径必须是绝对路径"
        }

        try {
            let fileContent = File.readFrom(filePath)
            return "文件内容:\n${String.fromUtf8(fileContent)}"
        } catch (e: FSException) {
            return "文件路径为空、文件不可读或文件读取失败"
        } catch (e: IllegalArgumentException) {
            return "文件路径包含空字符"
        } catch (e: Exception) {
            return "读取文件失败：${e}"
        }
    }

    @tool[
        description: "Lists the directory structure recursively from the given path, showing files and subdirectories in a tree-like format. Useful for understanding the overall layout and hierarchy of a project or folder.",
        parameters: {
            path: "The absolute path to the directory to visualize."
        }
    ]
    public func tree(path: String): String {
        let pathToTree = Path(path)
        if (!pathToTree.isAbsolute()) {
            return "path must be absolute"
        } else if (!exists(pathToTree)) {
            return "${path} does not exist"
        }

        PrintUtils.printTool("Tree", "path: ${pathToTree}")

        if (!exists(pathToTree)) {
            return "Directory does not exist: ${pathToTree}"
        }

        let builder = StringBuilder()
        treeRecursive(pathToTree, "", true, builder)
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
        let searchPath = if (let Some(p) <- path) {
            p
        } else {
            CliConfig.cwd.toString()
        }

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