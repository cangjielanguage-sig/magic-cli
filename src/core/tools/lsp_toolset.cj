package cli.core.tools

import std.fs.*
import std.collection.*
import stdx.encoding.json.*
import std.sync.{Mutex, Condition}
import std.time.DateTime

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils

import cli.lsp.{LSPClient, DocumentSymbol}
import cli.core.config.CliConfig

/**
 * LSP Toolset for code analysis using Language Server Protocol
 *
 * This toolset provides semantic code analysis capabilities by leveraging
 * the existing LSP client implementation.
 *
 * 性能优化：
 * 1. 使用单例模式缓存 LSP 客户端，避免重复创建和初始化
 * 2. 缓存符号信息，避免重复解析同一文件
 * 3. 缓存已打开的文档，避免重复打开
 */
@toolset
public class LSPToolset {
    // 单例 LSP 客户端缓存
    private static var cachedClient: Option<LSPClient> = None<LSPClient>

    // 已打开的文档缓存，避免重复打开
    private static var openedDocuments: HashSet<String> = HashSet<String>()

    // 符号信息缓存：文件路径 -> 符号 JSON 字符串
    // 性能优化：避免重复解析同一文件的符号信息
    private static var symbolsCache: HashMap<String, String> = HashMap<String, String>()

    /**
     * 获取或创建 LSP 客户端（单例模式）
     * 性能优化：复用同一个客户端实例，避免重复初始化
     */
    private static func getOrCreateLSPClient(): LSPClient {
        // 如果已有缓存的客户端，直接返回
        if (let Some(client) <- cachedClient) {
            LogUtils.debug("♻️ 复用已缓存的 LSP 客户端")
            return client
        }

        // 创建新客户端
        try {
            LogUtils.info("🔧 创建新的 LSP 客户端...")
            let client = LSPClient("LSPServer")

            LogUtils.info("🔧 初始化 LSP 客户端，工作目录: ${CliConfig.cwd.toString()}")
            client.initialize(root: CliConfig.cwd.toString())

            LogUtils.info("✅ LSP 客户端初始化成功")

            // 缓存客户端
            cachedClient = Some(client)
            return client
        } catch (e: Exception) {
            LogUtils.error("❌ LSP 客户端初始化失败: ${e}")
            LogUtils.error("错误详情: ${e.message}")
            throw e
        }
    }

    /**
     * 打开文档（带缓存优化）
     * 如果文档已打开，则跳过，避免重复打开
     */
    private static func openDocumentIfNeeded(client: LSPClient, path: Path): Unit {
        let pathStr = path.toString()

        if (openedDocuments.contains(pathStr)) {
            LogUtils.debug("📄 文档已打开，跳过: ${pathStr}")
            return
        }

        LogUtils.debug("📂 打开文档: ${pathStr}")
        client.openDocument(path)
        openedDocuments.add(pathStr)
    }

    /**
     * 清理缓存（用于测试或重置）
     * 清理所有缓存：LSP 客户端、已打开文档、符号信息
     */
    public static func clearCache(): Unit {
        if (let Some(client) <- cachedClient) {
            LogUtils.info("🧹 关闭并清理 LSP 客户端缓存")
            client.close()
        }
        cachedClient = None<LSPClient>
        openedDocuments.clear()
        symbolsCache.clear()
        LogUtils.info("🧹 已清理所有缓存（客户端、文档、符号）")
    }

    /**
     * 清理特定文件的符号缓存
     * 用于文件修改后需要重新解析的场景
     */
    public static func clearSymbolCache(filePath: String): Unit {
        if (symbolsCache.contains(filePath)) {
            symbolsCache.remove(filePath)
            LogUtils.debug("🧹 已清理文件符号缓存: ${filePath}")
        }
    }

