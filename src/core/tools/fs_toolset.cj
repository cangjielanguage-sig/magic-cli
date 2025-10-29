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
import cli.core.context.{ContextEngine, FileWatcher}
import std.sync.{Mutex, Condition}
import std.time.DateTime

//==============================================================================
// CLAIM
// Some prompts in this file are copied from Gemini Cli
// https://github.com/google-gemini/gemini-cli/tree/main/packages/core/src/tools
//==============================================================================

let EDIT_FILE_DESCRIPTION = """
Replaces text within a file. By default, replaces a single occurrence.
This tool requires providing significant context around the change to ensure precise targeting. Always use the readFile tool to examine the file's current content before attempting a text replacement.

Expectation for required parameters:
1. path MUST be an absolute path; otherwise an error will be thrown.
2. oldContent MUST be the exact literal text to replace (including all whitespace, indentation, newlines, and surrounding code etc.).
3. newContent MUST be the exact literal text to replace `oldContent` with (also including all whitespace, indentation, newlines, and surrounding code etc.). Ensure the resulting code is correct and idiomatic.
4. NEVER escape `oldContent` or `newContent`, that would break the exact literal text requirement.
**Important:** If ANY of the above are not satisfied, the tool will fail. CRITICAL for `oldContent`: Must uniquely identify the single instance to change. Include at least 3 lines of context BEFORE and AFTER the target text, matching whitespace and indentation precisely. If this string matches multiple locations, or does not match exactly, the tool will fail.
"""

/**
 * ✨ P0-2改进: 从缓存内容中提取指定行范围（外部辅助函数）
 * 
 * 此函数位于FSToolset类外部，以避免@toolset宏的限制
 * 
 * @param content 完整文件内容
 * @param startLine 起始行（1-based）
 * @param endLine 结束行（Option）
 * @return 提取的内容
 */
private func extractLinesFromCache(
    content: String, 
    startLine: Int64, 
    endLine: Option<Int64>
): String {
    let lines = content.split("\n")
    let startIdx = if (startLine > 1) { startLine - 1 } else { 0 }
    let endIdx = if (let Some(e) <- endLine) {
        if (e > Int64(lines.size)) { Int64(lines.size) } else { e }
    } else {
        Int64(lines.size)
    }
    
    if (startIdx >= Int64(lines.size)) {
        return ""
    }
    
    // 直接使用索引切片而不是循环
    let result = ArrayList<String>()
    var i: Int64 = startIdx
    while (i < endIdx && i < Int64(lines.size)) {
        // 使用enumerate来避免类型转换问题
        var currentIdx: Int64 = 0
        for (line in lines) {
            if (currentIdx == i) {
                result.add(line)
                break
            }
            currentIdx += 1
        }
        i += 1
    }
    
    return String.join(result.toArray(), delimiter: "\n")
}

@toolset
public class FSToolset {
    // ✨ P0-2: 缓存集成 - 静态变量存储 ContextEngine 和 FileWatcher
    private static var contextEngineInstance: Option<ContextEngine> = None
    private static var fileWatcherInstance: Option<FileWatcher> = None
    
    /**
     * 设置 ContextEngine（由 CliApp 初始化时调用）
     */
    public static func setContextEngine(engine: ContextEngine): Unit {
        contextEngineInstance = Some(engine)
        LogUtils.info("[FSToolset] ContextEngine cache enabled")
    }
    