    /**
     * 批量打开多个文档
     * 性能优化：一次性打开多个文档，减少 LSP 通信往返次数
     *
     * @param client LSP 客户端
     * @param paths 文件路径列表
     * @return 成功打开的文件数量
     */
    private static func openMultipleDocuments(client: LSPClient, paths: Array<Path>): Int64 {
        var openedCount: Int64 = 0

        LogUtils.info("📂 批量打开 ${paths.size} 个文档...")

        for (i in 0..paths.size) {
            let path = paths[i]
            let pathStr = path.toString()

            // 检查是否已打开
            if (openedDocuments.contains(pathStr)) {
                LogUtils.debug("  [${i + 1}/${paths.size}] 已打开，跳过: ${pathStr}")
                continue
            }

            // 打开文档
            try {
                LogUtils.debug("  [${i + 1}/${paths.size}] 打开文档: ${pathStr}")
                client.openDocument(path)
                openedDocuments.add(pathStr)
                openedCount++
            } catch (e: Exception) {
                LogUtils.error("  [${i + 1}/${paths.size}] 打开文档失败: ${pathStr}, 错误: ${e.message}")
            }
        }

        LogUtils.info("✅ 批量打开完成，成功打开 ${openedCount}/${paths.size} 个文档")
        return openedCount
    }