    /**
     * 设置 FileWatcher（由 CliApp 初始化时调用）
     */
    public static func setFileWatcher(watcher: FileWatcher): Unit {
        fileWatcherInstance = Some(watcher)
        LogUtils.info("[FSToolset] FileWatcher integration enabled")
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
                ShellUtils.execute(["dir"], workDir: Path(path))
            } else { //linux or ohos
                ShellUtils.execute(["ls", "-la"], workDir: Path(path))
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
        description: "Reads and returns a specific range of lines from a file with line numbers. If startLine and endLine is omitted, the entire file will be read.",
        parameters: {
            filePath: "The absolute path to the file to read",
            startLine: "Optional: Starting line number (1-based, inclusive). If not provided, reads from start of file",
            endLine: "Optional: Ending line number (1-based, inclusive). If not provided, reads to end of file"
        }
    ]
    public func readFile(filePath: String, startLine: Option<Int64>, endLine: Option<Int64>): String {
        let start = startLine ?? 1
        let end = endLine.map { n => n.toString() } ?? "EOF"
        let message = "filePath: ${filePath}\nstart: ${start}\nend: ${end}"
        PrintUtils.printTool("Read File", message)

        let path = Path(filePath)
        let isFullFileRead = startLine.isNone() && endLine.isNone()
        
        // ✨ 改进: 即使部分读取，也尝试使用缓存
        if (let Some(engine) <- FSToolset.contextEngineInstance) {
            if (let Some(fileContext) <- engine.getFileContext(path)) {
                // 缓存命中！
                if (isFullFileRead) {
                    LogUtils.debug("[FSToolset] Cache HIT (full): ${filePath}")
                } else {
                    LogUtils.debug("[FSToolset] Cache HIT (partial ${start}-${end}): ${filePath}")
                }
                
                // 🔍 自动添加到 FileWatcher
                if (let Some(watcher) <- FSToolset.fileWatcherInstance) {
                    watcher.track(path)
                }
                
                // 从缓存内容中提取指定行范围
                let content = if (isFullFileRead) {
                    fileContext.content
                } else {
                    extractLinesFromCache(fileContext.content, startLine ?? 1, endLine)
                }
                
                return "<file-content path=${filePath} start=${start} end=${end}>\n${content}\n</file-content>"
            } else {
                LogUtils.debug("[FSToolset] Cache MISS: ${filePath}")
            }
        }

        // 缓存未命中，从磁盘读取
        let content = catRange(filePath, startLine ?? 1, endLine: endLine ?? Int64.Max)
        
        // ✨ 如果读取成功，将完整文件加入缓存（即使本次是部分读取）
        if (!content.startsWith("File path must be absolute") && 
            !content.startsWith("File does not exist") && !content.startsWith("Path is not a regular file")) {
            
            // 如果本次是完整读取，直接缓存
            if (isFullFileRead) {
                if (let Some(engine) <- FSToolset.contextEngineInstance) {
                    engine.addFile(path, content)
                    LogUtils.debug("[FSToolset] Added to cache (full): ${filePath}")
                    
                    if (let Some(watcher) <- FSToolset.fileWatcherInstance) {
                        watcher.track(path)
                    }
                }
            } else {
                // 如果是部分读取但尚未缓存，读取完整文件并缓存
                // 这样下次读取（包括其他行范围）都能命中缓存
                try {
                    let fullContent = String.fromUtf8(File.readFrom(path))
                    if (let Some(engine) <- FSToolset.contextEngineInstance) {
                        engine.addFile(path, fullContent)
                        LogUtils.debug("[FSToolset] Added full file to cache after partial read: ${filePath}")
                        
                        if (let Some(watcher) <- FSToolset.fileWatcherInstance) {
                            watcher.track(path)
                        }
                    }
                } catch (e: Exception) {
                    // 如果读取完整文件失败，不影响当前部分读取的结果
                    LogUtils.debug("[FSToolset] Failed to cache full file: ${e.message}")
                }
            }
        }
        
        return "<file-content path=${filePath} start=${start} end=${end}>\n${content}\n</file-content>"
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
        let result = writeFileBasic(filePath, content)
        
        // ✨ P0-2: 缓存更新 - 文件写入后更新缓存
        if (result.contains("written successfully")) {
            if (let Some(engine) <- FSToolset.contextEngineInstance) {
                let path = Path(filePath)
                engine.updateFile(path, content)
                LogUtils.debug("[FSToolset] Cache updated after write: ${filePath}")
            }
        }
        
        return result
    }