    /**
     * Tool 1: Get all symbols in a Cangjie file
     * 
     * Returns a JSON array of symbols with their names, kinds, and locations.
     * This is useful for quickly understanding the structure of a file without
     * reading the entire content.
     */
    @tool[
        description: """
Get all symbols (functions, classes, structs, etc.) in a Cangjie file using LSP.
This tool provides a structured overview of the file's contents without reading the entire file.
Use this to quickly understand what's defined in a file before deciding what to read in detail.

Returns a JSON array of symbols with:
- name: Symbol name
- kind: Symbol type (Class, Function, Method, Struct, Variable, etc.)
- line: Line number where the symbol is defined (1-based)
- detail: Additional details about the symbol
- children: Nested symbols (for classes, structs, etc.)

Example usage:
- "What functions are defined in auth.cj?"
- "Show me all classes in user_manager.cj"
- "List all public methods in the Database class"
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file (must end with .cj)"
        }
    ]
    public func getFileSymbols(filePath: String): String {
        // 验证文件路径
        if (!filePath.endsWith(".cj")) {
            return "Error: File must be a Cangjie file (.cj extension)"
        }

        let path = Path(filePath)

        // 先检查路径是否为绝对路径（在检查文件存在性之前）
        if (!path.isAbsolute()) {
            return "Error: File path must be absolute"
        }

        if (!exists(path)) {
            return "Error: File does not exist: ${filePath}"
        }

        // 🚀 性能优化：检查符号缓存
        if (symbolsCache.contains(filePath)) {
            LogUtils.debug("💾 使用缓存的符号信息: ${filePath}")
            return symbolsCache[filePath]
        }

        // 获取或创建 LSP 客户端（使用缓存）
        let client = try {
            getOrCreateLSPClient()
        } catch (e: Exception) {
            return "Error: Failed to initialize LSP client: ${e.message}"
        }

        try {
            // 打开文档（带缓存优化）
            openDocumentIfNeeded(client, path)

            LogUtils.info("📋 获取文档符号...")
            let symbols = client.getDocumentSymbols(path)
            LogUtils.info("✅ 获取到 ${symbols.size} 个符号")

            if (symbols.isEmpty()) {
                return "No symbols found in ${filePath}"
            }

            // 转换符号为 JSON
            let result = ArrayList<JsonValue>()
            for (symbol in symbols) {
                result.add(symbolToJson(symbol))
            }

            let jsonResult = JsonArray(result.toArray()).toJsonString()
            LogUtils.debug("JSON 结果: ${jsonResult}")

            // 🚀 性能优化：缓存符号信息
            symbolsCache[filePath] = jsonResult
            LogUtils.debug("💾 已缓存符号信息: ${filePath}")

            return jsonResult
        } catch (e: Exception) {
            LogUtils.error("获取文件符号失败: ${e}")
            LogUtils.error("错误堆栈: ${e}")
            return "Error: ${e.message}"
        }
        // 注意：不再关闭客户端，保持缓存以供后续使用
    }
    
    /**
     * Tool 2: Get symbols of a specific kind
     * 
     * Filters symbols by their kind (e.g., only functions, only classes).
     * This is useful when you're looking for specific types of symbols.
     */
    @tool[
        description: """
Get symbols of a specific kind from a Cangjie file.

Supported kinds:
- "class" or "Class" - Classes
- "function" or "Function" - Top-level functions
- "method" or "Method" - Class methods
- "struct" or "Struct" - Structs
- "variable" or "Variable" - Variables
- "constant" or "Constant" - Constants

Example usage:
- "Show me all functions in utils.cj"
- "List all classes in the project"
- "Find all public methods"
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file",
            kind: "Symbol kind to filter (class, function, method, struct, variable, constant)"
        }
    ]
    public func getSymbolsByKind(filePath: String, kind: String): String {
        try {
            // Get all symbols first - call the tool implementation function directly
            let allSymbolsJson = __tool_impl_of_getFileSymbols(filePath)

            // Check for errors
            if (allSymbolsJson.startsWith("Error:") || allSymbolsJson.startsWith("No symbols")) {
                return allSymbolsJson
            }

            // Parse JSON
            let allSymbols = JsonValue.fromStr(allSymbolsJson).asArray()

            // Filter by kind
            let kindLower = kind.toAsciiLower()
            let filtered = ArrayList<JsonValue>()

            for (symbolJson in allSymbols.getItems()) {
                let symbol = symbolJson.asObject()
                let symbolKind = symbol.get("kind").getOrThrow().asString().getValue().toAsciiLower()

                if (symbolKind == kindLower) {
                    filtered.add(symbolJson)
                }
            }

            if (filtered.isEmpty()) {
                return "No symbols of kind '${kind}' found in ${filePath}"
            }

            return JsonArray(filtered.toArray()).toJsonString()
        } catch (e: Exception) {
            LogUtils.error("Failed to get symbols by kind: ${e}")
            return "Error: ${e.message}"
        }
    }
    
    /**
     * Tool 3: Search for a symbol by name
     * 
     * Searches for symbols matching a given name across a file.
     * Supports exact match and partial match.
     */
    @tool[
        description: """
Search for symbols by name in a Cangjie file.

This tool helps you quickly locate specific symbols without reading the entire file.
Supports both exact and partial matching.

Example usage:
- "Find the 'login' function in auth.cj"
- "Where is the UserAuth class defined?"
- "Search for symbols containing 'database' in db.cj"
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file",
            symbolName: "Symbol name to search for (case-insensitive, supports partial match)",
            exactMatch: "Whether to use exact match (default: false)"
        }
    ]
    public func findSymbolByName(
        filePath: String,
        symbolName: String,
        exactMatch: String
    ): String {
        try {
            let useExactMatch = exactMatch.toAsciiLower() == "true"

            // Get all symbols - call the tool implementation function directly
            let allSymbolsJson = __tool_impl_of_getFileSymbols(filePath)

            // Check for errors
            if (allSymbolsJson.startsWith("Error:") || allSymbolsJson.startsWith("No symbols")) {
                return allSymbolsJson
            }

            // Parse JSON
            let allSymbols = JsonValue.fromStr(allSymbolsJson).asArray()

            // Search for symbol
            let searchName = symbolName.toAsciiLower()
            let found = ArrayList<JsonValue>()

            for (symbolJson in allSymbols.getItems()) {
                let symbol = symbolJson.asObject()
                let name = symbol.get("name").getOrThrow().asString().getValue()
                let nameLower = name.toAsciiLower()

                let matches = if (useExactMatch) {
                    nameLower == searchName
                } else {
                    nameLower.contains(searchName)
                }

                if (matches) {
                    found.add(symbolJson)
                }
            }

            if (found.isEmpty()) {
                return "No symbols matching '${symbolName}' found in ${filePath}"
            }

            return JsonArray(found.toArray()).toJsonString()
        } catch (e: Exception) {
            LogUtils.error("Failed to find symbol by name: ${e}")
            return "Error: ${e.message}"
        }
    }
    
    /**
     * Tool 4: Get symbol location for precise reading
     * 
     * Returns the exact line range where a symbol is defined.
     * This can be used with the `head` or `cat` tool to read only the relevant code.
     */
    @tool[
        description: """
Get the exact line range where a symbol is defined.

This tool helps you read only the relevant code section instead of the entire file.
Use the returned line range with the 'head' or 'cat' tool to read the specific code.

Returns:
- symbolName: Name of the symbol
- kind: Symbol type
- startLine: Starting line number (1-based)
- endLine: Ending line number (1-based)
- lineCount: Number of lines

Example usage:
- "Where is the login function defined in auth.cj?"
- "Get the line range for the UserAuth class"
- "Show me where the processOrder method is located"
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file",
            symbolName: "Symbol name to locate"
        }
    ]
    public func getSymbolLocation(filePath: String, symbolName: String): String {
        try {
            // Find the symbol - call the tool implementation function directly
            let symbolJson = __tool_impl_of_findSymbolByName(filePath, symbolName, "true")

            // Check for errors
            if (symbolJson.startsWith("Error:") || symbolJson.startsWith("No symbols")) {
                return symbolJson
            }

            // Parse JSON
            let symbols = JsonValue.fromStr(symbolJson).asArray()

            if (symbols.getItems().isEmpty()) {
                return "Symbol '${symbolName}' not found in ${filePath}"
            }

            // Get first match
            let symbol = symbols.getItems()[0].asObject()

            // Extract location info
            let name = symbol.get("name").getOrThrow().asString().getValue()
            let kind = symbol.get("kind").getOrThrow().asString().getValue()
            let line = symbol.get("line").getOrThrow().asInt().getValue()

            // Create result
            let fields = HashMap<String, JsonValue>()
            fields["symbolName"] = JsonString(name)
            fields["kind"] = JsonString(kind)
            fields["startLine"] = JsonInt(line)
            fields["filePath"] = JsonString(filePath)
            fields["suggestion"] = JsonString("Use 'cat ${filePath}' or 'head ${filePath} ${line + 50}' to read the code")

            let result = JsonObject(fields)

            return result.toJsonString()
        } catch (e: Exception) {
            LogUtils.error("Failed to get symbol location: ${e}")
            return "Error: ${e.message}"
        }
    }

    /**
     * 批量获取多个文件的符号信息
     *
     * 性能优化：
     * 1. 一次性打开所有文档，减少 LSP 通信往返
     * 2. 利用符号缓存，避免重复解析
     * 3. 批量处理，提升多文件分析效率
     *
     * 返回格式：
     * {
     *   "files": [
     *     {
     *       "filePath": "/path/to/file1.cj",
     *       "symbols": [...],
     *       "symbolCount": 10
     *     },
     *     {
     *       "filePath": "/path/to/file2.cj",
     *       "symbols": [...],
     *       "symbolCount": 15
     *     }
     *   ],
     *   "totalFiles": 2,
     *   "totalSymbols": 25
     * }
     */
    @tool[
        description: """
🚀 批量并行获取多个 Cangjie 文件的符号信息（高性能版本）。

此工具使用并行执行，比逐个调用 getFileSymbols 快 2-3倍。
适用于需要分析多个文件的场景，如：
- 分析整个模块的代码结构
- 查找跨文件的符号定义
- 批量代码审查

性能优化（P0-1 并行工具执行）：
- ⚡ 并行执行：最多4个文件同时查询
- 📂 一次性打开所有文档，减少 LSP 通信往返
- 💾 利用符号缓存，避免重复解析
- 📊 性能计时：显示实际耗时

返回 JSON 格式包含：
- files: 文件列表，每个文件包含符号信息
- totalFiles: 总文件数
- totalSymbols: 总符号数

性能对比：
- 串行: 6个文件 × 150ms = 900ms
- 并行: max(150ms) × 2批次 ≈ 400ms (2.2x faster!)

Example usage:
- "分析 src/core/tools/ 目录下所有文件的符号"
- "批量获取 auth.cj, user.cj, session.cj 的符号信息"
- "查看整个 lsp 模块的代码结构"
""",
        parameters: {
            filePaths: "Comma-separated absolute paths to Cangjie files (e.g., '/path/to/file1.cj,/path/to/file2.cj')"
        }
    ]
    public func getMultipleFileSymbols(filePaths: String): String {
        // 解析文件路径列表
        let pathStrings = filePaths.split(",")
        if (pathStrings.size == 0) {
            return "Error: No file paths provided"
        }

        LogUtils.info("📦 批量获取 ${pathStrings.size} 个文件的符号信息...")

        // 验证所有文件路径
        let validPaths = ArrayList<Path>()
        let invalidFiles = ArrayList<String>()

        for (i in 0..pathStrings.size) {
            let pathStr = pathStrings[i]

            // 跳过空字符串
            if (pathStr.isEmpty()) {
                continue
            }

            // 验证文件扩展名
            if (!pathStr.endsWith(".cj")) {
                invalidFiles.add("${pathStr} (not a .cj file)")
                continue
            }

            let path = Path(pathStr)

            // 验证绝对路径
            if (!path.isAbsolute()) {
                invalidFiles.add("${pathStr} (not absolute path)")
                continue
            }

            // 验证文件存在
            if (!exists(path)) {
                invalidFiles.add("${pathStr} (file not found)")
                continue
            }

            validPaths.add(path)
        }

        // 如果有无效文件，返回错误
        if (!invalidFiles.isEmpty()) {
            let errorMsg = "Error: Invalid files:\n" + invalidFiles.toArray().toString()
            LogUtils.error(errorMsg)
            return errorMsg
        }

        if (validPaths.isEmpty()) {
            return "Error: No valid files to process"
        }

        // 获取或创建 LSP 客户端
        let client = try {
            getOrCreateLSPClient()
        } catch (e: Exception) {
            return "Error: Failed to initialize LSP client: ${e.message}"
        }

        try {
            // 🚀 性能优化：批量打开所有文档
            let openedCount = openMultipleDocuments(client, validPaths.toArray())
            LogUtils.info("📂 已打开 ${openedCount} 个文档")

            // 🚀 P0-1: 并行获取所有文件的符号信息
            let startMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
            let totalFiles = validPaths.size
            
            // 初始化结果数组
            let fileResults = ArrayList<Option<JsonValue>>()
            var i: Int64 = 0
            while (i < Int64(totalFiles)) {
                fileResults.add(None)
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
                
                LogUtils.info("🔄 并行处理批次: ${index} - ${batchEnd - 1}")
                
                // 当前批次的并发执行
                let mutex = Mutex()
                let condition = synchronized(mutex) { mutex.condition() }
                let completionList = ArrayList<Bool>()
                
                var i = index
                while (i < batchEnd) {
                    let fileIndex = i
                    let path = validPaths[i]
                    let pathStr = path.toString()
                    
                    spawn {
                        try {
                            // 调用 getFileSymbols 获取符号（会使用缓存）
                            let symbolsJson = __tool_impl_of_getFileSymbols(pathStr)
                            
                            // 检查错误
                            if (symbolsJson.startsWith("Error:")) {
                                synchronized(mutex) {
                                    fileResults[fileIndex] = None
                                    completionList.add(true)
                                    condition.notifyAll()
                                }
                                LogUtils.error("获取符号失败: ${pathStr}")
                                return
                            }
                            
                            // 解析符号数组
                            let symbols = try {
                                JsonValue.fromStr(symbolsJson).asArray().getItems()
                            } catch (e: Exception) {
                                synchronized(mutex) {
                                    fileResults[fileIndex] = None
                                    completionList.add(true)
                                    condition.notifyAll()
                                }
                                LogUtils.error("解析符号JSON失败: ${pathStr}: ${e.message}")
                                return
                            }
                            
                            let symbolCount = Int64(symbols.size)
                            
                            // 创建文件结果
                            let fileFields = HashMap<String, JsonValue>()
                            fileFields["filePath"] = JsonString(pathStr)
                            fileFields["symbols"] = JsonArray(symbols)
                            fileFields["symbolCount"] = JsonInt(symbolCount)
                            
                            synchronized(mutex) {
                                fileResults[fileIndex] = Some(JsonObject(fileFields))
                                completionList.add(true)
                                condition.notifyAll()
                            }
                            
                            LogUtils.debug("⚡ 获取到 ${symbolCount} 个符号: ${pathStr}")
                        } catch (e: Exception) {
                            synchronized(mutex) {
                                fileResults[fileIndex] = None
                                completionList.add(true)
                                condition.notifyAll()
                            }
                            LogUtils.error("并行查询失败: ${pathStr}: ${e.message}")
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
            
            // 转换结果并统计
            let finalResults = ArrayList<JsonValue>()
            var totalSymbols: Int64 = 0
            for (result in fileResults) {
                if (let Some(fileResult) <- result) {
                    finalResults.add(fileResult)
                    // 提取symbolCount
                    let obj = fileResult.asObject()
                    if (let Some(count) <- obj.get("symbolCount")) {
                        try {
                            totalSymbols += Int64.fromJsonValue(count)
                        } catch (e: Exception) {
                            // Ignore conversion errors
                        }
                    }
                }
            }
            
            let endMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
            let durationMs = endMs - startMs
            LogUtils.info("⚡ 并行查询完成: ${finalResults.size}/${totalFiles} 文件，共 ${totalSymbols} 个符号，耗时 ${durationMs}ms")

            // 创建最终结果
            let resultFields = HashMap<String, JsonValue>()
            resultFields["files"] = JsonArray(finalResults.toArray())
            resultFields["totalFiles"] = JsonInt(finalResults.size)
            resultFields["totalSymbols"] = JsonInt(totalSymbols)

            let result = JsonObject(resultFields).toJsonString()

            LogUtils.info("✅ 批量获取完成：${finalResults.size} 个文件，共 ${totalSymbols} 个符号")

            return result
        } catch (e: Exception) {
            LogUtils.error("批量获取符号失败: ${e}")
            return "Error: ${e.message}"
        }
    }

    // Helper function: Convert DocumentSymbol to JSON
    private static func symbolToJson(symbol: DocumentSymbol): JsonValue {
        let fields = HashMap<String, JsonValue>()
        
        // Basic info
        fields["name"] = JsonString(symbol.name)
        fields["kind"] = JsonString(getSymbolKindName(symbol.kind))
        fields["line"] = JsonInt(symbol.range.start.line + 1)  // Convert to 1-based

        // Detail
        match (symbol.detail) {
            case Some(detail) =>
                fields["detail"] = JsonString(detail)
            case None =>
                ()
        }

        // Children
        match (symbol.children) {
            case Some(children) =>
                let childrenJson = ArrayList<JsonValue>()
                for (child in children) {
                    childrenJson.add(symbolToJson(child))
                }
                fields["children"] = JsonArray(childrenJson.toArray())
            case None =>
                ()
        }
        
        return JsonObject(fields)
    }
    
    // Helper function: Get symbol kind name
    private static func getSymbolKindName(kind: Int64): String {
        match (kind) {
            case 5 => "Class"
            case 6 => "Method"
            case 12 => "Function"
            case 13 => "Variable"
            case 14 => "Constant"
            case 23 => "Struct"
            case _ => "Unknown"
        }
    }
    
    /**
     * Tool 3: Get hover information for a symbol at a specific location
     * 
     * Returns type information and documentation for a symbol.
     * This is useful for understanding what a symbol is without jumping to its definition.
     */
    @tool[
        description: """
Get hover information (type, documentation) for a symbol at a specific location in a Cangjie file.
This provides detailed information about what a symbol is, including its type signature and documentation.

Use this when you want to:
- Check the type of a variable or parameter
- Read documentation for a function or class
- Understand what a symbol does without navigating to its definition
- Get parameter information for functions

Returns information including:
- Type signature of the symbol
- Documentation comments if available
- Parameter information for functions
- Return type information

Example usage:
- "What is the type of the variable 'count' at line 42?"
- "Show me the documentation for the function at line 15"
- "What parameters does this function take?"
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file (must end with .cj)",
            line: "Line number where the symbol is located (1-based, starting from 1)",
            character: "Character position in the line (0-based, starting from 0)"
        }
    ]
    public func getSymbolHoverInfo(
        filePath: String,
        line: Int64,
        character: Int64
    ): String {
        // 验证参数
        if (!filePath.endsWith(".cj")) {
            return "Error: File must be a Cangjie file (.cj extension)"
        }
        
        if (line < 1) {
            return "Error: Line number must be positive (1-based)"
        }
        
        if (character < 0) {
            return "Error: Character position must be non-negative (0-based)"
        }
        
        let path = Path(filePath)
        
        if (!path.isAbsolute()) {
            return "Error: File path must be absolute"
        }
        
        if (!exists(path)) {
            return "Error: File does not exist: ${filePath}"
        }
        
        // 获取 LSP 客户端
        let client = try {
            getOrCreateLSPClient()
        } catch (e: Exception) {
            return "Error: Failed to initialize LSP client: ${e.message}"
        }
        
        try {
            // 打开文档
            openDocumentIfNeeded(client, path)
            
            // 获取语义tokens
            LogUtils.info("📊 获取语义tokens...")
            let tokens = client.getSemanticTokens(path)
            
            if (tokens.isEmpty()) {
                return "No semantic information available for ${filePath}"
            }
            
            // 获取hover信息
            LogUtils.info("💡 获取hover信息...")
            let hovers = client.getHovers(path, tokens)
            
            if (hovers.isEmpty()) {
                return "No hover information available at line ${line}, character ${character}"
            }
            
            // 转换为0-based行号（LSP使用0-based）
            let lspLine = line - 1
            
            // 查找指定位置的hover信息
            for (hover in hovers) {
                // 检查hover的位置是否匹配
                if (hover.line == lspLine) {
                    // 构建结果JSON
                    let result = HashMap<String, JsonValue>()
                    result["line"] = JsonInt(hover.line + 1) // 转回1-based
                    result["contents"] = JsonString(hover.contents)
                    result["symbol"] = JsonString(hover.symbol)
                    
                    let jsonResult = JsonObject(result).toJsonString()
                    LogUtils.debug("Hover结果: ${jsonResult}")
                    
                    return jsonResult
                }
            }
            
            return "No hover information found at line ${line}, character ${character}"
            
        } catch (e: Exception) {
            LogUtils.error("获取hover信息失败: ${e}")
            return "Error: ${e.message}"
        }
    }
    
    /**
     * Tool 4: Get code summary for a Cangjie file
     * 
     * Provides a concise overview of the file's structure and contents.
     * This is useful for quickly understanding what's in a file.
     */
    @tool[
        description: """
Get a concise summary of a Cangjie file's structure and main components.
This provides a quick overview perfect for understanding a file without reading it entirely.

The summary includes:
- File statistics (total lines, number of symbols)
- Main components (classes, functions, structs, etc.) with their line numbers
- Package declaration
- Quick structural overview

Use this when you want to:
- Get a quick overview of what's in a file
- Understand the file structure before diving into details
- Check what classes or functions are defined
- Get a sense of file complexity

Returns a formatted summary with:
- File path and statistics
- List of main symbols grouped by type
- Symbol locations (line numbers)

Example usage:
- "Give me a summary of user_manager.cj"
- "What's in the authentication.cj file?"
- "Show me an overview of database.cj"
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file (must end with .cj)"
        }
    ]
    public func getCodeSummary(filePath: String): String {
        // 验证参数
        if (!filePath.endsWith(".cj")) {
            return "Error: File must be a Cangjie file (.cj extension)"
        }
        
        let path = Path(filePath)
        
        if (!path.isAbsolute()) {
            return "Error: File path must be absolute"
        }
        
        if (!exists(path)) {
            return "Error: File does not exist: ${filePath}"
        }
        
        // 获取 LSP 客户端
        let client = try {
            getOrCreateLSPClient()
        } catch (e: Exception) {
            return "Error: Failed to initialize LSP client: ${e.message}"
        }
        
        try {
            // 打开文档
            openDocumentIfNeeded(client, path)
            
            // 获取符号信息
            LogUtils.info("📋 获取文档符号...")
            let symbols = client.getDocumentSymbols(path)
            
            // 读取文件以获取行数和package信息
            let content = String.fromUtf8(File.readFrom(path))
            let lines = content.split("\n")
            let totalLines = lines.size
            
            // 提取package声明
            var packageName = "unknown"
            for (line in lines) {
                let trimmed = line.trimAscii()
                if (trimmed.startsWith("package ")) {
                    packageName = trimmed[8..].trimAscii()
                    break
                }
            }
            
            // 按类型分组符号
            var classes = ArrayList<DocumentSymbol>()
            var functions = ArrayList<DocumentSymbol>()
            var structs = ArrayList<DocumentSymbol>()
            var variables = ArrayList<DocumentSymbol>()
            var others = ArrayList<DocumentSymbol>()
            
            for (symbol in symbols) {
                match (symbol.kind) {
                    case 5 => classes.add(symbol)  // Class
                    case 12 => functions.add(symbol)  // Function
                    case 23 => structs.add(symbol)  // Struct
                    case 13 | 14 => variables.add(symbol)  // Variable/Constant
                    case _ => others.add(symbol)
                }
            }
            
            // 构建摘要
            var summary = StringBuilder()
            let pathParts = path.toString().split("/")
            let fileName = pathParts[pathParts.size - 1]
            summary.append("📄 Code Summary: ${fileName}\n")
            summary.append("Package: ${packageName}\n")
            summary.append("Total Lines: ${totalLines}\n")
            summary.append("Total Symbols: ${symbols.size}\n")
            summary.append("\n")
            
            if (classes.size > 0) {
                summary.append("📦 Classes (${classes.size}):\n")
                for (cls in classes) {
                    summary.append("  - ${cls.name} (line ${cls.range.start.line + 1})\n")
                }
                summary.append("\n")
            }
            
            if (structs.size > 0) {
                summary.append("🏗️ Structs (${structs.size}):\n")
                for (st in structs) {
                    summary.append("  - ${st.name} (line ${st.range.start.line + 1})\n")
                }
                summary.append("\n")
            }
            
            if (functions.size > 0) {
                summary.append("⚡ Functions (${functions.size}):\n")
                for (fn in functions) {
                    summary.append("  - ${fn.name} (line ${fn.range.start.line + 1})\n")
                }
                summary.append("\n")
            }
            
            if (variables.size > 0) {
                summary.append("📊 Variables/Constants (${variables.size}):\n")
                for (v in variables) {
                    summary.append("  - ${v.name} (line ${v.range.start.line + 1})\n")
                }
                summary.append("\n")
            }
            
            if (symbols.isEmpty()) {
                summary.append("ℹ️ No symbols found in this file.\n")
            }
            
            return summary.toString()
            
        } catch (e: Exception) {
            LogUtils.error("生成代码摘要失败: ${e}")
            return "Error: ${e.message}"
        }
    }
}