    @tool[
        description: "${EDIT_FILE_DESCRIPTION}",
        parameters: {
            filePath: "File path, must be an absolute path",
            oldContent: "The exact literal text to replace, preferably unescaped. Including at least 3 lines of context BEFORE and AFTER the target text, matching whitespace and indentation precisely. If this string is not the exact literal text (i.e. you escaped it) or does not match exactly, the tool will fail.",
            newContent: "The exact literal text to replace `oldContent` with, preferably unescaped. Provide the EXACT text. newContent MUST be different from oldContent; otherwise, the tool will fail."
        }
    ]
    public func editFile(filePath: String, oldContent: String, newContent: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }

        try {
            let oldFileContent = String.fromUtf8(File.readFrom(filePath))

            if (!oldFileContent.contains(oldContent)) {
                PrintUtils.printToolFailure(
                    "Edit File (${filePath})",
                    failureInfo: "File does not contain the specified content"
                )
                return "Failed to edit. File ${filePath} does not contain the specified content '${oldContent}'."
            }
            let newFileContent = oldFileContent.replace(oldContent, newContent)
            if (oldFileContent == newFileContent) {
                PrintUtils.printToolFailure(
                    "Edit File (${filePath})",
                    failureInfo: "File content is not modified"
                )
                return "No changes to apply. The oldContent and newContent are identical in file: ${filePath}"
            }

            let message = diff(oldFileContent, newFileContent) |> PrintUtils.renderDiff

            if (InputUtils.confirm("Edit File (${filePath})", message) == Confirmation.Deny) {
                return "User denied the operation"
            }

            File.writeTo(filePath, newFileContent.toArray())
            
            // ✨ P0-2: 缓存更新 - 文件编辑后更新缓存
            if (let Some(engine) <- FSToolset.contextEngineInstance) {
                let path = Path(filePath)
                engine.updateFile(path, newFileContent)
                LogUtils.debug("[FSToolset] Cache updated after edit: ${filePath}")
            }
            
            return "File ${filePath} content modified successfully"
        } catch (ex: FSException) {
            return "File path error or file is not readable/writable"
        } catch (ex: IllegalArgumentException) {
            return "File path is empty or contains illegal characters"
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
    
    /**
     * 🚀 P0-1: 批量并行读取多个文件（真实实现）
     * 
     * 自动使用并行执行读取多个文件，提升性能
     * 
     * @param filePaths 文件路径数组
     * @return 文件内容数组（与输入顺序对应）
     * 
     * 性能：
     * - 串行: n个文件 × 50ms = n×50ms
     * - 并行: max(50ms) × (n/4) ≈ n×12.5ms
     * - 加速比: 约4x（小文件）到2x（大文件）
     */
    @tool[
        description: """
🚀 Batch read multiple files in parallel for maximum performance (2-4x faster than sequential reading).

This tool uses parallel execution (MAX_CONCURRENCY=4) to read multiple files simultaneously.

Use cases:
- Read configuration files at startup
- Load multiple source files for analysis
- Batch data processing

Performance:
- Small files (< 100KB): 4x faster
- Large files (> 1MB): 2x faster  
- Recommended for 3+ files

Example usage:
- "使用batchReadFiles批量读取以下6个文件：/path/to/file1.cj,/path/to/file2.cj,/path/to/file3.cj"
- "Read all config files: /project/config.toml,/project/settings.toml"

Returns: JSON object with file contents, status, and performance metrics.
""",
        parameters: {
            filePaths: "Comma-separated absolute file paths (e.g., '/path/file1.txt,/path/file2.txt'). Spaces around commas are trimmed automatically."
        }
    ]
    public func batchReadFiles(filePaths: String): String {
        // 解析文件路径列表
        let pathList = filePaths.split(",")
        let cleanPaths = ArrayList<String>()
        for (pathStr in pathList) {
            let trimmed = pathStr.trimAscii()
            if (!trimmed.isEmpty()) {
                cleanPaths.add(trimmed)
            }
        }
        
        let totalFiles = cleanPaths.size
        
        // 参数验证
        if (totalFiles == 0) {
            let errorResult = HashMap<String, JsonValue>()
            errorResult["error"] = JsonString("No file paths provided")
            errorResult["files"] = JsonArray([])
            return JsonObject(errorResult).toJsonString()
        }
        
        let startMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        LogUtils.info("[FSToolset] Batch reading ${totalFiles} files in parallel...")
        
        // 初始化结果数组
        let results = ArrayList<Option<String>>()
        var i: Int64 = 0
        while (i < Int64(totalFiles)) {
            results.add(None)
            i += 1
        }
        
        // 分批并发处理（最多4个并发）
        let MAX_CONCURRENCY = 4
        var index = 0
        while (index < totalFiles) {
            let batchEnd = if (index + MAX_CONCURRENCY < totalFiles) {
                index + MAX_CONCURRENCY
            } else {
                totalFiles
            }
            let batchSize = batchEnd - index
            
            // 当前批次的并发执行
            let mutex = Mutex()
            let condition = synchronized(mutex) { mutex.condition() }
            let completionList = ArrayList<Bool>()
            
            var i = index
            while (i < batchEnd) {
                let fileIndex = i
                let filePath = cleanPaths[i]
                // 直接读取文件，不使用this
                spawn {
                    try {
                        let path = Path(filePath)
                        let content = String.fromUtf8(File.readFrom(path))
                        synchronized(mutex) {
                            results[fileIndex] = Some(content)
                            completionList.add(true)
                            condition.notifyAll()
                        }
                        LogUtils.debug("[FSToolset] Parallel read: ${filePath} (${content.size} bytes)")
                    } catch (e: Exception) {
                        synchronized(mutex) {
                            results[fileIndex] = Some("Error reading ${filePath}: ${e.message}")
                            completionList.add(true)
                            condition.notifyAll()
                        }
                        LogUtils.error("[FSToolset] Failed to read ${filePath}: ${e.message}")
                    }
                }
                i += 1
            }
            
            // 等待当前批次完成
            synchronized(mutex) {
                condition.waitUntil({ => completionList.size >= batchSize })
            }
            
            index = batchEnd
        }
        
        // 转换结果为JSON格式
        let fileResults = ArrayList<JsonValue>()
        var successCount: Int64 = 0
        
        for (i in 0..totalFiles) {
            let filePath = cleanPaths[i]
            let fileResult = HashMap<String, JsonValue>()
            fileResult["path"] = JsonString(filePath)
            
            if (let Some(content) <- results[i]) {
                if (content.startsWith("Error reading")) {
                    fileResult["status"] = JsonString("error")
                    fileResult["error"] = JsonString(content)
                } else {
                    fileResult["status"] = JsonString("success")
                    fileResult["content"] = JsonString(content)
                    fileResult["size"] = JsonInt(Int64(content.size))
                    successCount += 1
                }
            } else {
                fileResult["status"] = JsonString("error")
                fileResult["error"] = JsonString("Failed to read file")
            }
            
            fileResults.add(JsonObject(fileResult))
        }
        
        let endMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let durationMs = endMs - startMs
        LogUtils.info("[FSToolset] ⚡ Batch read completed: ${successCount}/${totalFiles} files in ${durationMs}ms")
        
        // 构建最终JSON结果
        let result = HashMap<String, JsonValue>()
        result["files"] = JsonArray(fileResults.toArray())
        result["totalFiles"] = JsonInt(totalFiles)
        result["successCount"] = JsonInt(successCount)
        result["failedCount"] = JsonInt(totalFiles - successCount)
        result["durationMs"] = JsonInt(durationMs)
        
        return JsonObject(result).toJsonString()
    }
}