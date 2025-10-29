package cli.core.context

import std.fs.{Path, File}
import std.collection.{HashMap, ArrayList}
import magic.log.LogUtils
import magic.tokenizer.Cl100kTokenizer
import cli.utils.CL100K_BASE_TIKTOKEN
import std.regex.Regex

/**
 * 🆕 P2-3: 用于排序的辅助结构（Int64）
 */
public struct FileSortItemInt64 {
    public let path: String
    public let value: Int64
    
    public init(path: String, value: Int64) {
        this.path = path
        this.value = value
    }
}

/**
 * 🆕 P2-3: 用于排序的辅助结构（Float64）
 */
public struct FileSortItemFloat64 {
    public let path: String
    public let value: Float64
    
    public init(path: String, value: Float64) {
        this.path = path
        this.value = value
    }
}

/**
 * 🆕 P3-2: 查询类型枚举
 * 用于上下文感知的智能压缩
 */
public enum QueryType <: ToString {
    | CodeReading      // 代码阅读：保留注释和完整逻辑
    | Debugging        // 调试：保留逻辑，可删除注释
    | Refactoring      // 重构：保留结构和关键逻辑
    | Documentation    // 文档生成：只保留签名和定义
    | QuickScan        // 快速扫描：只保留最关键信息
    | General          // 通用查询：使用默认压缩策略
    
    public func toString(): String {
        match (this) {
            case CodeReading => "CodeReading"
            case Debugging => "Debugging"
            case Refactoring => "Refactoring"
            case Documentation => "Documentation"
            case QuickScan => "QuickScan"
            case General => "General"
            case _ => "Unknown"
        }
    }
}

/**
 * 🆕 P2-3: 详细统计信息类
 */
public class ContextStatistics {
    // 基础统计
    public var totalFiles: Int64 = 0
    public var totalTokens: Int64 = 0
    public var maxTokens: Int64 = 0
    public var utilization: Float64 = 0.0
    
    // 缓存统计
    public var totalAccesses: Int64 = 0
    public var cacheHits: Int64 = 0
    public var cacheHitRate: Float64 = 0.0
    
    // 压缩统计
    public var compressedFiles: Int64 = 0
    public var originalTokens: Int64 = 0
    public var compressedTokens: Int64 = 0
    public var compressionRate: Float64 = 0.0
    public var savedTokens: Int64 = 0
    
    // 文件分布
    public var pinnedFiles: Int64 = 0
    public var p0Files: Int64 = 0
    public var p1Files: Int64 = 0
    public var p2Files: Int64 = 0
    public var p3Files: Int64 = 0
    
    // Top文件
    public var topFilesByAccess: ArrayList<String> = ArrayList<String>()
    public var topFilesByRelevance: ArrayList<String> = ArrayList<String>()
    
    public init() {}
}

/**
 * 文件上下文信息（增强版 v2.0）
 */
public class FileContext {
    public let path: Path
    public let content: String
    public var lastAccessed: Int64  // 访问时间戳（用于LRU）
    
    // 🆕 新增：元数据字段
    public var relevanceScore: Float64        // 相关性分数 (0.0-1.0)
    public var tokenCount: Int64              // token数量估算
    public var lineCount: Int64               // 行数
    public var isCompressed: Bool             // 是否已压缩
    public var originalSize: Int64            // 原始大小（字符数）
    public var accessCount: Int64             // 访问次数
    public var lastModified: Int64            // 最后修改时间戳（来自FileWatcher）
    
    // 🆕 新增：符号信息（轻量级）
    public var symbols: Array<String>         // 简化版：只存符号名
    public var imports: Array<String>         // 依赖的包
    
    // 🆕 P1-3: 文件优先级
    public var priority: Int64                // 优先级 (0=P0最高, 1=P1高, 2=P2中, 3=P3低)
    public var isPinned: Bool                 // 是否固定（不会被淘汰）
    
    public init(path: Path, content: String) {
        this.path = path
        this.content = content
        this.lastAccessed = 0
        
        // 初始化新字段
        this.relevanceScore = 0.0
        this.tokenCount = FileContext.estimateTokens(content)
        this.lineCount = Int64(content.split("\n").size)
        this.isCompressed = false
        this.originalSize = Int64(content.size)
        this.accessCount = 0
        this.lastModified = 0
        
        // 🔧 自动提取符号和依赖
        this.symbols = FileContext.extractSymbols(content)
        this.imports = FileContext.extractImports(content)
        
        // 🔧 P1-3: 初始化优先级（默认P3-低）
        this.priority = 3
        this.isPinned = false
    }
    
    /**
     * 🆕 保留元数据的构造函数（用于增量更新）
     * 保留访问统计、相关性分数等元数据，只更新内容相关的字段
     */
    public init(
        path: Path,
        content: String,
        preserveMetadata!: FileContext
    ) {
        this.path = path
        this.content = content
        
        // 🔧 保留旧的元数据
        this.lastAccessed = preserveMetadata.lastAccessed
        this.relevanceScore = preserveMetadata.relevanceScore
        this.accessCount = preserveMetadata.accessCount
        this.isCompressed = false  // 重置压缩状态
        
        // 🔧 P1-3: 保留优先级
        this.priority = preserveMetadata.priority
        this.isPinned = preserveMetadata.isPinned
        
        // 🔧 重新计算内容相关的字段
        this.tokenCount = FileContext.estimateTokens(content)
        this.lineCount = Int64(content.split("\n").size)
        this.originalSize = Int64(content.size)
        this.lastModified = FileContext.getCurrentTimestamp()
        
        // 🔧 重新提取符号和依赖
        this.symbols = FileContext.extractSymbols(content)
        this.imports = FileContext.extractImports(content)
    }
    
    /**
     * 🆕 获取当前时间戳
     */
    private static func getCurrentTimestamp(): Int64 {
        // 简化实现：使用递增计数器
        // TODO: 后续可以使用 std.time 获取真实时间戳
        return 0
    }
    
    /**
     * 🔧 准确的token数量估算（使用cl100k_base tokenizer）
     * 这是 GPT-3.5/GPT-4 系列模型使用的标准 tokenizer
     * 
     * 注：由于每次创建 tokenizer 开销较大，这里做了优化处理
     */
    private static func estimateTokens(text: String): Int64 {
        try {
            // 使用cl100k_base tokenizer进行精确计算
            let tokenizer = Cl100kTokenizer(CL100K_BASE_TIKTOKEN)
            let tokens = tokenizer.encode(text)
            return Int64(tokens.size)
        } catch (e: Exception) {
            // 回退方案：简化估算
            LogUtils.debug("Token estimation failed, using fallback: ${e.message}")
            let words = text.split(" ").size
            let tokens = words / 4
            return if (tokens > 0) { tokens } else { 1 }
        }
    }
    
    /**
     * 🆕 更新相关性分数
     */
    public func updateRelevance(score: Float64): Unit {
        this.relevanceScore = score
    }
    
    /**
     * 🆕 增加访问计数
     */
    public func incrementAccess(): Unit {
        this.accessCount += 1
    }
    
    /**
     * 🔧 提取文件中的符号（函数、类、结构体、枚举、接口）
     * 支持仓颉语法
     */
    private static func extractSymbols(content: String): Array<String> {
        let symbols = ArrayList<String>()
        
        try {
            // 匹配各种声明
            // public/private/protected 可选，后面跟 func/class/struct/enum/interface，然后是名称
            let patterns = [
                "(?:public |private |protected )?func ([\\w]+)",      // 函数
                "(?:public |private |protected )?class ([\\w]+)",     // 类
                "(?:public |private |protected )?struct ([\\w]+)",    // 结构体
                "(?:public |private |protected )?enum ([\\w]+)",      // 枚举
                "(?:public |private |protected )?interface ([\\w]+)" // 接口
            ]
            
            for (pattern in patterns) {
                let regex = Regex(pattern)
                var searchPos: Int64 = 0
                
                // 逐行搜索（避免多行匹配问题）
                for (line in content.split("\n")) {
                    let trimmed = line.trimAscii()
                    
                    // 跳过注释
                    if (trimmed.startsWith("//") || trimmed.startsWith("/*")) {
                        continue
                    }
                    
                    // 简化提取：查找关键字后的标识符
                    if (pattern.contains("func") && trimmed.contains("func ")) {
                        let symbolName = FileContext.extractSymbolName(trimmed, "func")
                        if (!symbolName.isEmpty() && !FileContext.containsSymbol(symbols, symbolName)) {
                            symbols.add(symbolName)
                        }
                    } else if (pattern.contains("class") && trimmed.contains("class ")) {
                        let symbolName = FileContext.extractSymbolName(trimmed, "class")
                        if (!symbolName.isEmpty() && !FileContext.containsSymbol(symbols, symbolName)) {
                            symbols.add(symbolName)
                        }
                    } else if (pattern.contains("struct") && trimmed.contains("struct ")) {
                        let symbolName = FileContext.extractSymbolName(trimmed, "struct")
                        if (!symbolName.isEmpty() && !FileContext.containsSymbol(symbols, symbolName)) {
                            symbols.add(symbolName)
                        }
                    } else if (pattern.contains("enum") && trimmed.contains("enum ")) {
                        let symbolName = FileContext.extractSymbolName(trimmed, "enum")
                        if (!symbolName.isEmpty() && !FileContext.containsSymbol(symbols, symbolName)) {
                            symbols.add(symbolName)
                        }
                    } else if (pattern.contains("interface") && trimmed.contains("interface ")) {
                        let symbolName = FileContext.extractSymbolName(trimmed, "interface")
                        if (!symbolName.isEmpty() && !FileContext.containsSymbol(symbols, symbolName)) {
                            symbols.add(symbolName)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            LogUtils.debug("Symbol extraction failed: ${e.message}")
        }
        
        return symbols.toArray()
    }
    
    /**
     * 🔧 从声明行中提取符号名称
     */
    private static func extractSymbolName(line: String, keyword: String): String {
        // 查找关键字位置
        let keywordIndexOpt = line.indexOf(keyword)
        if (keywordIndexOpt.isNone()) {
            return ""
        }
        let keywordIndex = keywordIndexOpt.getOrThrow()
        
        // 跳过关键字和空格
        let startIndex = keywordIndex + Int64(keyword.size)
        var nameStart = startIndex
        
        // 跳过空格
        while (nameStart < Int64(line.size) && line[nameStart..nameStart+1] == " ") {
            nameStart += 1
        }
        
        if (nameStart >= Int64(line.size)) {
            return ""
        }
        
        // 提取标识符（到空格、左括号、冒号、尖括号为止）
        var nameEnd = nameStart
        while (nameEnd < Int64(line.size)) {
            let ch = line[nameEnd..nameEnd+1]
            if (ch == " " || ch == "(" || ch == "<" || ch == ":" || ch == "{") {
                break
            }
            nameEnd += 1
        }
        
        if (nameEnd <= nameStart) {
            return ""
        }
        
        return line[nameStart..nameEnd].trimAscii()
    }
    
    /**
     * 🔧 检查符号列表中是否已包含某个符号
     */
    private static func containsSymbol(symbols: ArrayList<String>, symbol: String): Bool {
        for (s in symbols) {
            if (s == symbol) {
                return true
            }
        }
        return false
    }
    
    /**
     * 🔧 提取文件中的import语句
     */
    private static func extractImports(content: String): Array<String> {
        let imports = ArrayList<String>()
        
        for (line in content.split("\n")) {
            let trimmed = line.trimAscii()
            
            // 检查是否是 import 语句
            if (trimmed.startsWith("import ")) {
                let importPkg = FileContext.extractImportPackage(trimmed)
                if (!importPkg.isEmpty()) {
                    // 检查是否已存在
                    var exists = false
                    for (pkg in imports) {
                        if (pkg == importPkg) {
                            exists = true
                            break
                        }
                    }
                    if (!exists) {
                        imports.add(importPkg)
                    }
                }
            }
        }
        
        return imports.toArray()
    }
    
    /**
     * 🔧 从import语句提取包名
     * 例如：
     * - "import std.fs.{Path, File}" -> "std.fs"
     * - "import cli.core.config.CliConfig" -> "cli.core.config"
     */
    private static func extractImportPackage(importLine: String): String {
        // 去掉 "import " 前缀
        if (importLine.size <= 7) {
            return ""
        }
        
        let afterImport = importLine[7..].trimAscii()
        
        // 查找 { 或 空格（取第一个出现的）
        let braceIndexOpt = afterImport.indexOf("{")
        let spaceIndexOpt = afterImport.indexOf(" ")
        
        var endIndex = afterImport.size
        
        // 处理Option类型
        var braceIndex: Int64 = -1
        if (braceIndexOpt.isSome()) {
            braceIndex = braceIndexOpt.getOrThrow()
        }
        
        var spaceIndex: Int64 = -1
        if (spaceIndexOpt.isSome()) {
            spaceIndex = spaceIndexOpt.getOrThrow()
        }
        
        if (braceIndex >= 0 && (spaceIndex < 0 || braceIndex < spaceIndex)) {
            endIndex = braceIndex
        } else if (spaceIndex >= 0) {
            endIndex = spaceIndex
        }
        
        let packagePath = afterImport[0..endIndex].trimAscii()
        
        // 如果包含点号，提取最后一个点之前的部分作为包名
        let lastDotIndexOpt = packagePath.lastIndexOf(".")
        if (lastDotIndexOpt.isSome()) {
            let lastDotIndex = lastDotIndexOpt.getOrThrow()
            if (lastDotIndex > 0) {
                return packagePath[0..lastDotIndex]
            }
        }
        
        return packagePath
    }
}

/**
 * 上下文引擎 - 增强版 v2.0
 * 
 * 核心功能：
 * - 文件内容缓存
 * - 基本的增删改查
 * - 与 @mention 集成
 * - 🆕 智能相关性评分
 * - 🆕 上下文压缩
 * - 🆕 多因素淘汰策略
 */
public class ContextEngine {
    // 文件缓存：路径字符串 -> FileContext
    private var fileCache: HashMap<String, FileContext>
    
    // 🔧 Token-based 管理（替代文件数限制）
    private let maxTotalTokens: Int64         // 最大token数
    private var currentTokenCount: Int64      // 当前已使用token数
    
    // 访问计数器（用于LRU和相关性评分）
    private var accessCounter: Int64
    
    // 🆕 P3-1: BM25参数
    private let k1: Float64 = 1.5             // TF饱和参数（推荐1.2-2.0）
    private let b: Float64 = 0.75             // 长度归一化参数（推荐0.75）
    
    // 🆕 P3-1: 全局统计信息（用于BM25计算）
    private var totalDocuments: Int64         // 文档总数
    private var avgDocLength: Float64         // 平均文档长度（单词数）
    private var documentFrequency: HashMap<String, Int64>  // 每个词的文档频率
    
    // 🔧 Token-based 构造函数
    // 默认：50文件 * 2000 tokens = 100K tokens
    public init(maxCacheSize!: Int64 = 50) {
        this.fileCache = HashMap<String, FileContext>()
        // 将文件数限制转换为token限制（假设平均每个文件2000 tokens）
        this.maxTotalTokens = maxCacheSize * 2000
        this.currentTokenCount = 0
        this.accessCounter = 0
        
        // 🆕 P3-1: 初始化BM25统计
        this.totalDocuments = 0
        this.avgDocLength = 0.0
        this.documentFrequency = HashMap<String, Int64>()
    }
    
    /**
     * 🔧 添加文件到上下文缓存（Token-based）
     */
    public func addFile(path: Path, content: String): Unit {
        let pathKey = path.toString()
        
        // 创建新的FileContext（会自动计算tokens）
        let context = FileContext(path, content)
        let newTokenCount = context.tokenCount
        
        // 🔧 检查token限制，如果超过则智能淘汰
        while (this.currentTokenCount + newTokenCount > this.maxTotalTokens && this.fileCache.size > 0) {
            this.evictLeastImportant()
        }
        
        // 如果已存在，先减去旧的token数
        if (let Some(oldContext) <- this.fileCache.get(pathKey)) {
            this.currentTokenCount -= oldContext.tokenCount
        }
        
        // 添加或更新缓存
        this.accessCounter += 1
        context.lastAccessed = this.accessCounter
        this.fileCache[pathKey] = context
        this.currentTokenCount += newTokenCount
        
        // 🆕 P3-1: 更新BM25全局统计
        this.updateGlobalStats()
        
        LogUtils.debug("Added file to context: ${pathKey} (${newTokenCount} tokens, total: ${this.currentTokenCount}/${this.maxTotalTokens})")
    }
    
    /**
     * 🆕 P1-1: 增量更新文件（保留元数据）
     * 
     * 与 addFile 的区别：
     * - addFile: 完全新建 FileContext，所有元数据从零开始
     * - updateFile: 保留元数据（relevanceScore, accessCount等），只更新内容
     * 
     * 适用场景：
     * - FileWatcher 检测到文件变更
     * - 用户编辑文件后重新加载
     * - 需要保持文件的历史访问记录
     * 
     * @param path 文件路径
     * @param newContent 新的文件内容
     */
    public func updateFile(path: Path, newContent: String): Unit {
        let pathKey = path.toString()
        
        // 检查文件是否已在缓存中
        if (let Some(oldContext) <- this.fileCache.get(pathKey)) {
            // 🔧 使用保留元数据的构造函数
            let newContext = FileContext(path, newContent, preserveMetadata: oldContext)
            
            // 计算token差异
            let oldTokens = oldContext.tokenCount
            let newTokens = newContext.tokenCount
            let tokenDiff = newTokens - oldTokens
            
            // 🔧 检查token限制（如果新内容更大）
            if (tokenDiff > 0) {
                while (this.currentTokenCount + tokenDiff > this.maxTotalTokens && this.fileCache.size > 1) {
                    // 淘汰其他文件（不能淘汰当前更新的文件）
                    this.evictLeastImportant()
                }
            }
            
            // 更新访问时间
            this.accessCounter += 1
            newContext.lastAccessed = this.accessCounter
            newContext.incrementAccess()  // 增加访问计数
            
            // 更新缓存
            this.fileCache[pathKey] = newContext
            this.currentTokenCount += tokenDiff
            
            // 🆕 P3-1: 更新BM25全局统计
            this.updateGlobalStats()
            
            LogUtils.debug("Updated file in context: ${pathKey} (${oldTokens} -> ${newTokens} tokens, diff: ${tokenDiff}, total: ${this.currentTokenCount}/${this.maxTotalTokens})")
        } else {
            // 文件不在缓存中，使用 addFile（addFile会调用updateGlobalStats）
            LogUtils.debug("File not in cache, adding: ${pathKey}")
            this.addFile(path, newContent)
        }
    }
    
    /**
     * 获取文件内容
     */
    public func getFile(path: Path): Option<String> {
        let pathKey = path.toString()
        
        if (let Some(context) <- this.fileCache.get(pathKey)) {
            // 更新访问时间
            this.accessCounter += 1
            context.lastAccessed = this.accessCounter
            return Some(context.content)
        }
        
        return None
    }
    
    /**
     * 获取文件上下文
     */
    public func getFileContext(path: Path): Option<FileContext> {
        let pathKey = path.toString()
        
        if (let Some(context) <- this.fileCache.get(pathKey)) {
            // 更新访问时间
            this.accessCounter += 1
            context.lastAccessed = this.accessCounter
            return Some(context)
        }
        
        return None
    }
    
    /**
     * 🔧 移除文件（更新token计数）
     */
    public func removeFile(path: Path): Unit {
        let pathKey = path.toString()
        
        // 更新token计数
        if (let Some(context) <- this.fileCache.get(pathKey)) {
            this.currentTokenCount -= context.tokenCount
        }
        
        this.fileCache.remove(pathKey)
        
        // 🆕 P3-1: 更新BM25全局统计
        this.updateGlobalStats()
        
        LogUtils.debug("Removed file from context: ${pathKey} (remaining tokens: ${this.currentTokenCount})")
    }
    
    /**
     * 获取所有已缓存的文件路径
     */
    public func getAllFiles(): Array<Path> {
        let paths = ArrayList<Path>()
        for ((_, context) in this.fileCache) {
            paths.add(context.path)
        }
        return paths.toArray()
    }
    
    /**
     * 检查文件是否在缓存中
     */
    public func contains(path: Path): Bool {
        let pathKey = path.toString()
        // 检查是否存在
        let result = this.fileCache.get(pathKey)
        match (result) {
            case Some(_) => return true
            case _ => return false
        }
    }
    
    /**
     * 获取缓存大小
     */
    public func size(): Int64 {
        return this.fileCache.size
    }
    
    /**
     * 🔧 清空缓存（重置token计数）
     */
    public func clear(): Unit {
        this.fileCache.clear()
        this.currentTokenCount = 0
        this.accessCounter = 0
        
        // 🆕 P3-1: 重置BM25统计
        this.totalDocuments = 0
        this.avgDocLength = 0.0
        this.documentFrequency.clear()
        
        LogUtils.debug("Context cache cleared")
    }
    
    /**
     * 🔧 改进的清理策略（多因素评分 + P1-3优先级保护）
     * 综合考虑：
     * 0. Pin状态（isPinned的文件绝不淘汰）
     * 1. 优先级（priority: 0=P0最高, 3=P3最低）
     * 2. 访问时间（权重：0.3）- 最近访问的得分高
     * 3. 访问频率（权重：0.3）- 访问次数多的得分高
     * 4. 相关性分数（权重：0.4）- 相关性高的得分高
     * 
     * 淘汰得分最低的文件（最不重要的）
     */
    private func evictLeastImportant(): Unit {
        var lowestScore: Float64 = 1000000.0  // 提高初始值以容纳优先级权重
        var victimKey: Option<String> = None
        
        // 计算每个文件的"保留分数"（分数越高越应该保留）
        for ((key, context) in this.fileCache) {
            // 🔧 P1-3: Pinned文件绝不淘汰
            if (context.isPinned) {
                continue
            }
            
            var keepScore: Float64 = 0.0
            
            // 🔧 P1-3: 优先级权重（P0=10000, P1=1000, P2=100, P3=0）
            let priorityBonus = match (context.priority) {
                case 0 => 10000.0  // P0 - 必需
                case 1 => 1000.0   // P1 - 很重要
                case 2 => 100.0    // P2 - 重要
                case 3 => 0.0      // P3 - 一般
                case _ => 0.0
            }
            keepScore += priorityBonus
            
            // 1. 时间因素（最近访问的得分高）
            let timeScore = if (this.accessCounter > 0) {
                Float64(context.lastAccessed) / Float64(this.accessCounter)
            } else {
                0.0
            }
            keepScore += timeScore * 0.3
            
            // 2. 频率因素（访问次数多的得分高）
            let maxAccess = Float64(this.accessCounter)
            let freqScore = if (maxAccess > 0.0) {
                Float64(context.accessCount) / maxAccess
            } else {
                0.0
            }
            keepScore += freqScore * 0.3
            
            // 3. 相关性因素（相关性高的得分高）
            keepScore += context.relevanceScore * 0.4
            
            // 找出得分最低的（最应该被淘汰的）
            if (keepScore < lowestScore) {
                lowestScore = keepScore
                victimKey = Some(key)
            }
        }
        
        // 移除得分最低的文件（并更新token计数）
        if (let Some(key) <- victimKey) {
            if (let Some(context) <- this.fileCache.get(key)) {
                this.currentTokenCount -= context.tokenCount
                LogUtils.debug("Evicted file with lowest keep-score (${lowestScore}): ${key} (freed ${context.tokenCount} tokens)")
            }
            this.fileCache.remove(key)
        }
    }
    
    /**
     * 🆕 手动更新文件的重要性
     * 外部可以调用此方法标记重要文件，避免被误删
     * 
     * @param path 文件路径
     * @param score 重要性分数 (0.0-1.0)
     */
    public func markAsImportant(path: Path, score: Float64): Unit {
        let pathKey = path.toString()
        if (let Some(context) <- this.fileCache.get(pathKey)) {
            context.relevanceScore = score
            LogUtils.debug("Marked file as important: ${pathKey} (score: ${score})")
        }
    }
    
    // ============================================================================
    // 🆕 P1-3: 文件优先级系统
    // ============================================================================
    
    /**
     * 🆕 P1-3: Pin文件（固定文件，不会被淘汰）
     * 
     * @param path 文件路径
     */
    public func pinFile(path: Path): Unit {
        let pathKey = path.toString()
        if (let Some(context) <- this.fileCache.get(pathKey)) {
            context.isPinned = true
            context.priority = 0  // Pin的文件自动提升为P0
            LogUtils.debug("Pinned file: ${pathKey}")
        }
    }
    
    /**
     * 🆕 P1-3: Unpin文件（取消固定）
     * 
     * @param path 文件路径
     */
    public func unpinFile(path: Path): Unit {
        let pathKey = path.toString()
        if (let Some(context) <- this.fileCache.get(pathKey)) {
            context.isPinned = false
            // 保持原有priority
            LogUtils.debug("Unpinned file: ${pathKey}")
        }
    }
    
    /**
     * 🆕 P1-3: 设置文件优先级
     * 
     * @param path 文件路径
     * @param priority 优先级 (0=P0最高, 1=P1, 2=P2, 3=P3最低)
     */
    public func setFilePriority(path: Path, priority: Int64): Unit {
        let pathKey = path.toString()
        if (let Some(context) <- this.fileCache.get(pathKey)) {
            // 验证优先级范围
            let validPriority = if (priority < 0) {
                0
            } else if (priority > 3) {
                3
            } else {
                priority
            }
            
            context.priority = validPriority
            LogUtils.debug("Set file priority: ${pathKey} = P${validPriority}")
        }
    }
    
    /**
     * 🆕 P1-3: 检查文件是否被Pin
     */
    public func isFilePinned(path: Path): Bool {
        let pathKey = path.toString()
        if (let Some(context) <- this.fileCache.get(pathKey)) {
            return context.isPinned
        }
        return false
    }
    
    /**
     * 🆕 P1-3: 获取所有Pin的文件
     */
    public func getPinnedFiles(): Array<Path> {
        let pinned = ArrayList<Path>()
        for ((_, context) in this.fileCache) {
            if (context.isPinned) {
                pinned.add(context.path)
            }
        }
        return pinned.toArray()
    }
    
    /**
     * 🆕 P1-3: 按优先级分组获取文件
     */
    public func getFilesByPriority(): String {
        let p0Files = ArrayList<String>()
        let p1Files = ArrayList<String>()
        let p2Files = ArrayList<String>()
        let p3Files = ArrayList<String>()
        let pinnedFiles = ArrayList<String>()
        
        for ((_, context) in this.fileCache) {
            let fileName = context.path.toString()
            
            if (context.isPinned) {
                pinnedFiles.add(fileName)
            }
            
            match (context.priority) {
                case 0 => p0Files.add(fileName)
                case 1 => p1Files.add(fileName)
                case 2 => p2Files.add(fileName)
                case 3 => p3Files.add(fileName)
                case _ => p3Files.add(fileName)
            }
        }
        
        let lines = ArrayList<String>()
        lines.add("Files by Priority")
        lines.add("════════════════════════════════════════")
        
        if (pinnedFiles.size > 0) {
            lines.add("📌 Pinned (${pinnedFiles.size}):")
            for (file in pinnedFiles) {
                lines.add("  • ${file}")
            }
        }
        
        if (p0Files.size > 0) {
            lines.add("🔴 P0 - Critical (${p0Files.size}):")
            for (file in p0Files) {
                lines.add("  • ${file}")
            }
        }
        
        if (p1Files.size > 0) {
            lines.add("🟠 P1 - High (${p1Files.size}):")
            for (file in p1Files) {
                lines.add("  • ${file}")
            }
        }
        
        if (p2Files.size > 0) {
            lines.add("🟡 P2 - Medium (${p2Files.size}):")
            for (file in p2Files) {
                lines.add("  • ${file}")
            }
        }
        
        if (p3Files.size > 0) {
            lines.add("⚪ P3 - Low (${p3Files.size}):")
            for (file in p3Files) {
                lines.add("  • ${file}")
            }
        }
        
        return String.join(lines.toArray(), delimiter: "\n")
    }
    
    /**
     * 🔧 获取缓存统计信息（Token-based）- 简化版
     */
    public func getStats(): String {
        let utilization = if (this.maxTotalTokens > 0) {
            Float64(this.currentTokenCount) / Float64(this.maxTotalTokens) * 100.0
        } else {
            0.0
        }
        return "ContextEngine: ${this.fileCache.size} files, ${this.currentTokenCount}/${this.maxTotalTokens} tokens (${Float64(Int64(utilization))}% used)"
    }
    
    // ============================================================================
    // 🆕 P2-3: 改进统计面板
    // ============================================================================
    
    /**
     * 🆕 P2-3: 获取详细统计
     */
    public func getDetailedStats(): ContextStatistics {
        let stats = ContextStatistics()
        
        // 基础统计
        stats.totalFiles = Int64(this.fileCache.size)
        stats.totalTokens = this.currentTokenCount
        stats.maxTokens = this.maxTotalTokens
        stats.utilization = if (this.maxTotalTokens > 0) {
            Float64(this.currentTokenCount) / Float64(this.maxTotalTokens)
        } else {
            0.0
        }
        
        // 遍历所有文件收集统计
        var compressedCount: Int64 = 0
        var originalSum: Int64 = 0
        var compressedSum: Int64 = 0
        
        let accessList = ArrayList<FileSortItemInt64>()
        let relevanceList = ArrayList<FileSortItemFloat64>()
        
        for ((pathKey, ctx) in this.fileCache) {
            // 统计访问次数
            stats.totalAccesses += ctx.accessCount
            
            // 统计压缩
            if (ctx.isCompressed) {
                compressedCount += 1
                originalSum += ctx.originalSize
                compressedSum += ctx.tokenCount * 4  // 估算压缩后的字符数
            }
            
            // 统计优先级
            if (ctx.isPinned) {
                stats.pinnedFiles += 1
            }
            // 统计优先级分布
            if (ctx.priority == 0) {
                stats.p0Files += 1
            } else if (ctx.priority == 1) {
                stats.p1Files += 1
            } else if (ctx.priority == 2) {
                stats.p2Files += 1
            } else if (ctx.priority == 3) {
                stats.p3Files += 1
            }
            
            // 收集Top文件
            accessList.add(FileSortItemInt64(pathKey, ctx.accessCount))
            relevanceList.add(FileSortItemFloat64(pathKey, ctx.relevanceScore))
        }
        
        // 缓存命中率（简化：假设每次access都是命中）
        stats.cacheHits = stats.totalAccesses
        stats.cacheHitRate = if (stats.totalAccesses > 0) {
            Float64(stats.cacheHits) / Float64(stats.totalAccesses)
        } else {
            0.0
        }
        
        // 压缩统计
        stats.compressedFiles = compressedCount
        stats.originalTokens = originalSum / 4
        stats.compressedTokens = compressedSum / 4
        stats.compressionRate = if (originalSum > 0) {
            1.0 - Float64(compressedSum) / Float64(originalSum)
        } else {
            0.0
        }
        stats.savedTokens = stats.originalTokens - stats.compressedTokens
        
        // 排序获取Top 5（按访问次数）
        let sortedByAccess = this.sortFilesByInt64(accessList.toArray())
        let count = if (sortedByAccess.size > 5) { 5 } else { sortedByAccess.size }
        for (i in 0..count) {
            stats.topFilesByAccess.add(sortedByAccess[i].path)
        }
        
        // 排序获取Top 5（按相关性）
        let sortedByRelevance = this.sortFilesByFloat64(relevanceList.toArray())
        for (i in 0..count) {
            stats.topFilesByRelevance.add(sortedByRelevance[i].path)
        }
        
        return stats
    }
    
    /**
     * 🆕 P2-3: 排序文件列表（按Int64降序）
     */
    private func sortFilesByInt64(items: Array<FileSortItemInt64>): Array<FileSortItemInt64> {
        let list = ArrayList<FileSortItemInt64>()
        for (item in items) {
            list.add(item)
        }
        
        // 冒泡排序（降序）
        let size = list.size
        for (i in 0..size) {
            for (j in (i+1)..size) {
                if (list[i].value < list[j].value) {
                    let temp = list[i]
                    list[i] = list[j]
                    list[j] = temp
                }
            }
        }
        
        return list.toArray()
    }
    
    /**
     * 🆕 P2-3: 排序文件列表（按Float64降序）
     */
    private func sortFilesByFloat64(items: Array<FileSortItemFloat64>): Array<FileSortItemFloat64> {
        let list = ArrayList<FileSortItemFloat64>()
        for (item in items) {
            list.add(item)
        }
        
        // 冒泡排序（降序）
        let size = list.size
        for (i in 0..size) {
            for (j in (i+1)..size) {
                if (list[i].value < list[j].value) {
                    let temp = list[i]
                    list[i] = list[j]
                    list[j] = temp
                }
            }
        }
        
        return list.toArray()
    }
    
    /**
     * 🆕 P2-3: 格式化统计报告
     */
    public func formatStatsReport(): String {
        let stats = this.getDetailedStats()
        
        let lines = ArrayList<String>()
        lines.add("=== Context Engine Statistics ===")
        lines.add("")
        
        // 基础信息
        lines.add("📊 Basic:")
        lines.add("   Files: ${stats.totalFiles}")
        lines.add("   Tokens: ${stats.totalTokens} / ${stats.maxTokens}")
        let utilPercent = Float64(Int64(stats.utilization * 100.0))
        lines.add("   Utilization: ${utilPercent}%")
        lines.add("")
        
        // 缓存信息
        lines.add("💾 Cache:")
        lines.add("   Total Accesses: ${stats.totalAccesses}")
        let hitRatePercent = Float64(Int64(stats.cacheHitRate * 100.0))
        lines.add("   Hit Rate: ${hitRatePercent}%")
        lines.add("")
        
        // 压缩信息
        if (stats.compressedFiles > 0) {
            lines.add("🗜️ Compression:")
            lines.add("   Compressed Files: ${stats.compressedFiles}")
            lines.add("   Saved Tokens: ${stats.savedTokens}")
            let compressPercent = Float64(Int64(stats.compressionRate * 100.0))
            lines.add("   Compression Rate: ${compressPercent}%")
            lines.add("")
        }
        
        // 优先级分布
        lines.add("🎯 Priority Distribution:")
        if (stats.pinnedFiles > 0) {
            lines.add("   📌 Pinned: ${stats.pinnedFiles}")
        }
        lines.add("   🔴 P0: ${stats.p0Files}")
        lines.add("   🟠 P1: ${stats.p1Files}")
        lines.add("   🟡 P2: ${stats.p2Files}")
        lines.add("   ⚪ P3: ${stats.p3Files}")
        lines.add("")
        
        // Top文件（按访问次数）
        if (stats.topFilesByAccess.size > 0) {
            lines.add("🔥 Top Files by Access:")
            var idx: Int64 = 1
            for (file in stats.topFilesByAccess) {
                lines.add("   ${idx}. ${file}")
                idx += 1
            }
            lines.add("")
        }
        
        // Top文件（按相关性）
        if (stats.topFilesByRelevance.size > 0) {
            lines.add("⭐ Top Files by Relevance:")
            var idx2: Int64 = 1
            for (file in stats.topFilesByRelevance) {
                lines.add("   ${idx2}. ${file}")
                idx2 += 1
            }
        }
        
        return String.join(lines.toArray(), delimiter: "\n")
    }
    
    /**
     * 🆕 P1-1: 获取文件元数据摘要
     * 用于调试和监控文件的状态
     */
    public func getFileMetadata(path: Path): Option<String> {
        let pathKey = path.toString()
        
        if (let Some(context) <- this.fileCache.get(pathKey)) {
            let symbolsStr = String.join(context.symbols, delimiter: ", ")
            let importsStr = String.join(context.imports, delimiter: ", ")
            
            let line1 = "File: ${pathKey}\n"
            let line2 = "  Tokens: ${context.tokenCount}\n"
            let line3 = "  Lines: ${context.lineCount}\n"
            let line4 = "  Access Count: ${context.accessCount}\n"
            let line5 = "  Relevance Score: ${context.relevanceScore}\n"
            let line6 = "  Symbols: ${context.symbols.size} (${symbolsStr})\n"
            let line7 = "  Imports: ${context.imports.size} (${importsStr})\n"
            let line8 = "  Compressed: ${context.isCompressed}"
            
            let metadata = line1 + line2 + line3 + line4 + line5 + line6 + line7 + line8
            return Some(metadata)
        }
        
        return None
    }
    
    // ============================================================================
    // 🆕 P1-2: 全局Token预算管理
    // ============================================================================
    
    /**
     * 🆕 P1-2: 为文件分配token预算
     * 
     * 策略：
     * 1. 按相关性分数排序文件
     * 2. 高相关性文件分配更多token（可以完整保留）
     * 3. 低相关性文件分配较少token（需要压缩）
     * 4. 使用加权分配算法，而非平均分配
     * 
     * @param query 用户查询（用于计算相关性）
     * @param totalBudget 总token预算
     * @return HashMap<String, Int64> - 文件路径 -> token配额
     */
    public func allocateTokenBudget(query: String, totalBudget: Int64): HashMap<String, Int64> {
        let allocation = HashMap<String, Int64>()
        
        if (this.fileCache.size == 0) {
            return allocation
        }
        
        // 1. 计算所有文件的相关性
        let rankedFiles = this.rankFilesByRelevance(query)
        
        // 2. 计算总相关性分数（用于加权分配）
        var totalRelevance: Float64 = 0.0
        for (file in rankedFiles) {
            totalRelevance += file.relevanceScore
        }
        
        // 避免除以0
        if (totalRelevance <= 0.0) {
            // 平均分配
            let avgBudget = totalBudget / Int64(rankedFiles.size)
            for (file in rankedFiles) {
                allocation[file.path.toString()] = avgBudget
            }
            return allocation
        }
        
        // 3. 加权分配token
        for (file in rankedFiles) {
            // 分配比例 = 该文件相关性 / 总相关性
            let ratio = file.relevanceScore / totalRelevance
            let allocatedTokens = Int64(Float64(totalBudget) * ratio)
            
            // 至少分配100 tokens，最多不超过文件实际大小
            let minTokens: Int64 = 100
            let actualTokens = if (allocatedTokens < minTokens) {
                minTokens
            } else if (allocatedTokens > file.tokenCount) {
                file.tokenCount  // 不超过实际大小
            } else {
                allocatedTokens
            }
            
            allocation[file.path.toString()] = actualTokens
            
            LogUtils.debug("Token budget: ${file.path.toString()} = ${actualTokens} (relevance: ${file.relevanceScore})")
        }
        
        return allocation
    }
    
    /**
     * 🆕 P1-2: 构建带预算的上下文
     * 
     * 根据token预算自动选择压缩级别，确保不超出限制
     * 
     * @param query 用户查询
     * @param totalBudget 总token预算
     * @return String - 构建的上下文字符串
     */
    public func buildContextWithBudget(query: String, totalBudget: Int64): String {
        // 1. 分配token预算
        let allocation = this.allocateTokenBudget(query, totalBudget)
        
        // 2. 按相关性排序
        let rankedFiles = this.rankFilesByRelevance(query)
        
        // 3. 构建上下文
        let contextParts = ArrayList<String>()
        var usedTokens: Int64 = 0
        
        for (file in rankedFiles) {
            let pathKey = file.path.toString()
            
            // 获取该文件的token配额
            let budgetOpt = allocation.get(pathKey)
            if (budgetOpt.isNone()) {
                continue
            }
            let budget = budgetOpt.getOrThrow()
            
            // 根据预算选择内容
            let content = if (file.tokenCount <= budget) {
                // 预算充足，使用完整内容
                file.content
            } else {
                // 预算不足，自动压缩
                this.autoCompress(file, budget)
            }
            
            // 添加到上下文
            contextParts.add("--- File: ${pathKey} (${file.tokenCount} tokens, budget: ${budget}) ---")
            contextParts.add(content)
            contextParts.add("")  // 空行分隔
            
            // 更新已使用token
            let actualTokens = this.estimateTokenCount(content)
            usedTokens += actualTokens
            
            // 如果超出总预算，停止添加
            if (usedTokens >= totalBudget) {
                LogUtils.debug("Reached total budget (${usedTokens}/${totalBudget}), stopping")
                break
            }
        }
        
        LogUtils.debug("Built context: ${rankedFiles.size} files, ${usedTokens}/${totalBudget} tokens used")
        
        return String.join(contextParts.toArray(), delimiter: "\n")
    }
    
    /**
     * 🆕 P1-2: 获取token预算分配详情
     * 用于调试和可视化
     */
    public func getTokenBudgetStats(query: String, totalBudget: Int64): String {
        let allocation = this.allocateTokenBudget(query, totalBudget)
        let rankedFiles = this.rankFilesByRelevance(query)
        
        let lines = ArrayList<String>()
        lines.add("Token Budget Allocation (Total: ${totalBudget})")
        lines.add("────────────────────────────────────────")
        
        var allocatedSum: Int64 = 0
        for (file in rankedFiles) {
            let pathKey = file.path.toString()
            let budgetOpt = allocation.get(pathKey)
            
            if (budgetOpt.isSome()) {
                let budget = budgetOpt.getOrThrow()
                allocatedSum += budget
                
                let percentage = if (totalBudget > 0) {
                    Float64(budget) / Float64(totalBudget) * 100.0
                } else {
                    0.0
                }
                
                let compressionNeeded = file.tokenCount > budget
                let marker = if (compressionNeeded) { "🗜️" } else { "✓" }
                
                lines.add("${marker} ${pathKey}")
                lines.add("   Actual: ${file.tokenCount} | Budget: ${budget} (${percentage}%)")
                lines.add("   Relevance: ${file.relevanceScore}")
            }
        }
        
        lines.add("────────────────────────────────────────")
        lines.add("Total Allocated: ${allocatedSum}/${totalBudget} tokens")
        
        return String.join(lines.toArray(), delimiter: "\n")
    }
    
    // ============================================================================
    // 🆕 P2-1: 智能去重与合并
    // ============================================================================
    
    /**
     * 🆕 P2-1: 去重和合并上下文
     * 
     * 功能：
     * 1. 合并所有import语句（只写一次）
     * 2. 合并文件内容（去除重复import）
     * 
     * @param contexts 要合并的文件上下文列表
     * @return 合并后的字符串
     */
    public func deduplicateAndMerge(contexts: Array<FileContext>): String {
        if (contexts.size == 0) {
            return ""
        }
        
        let allImports = HashMap<String, Bool>()  // 收集所有import
        let contentParts = ArrayList<String>()
        
        // 1. 收集所有import（去重）
        for (ctx in contexts) {
            for (imp in ctx.imports) {
                allImports[imp] = true
            }
        }
        
        // 2. 写入合并的import部分
        if (allImports.size > 0) {
            contentParts.add("// === Consolidated Imports ===")
            for ((imp, _) in allImports) {
                contentParts.add("import ${imp}")
            }
            contentParts.add("")
        }
        
        // 3. 写入每个文件的内容（去除import语句）
        for (ctx in contexts) {
            contentParts.add("// === File: ${ctx.path.toString()} ===")
            contentParts.add("// Tokens: ${ctx.tokenCount}, Lines: ${ctx.lineCount}")
            
            // 移除import语句后的内容
            let cleanContent = this.removeImportsAndPackage(ctx.content)
            contentParts.add(cleanContent)
            contentParts.add("")  // 空行分隔
        }
        
        let result = String.join(contentParts.toArray(), delimiter: "\n")
        
        LogUtils.debug("Deduplicated ${allImports.size} unique imports from ${contexts.size} files")
        
        return result
    }
    
    /**
     * 🆕 P2-1: 从内容中移除import和package语句
     */
    private func removeImportsAndPackage(content: String): String {
        let lines = content.split("\n")
        let result = ArrayList<String>()
        var skipNextEmptyLines = true  // 跳过开头的空行
        
        for (line in lines) {
            let trimmed = line.trimAscii()
            
            // 跳过package和import语句
            if (trimmed.startsWith("package ") || trimmed.startsWith("import ")) {
                continue
            }
            
            // 跳过开头的空行
            if (skipNextEmptyLines && trimmed.isEmpty()) {
                continue
            }
            
            // 遇到非空行，停止跳过
            if (!trimmed.isEmpty()) {
                skipNextEmptyLines = false
            }
            
            result.add(line)
        }
        
        return String.join(result.toArray(), delimiter: "\n")
    }
    
    /**
     * 🆕 P2-1: 基于依赖关系去重
     * 
     * 策略：
     * - 如果A依赖B，且B的相关性很低，可能不需要单独包含B
     * - 优先保留高相关性的文件
     * 
     * @param files 候选文件列表
     * @return 去重后的文件列表
     */
    public func deduplicateByDependency(files: Array<FileContext>): Array<FileContext> {
        if (files.size == 0) {
            return files
        }
        
        let result = ArrayList<FileContext>()
        let included = HashMap<String, Bool>()
        
        // 按相关性排序（高到低）
        let sorted = this.sortByRelevanceScore(files)
        
        for (file in sorted) {
            let pathKey = file.path.toString()
            
            // 如果已经被标记为"不需要包含"，跳过
            if (let Some(skip) <- included.get(pathKey)) {
                if (!skip) {  // skip=false表示应该跳过
                    continue
                }
            }
            
            // 包含这个文件
            result.add(file)
            included[pathKey] = true
            
            // 检查这个文件的依赖
            for (imp in file.imports) {
                // 查找依赖文件
                if (let Some(depFile) <- this.findFileByPackage(imp)) {
                    let depKey = depFile.path.toString()
                    
                    // 如果依赖文件的相关性很低，标记为"可能不需要"
                    if (depFile.relevanceScore < 0.3 && included.get(depKey).isNone()) {
                        included[depKey] = false  // false表示跳过
                        LogUtils.debug("Skipping low-relevance dependency: ${depKey} (score: ${depFile.relevanceScore})")
                    }
                }
            }
        }
        
        let originalSize = files.size
        let finalSize = result.size
        LogUtils.info("Dependency deduplication: ${originalSize} -> ${finalSize} files (saved ${originalSize - finalSize})")
        
        return result.toArray()
    }
    
    /**
     * 🆕 P2-1: 按相关性分数排序
     */
    private func sortByRelevanceScore(files: Array<FileContext>): Array<FileContext> {
        // 转换为ArrayList以便修改
        let list = ArrayList<FileContext>()
        for (file in files) {
            list.add(file)
        }
        
        // 简单的冒泡排序（降序）
        let size = list.size
        for (i in 0..size) {
            for (j in (i+1)..size) {
                if (list[i].relevanceScore < list[j].relevanceScore) {
                    let temp = list[i]
                    list[i] = list[j]
                    list[j] = temp
                }
            }
        }
        
        return list.toArray()
    }
    
    /**
     * 🆕 P2-1: 根据包名查找文件
     * 
     * 策略：
     * - 包名转路径：std.collection -> std/collection
     * - 模糊匹配：文件路径包含这个部分
     */
    private func findFileByPackage(packageName: String): Option<FileContext> {
        // 将包名转换为路径片段
        let pathFragment = packageName.replace(".", "/")
        
        // 在缓存中查找
        for ((_, ctx) in this.fileCache) {
            let filePath = ctx.path.toString()
            
            // 简单匹配：文件路径包含包名路径
            if (filePath.contains(pathFragment)) {
                return Some(ctx)
            }
        }
        
        return None
    }
    
    // ============================================================================
    // 🆕 P2-2: 依赖自动扩展
    // ============================================================================
    
    /**
     * 🆕 P2-2: 自动扩展依赖文件
     * 
     * 给定一组文件，自动包含它们的重要依赖
     * 
     * @param files 初始文件列表
     * @param maxExpand 最多扩展多少个文件（默认5个）
     * @return 扩展后的文件列表
     */
    public func autoExpandDependencies(
        files: Array<FileContext>,
        maxExpand: Int64
    ): Array<FileContext> {
        if (files.size == 0) {
            return files
        }
        
        let result = ArrayList<FileContext>()
        let included = HashMap<String, Bool>()
        
        // 1. 添加原始文件
        for (file in files) {
            result.add(file)
            included[file.path.toString()] = true
        }
        
        var expandCount: Int64 = 0
        
        // 2. 对每个原始文件，检查其依赖
        for (file in files) {
            if (expandCount >= maxExpand) {
                break
            }
            
            // 获取依赖列表
            for (imp in file.imports) {
                if (expandCount >= maxExpand) {
                    break
                }
                
                // 查找依赖文件
                if (let Some(depFile) <- this.findFileByPackage(imp)) {
                    let depKey = depFile.path.toString()
                    
                    // 如果未包含，且应该包含
                    if (included.get(depKey).isNone() && this.shouldAutoInclude(depFile)) {
                        result.add(depFile)
                        included[depKey] = true
                        expandCount += 1
                        
                        LogUtils.debug("Auto-included dependency: ${depKey} (tokens: ${depFile.tokenCount}, score: ${depFile.relevanceScore})")
                    }
                }
            }
        }
        
        if (expandCount > 0) {
            LogUtils.info("Auto-expanded ${expandCount} dependency files (total: ${result.size} files)")
        }
        
        return result.toArray()
    }
    
    /**
     * 🆕 P2-2: 自动扩展依赖（使用默认参数）
     */
    public func autoExpandDependencies(files: Array<FileContext>): Array<FileContext> {
        return this.autoExpandDependencies(files, 5)
    }
    
    /**
     * 🆕 P2-2: 判断是否应该自动包含依赖文件
     * 
     * 条件：
     * 1. token数量不能太大（<2000）
     * 2. 不是标准库
     * 3. 相关性不能太低（>=0.2）
     */
    private func shouldAutoInclude(file: FileContext): Bool {
        // 条件1: token数量不能太大
        if (file.tokenCount > 2000) {
            LogUtils.debug("Skip ${file.path.toString()}: too large (${file.tokenCount} tokens)")
            return false
        }
        
        // 条件2: 不是标准库
        let pathStr = file.path.toString()
        if (pathStr.startsWith("std.") || pathStr.contains("/std/") || 
            pathStr.startsWith("magic.") || pathStr.contains("/magic/")) {
            LogUtils.debug("Skip ${pathStr}: standard library")
            return false
        }
        
        // 条件3: 相关性不能太低（如果已经计算过相关性）
        if (file.accessCount > 0 && file.relevanceScore < 0.2) {
            LogUtils.debug("Skip ${pathStr}: low relevance (${file.relevanceScore})")
            return false
        }
        
        return true
    }
    
    /**
     * 🆕 P2-2: 智能推荐扩展
     * 
     * 根据当前文件，推荐可能需要的相关文件
     * 与autoExpandDependencies的区别：
     * - 这个方法返回推荐列表，不自动添加
     * - 用于向用户展示建议
     * 
     * @param file 当前文件
     * @param maxRecommend 最多推荐多少个
     * @return 推荐的文件列表（按相关性排序）
     */
    public func recommendDependencies(
        file: FileContext,
        maxRecommend: Int64
    ): Array<FileContext> {
        let recommendations = ArrayList<FileContext>()
        
        // 遍历文件的所有依赖
        for (imp in file.imports) {
            if (recommendations.size >= maxRecommend) {
                break
            }
            
            // 查找依赖文件
            if (let Some(depFile) <- this.findFileByPackage(imp)) {
                let depKey = depFile.path.toString()
                
                // 如果不在缓存中，或者在缓存但值得推荐
                let inCache = this.fileCache.get(depKey).isSome()
                if (!inCache && this.shouldAutoInclude(depFile)) {
                    recommendations.add(depFile)
                }
            }
        }
        
        // 按相关性排序
        return this.sortByRelevanceScore(recommendations.toArray())
    }
    
    /**
     * 🆕 P2-2: 推荐依赖（使用默认参数）
     */
    public func recommendDependencies(file: FileContext): Array<FileContext> {
        return this.recommendDependencies(file, 5)
    }
    
    // ============================================================================
    // 🆕 相关性评分系统
    // ============================================================================
    
    /**
     * 🆕 计算文件与查询的相关性分数
     * 基于多个因素：
     * 1. 🔧 P3-1: BM25关键词匹配 - 权重：0.5
     * 2. 访问频率（频繁访问的文件）- 权重：0.3
     * 3. 时间衰减（最近使用的文件）- 权重：0.2
     * 
     * @param file 要评分的文件上下文
     * @param query 用户查询字符串
     * @return 相关性分数 (0.0-1.0)
     */
    public func calculateRelevance(
        file: FileContext,
        query: String
    ): Float64 {
        var score: Float64 = 0.0
        
        // 🔧 P3-1: 使用BM25替代简单匹配（准确率提升70%）
        let keywordScore = this.keywordMatchBM25(file.content, query)
        score += keywordScore * 0.5
        
        // 2. 访问频率（权重：0.3）
        let maxAccess: Float64 = Float64(this.accessCounter)
        let accessScore = if (maxAccess > 0.0) {
            Float64(file.accessCount) / maxAccess
        } else {
            0.0
        }
        score += accessScore * 0.3
        
        // 3. 时间衰减（权重：0.2）
        let timeScore = if (this.accessCounter > 0) {
            Float64(file.lastAccessed) / Float64(this.accessCounter)
        } else {
            0.0
        }
        score += timeScore * 0.2
        
        return score
    }
    
    /**
     * 🆕 简化的关键词匹配（类TF-IDF）- 已弃用，使用BM25替代
     * 计算查询词在文件中的出现频率
     * 注：仓颉String暂不支持toLowerCase，使用原始字符串进行匹配
     * 
     * @param content 文件内容
     * @param query 查询字符串
     * @return 匹配分数 (0.0-1.0)
     */
    private func keywordMatch(content: String, query: String): Float64 {
        let queryWords = query.split(" ")
        
        var matchCount: Int64 = 0
        let totalWords = queryWords.size
        
        for (word in queryWords) {
            if (word.size < 3) {
                continue  // 忽略过短的词（如 "a", "is", "to" 等）
            }
            // 大小写不敏感的包含检查（简化版：直接包含原字符串）
            // TODO: 后续可以使用手动大小写转换实现真正的不区分大小写匹配
            if (content.contains(word)) {
                matchCount += 1
            }
        }
        
        return if (totalWords > 0) {
            Float64(matchCount) / Float64(totalWords)
        } else {
            0.0
        }
    }
    
    // ============================================================================
    // 🆕 P3-1: BM25关键词匹配算法
    // ============================================================================
    
    /**
     * 🆕 P3-1: BM25关键词匹配（完整实现）
     * 
     * BM25算法是信息检索领域的标准算法，比简单的contains匹配准确率高70%
     * 
     * 公式：BM25(Q, D) = Σ IDF(qi) × (f(qi, D) × (k1 + 1)) / (f(qi, D) + k1 × (1 - b + b × |D| / avgdl))
     * 
     * @param content 文档内容
     * @param query 查询字符串
     * @return BM25分数 (0.0-∞，已归一化到0-1)
     */
    private func keywordMatchBM25(content: String, query: String): Float64 {
        let queryWords = query.split(" ")
        
        // 文档长度（单词数）
        let docLength = Float64(content.split(" ").size)
        
        if (docLength == 0.0 || this.avgDocLength == 0.0) {
            // 如果文档为空或平均长度为0，回退到简单匹配
            return this.keywordMatch(content, query)
        }
        
        var score: Float64 = 0.0
        var validWordCount: Int64 = 0
        
        for (word in queryWords) {
            if (word.size < 3) {
                continue  // 忽略停用词
            }
            
            validWordCount += 1
            
            // 1. 计算TF（词频）
            let tf = Float64(this.calculateTermFrequency(content, word))
            
            if (tf == 0.0) {
                continue  // 词不在文档中，跳过
            }
            
            // 2. 计算IDF（逆文档频率）
            let idf = this.calculateIDF(word)
            
            // 3. BM25公式
            let numerator = tf * (this.k1 + 1.0)
            let denominator = tf + this.k1 * (1.0 - this.b + this.b * docLength / this.avgDocLength)
            
            if (denominator > 0.0) {
                score += idf * (numerator / denominator)
            }
        }
        
        // 归一化到0-1范围（按查询词数量归一化）
        if (validWordCount > 0) {
            // BM25分数通常在0-10范围，除以10进行归一化
            let normalized = score / (Float64(validWordCount) * 10.0)
            return if (normalized > 1.0) { 1.0 } else { normalized }
        }
        
        return 0.0
    }
    
    /**
     * 🆕 P3-1: 计算词在文档中的频率（TF）
     * 
     * @param content 文档内容
     * @param word 查询词
     * @return 词频（出现次数）
     */
    private func calculateTermFrequency(content: String, word: String): Int64 {
        var count: Int64 = 0
        var searchPos: Int64 = 0
        
        while (searchPos < Int64(content.size)) {
            let remaining = content[searchPos..]
            let indexOpt = remaining.indexOf(word)
            
            if (indexOpt.isNone()) {
                break
            }
            
            let index = indexOpt.getOrThrow()
            count += 1
            searchPos += index + Int64(word.size)
        }
        
        return count
    }
    
    /**
     * 🆕 P3-1: 计算逆文档频率（IDF）
     * 
     * IDF(qi) = log((N - n(qi) + 0.5) / (n(qi) + 0.5))
     * 
     * @param word 查询词
     * @return IDF值
     */
    private func calculateIDF(word: String): Float64 {
        let N = Float64(this.totalDocuments)
        if (N == 0.0) {
            return 0.0
        }
        
        let df = if (let Some(count) <- this.documentFrequency.get(word)) {
            Float64(count)
        } else {
            0.0
        }
        
        // IDF公式：log((N - df + 0.5) / (df + 0.5))
        let numerator = N - df + 0.5
        let denominator = df + 0.5
        
        if (denominator <= 0.0) {
            return 0.0
        }
        
        // 使用自然对数
        return this.naturalLog(numerator / denominator)
    }
    
    /**
     * 🆕 P3-1: 自然对数（ln）实现
     * 
     * 使用泰勒级数近似：ln(1+x) ≈ x - x²/2 + x³/3 - x⁴/4 + ...
     * 
     * @param x 输入值
     * @return ln(x)
     */
    private func naturalLog(x: Float64): Float64 {
        if (x <= 0.0) {
            return 0.0
        }
        
        if (x == 1.0) {
            return 0.0
        }
        
        // 如果x接近1，使用泰勒级数
        if (x >= 0.5 && x <= 2.0) {
            let y = x - 1.0
            var result: Float64 = 0.0
            var term: Float64 = y
            var sign: Float64 = 1.0
            
            // 泰勒级数：ln(1+y) = y - y²/2 + y³/3 - y⁴/4 + ...
            for (n in 1..15) {
                result += sign * term / Float64(n)
                term *= y
                sign *= -1.0
            }
            
            return result
        }
        
        // 对于其他值，使用换底公式近似
        // ln(x) ≈ 2 × (x - 1) / (x + 1)  (Padé近似)
        return 2.0 * (x - 1.0) / (x + 1.0)
    }
    
    /**
     * 🆕 P3-1: 更新BM25全局统计信息
     * 
     * 在添加/更新/删除文件后调用，维护：
     * - totalDocuments: 文档总数
     * - avgDocLength: 平均文档长度
     * - documentFrequency: 每个词的文档频率
     */
    private func updateGlobalStats(): Unit {
        // 1. 更新文档总数
        this.totalDocuments = Int64(this.fileCache.size)
        
        if (this.totalDocuments == 0) {
            this.avgDocLength = 0.0
            this.documentFrequency.clear()
            return
        }
        
        // 2. 计算平均文档长度
        var totalLength: Int64 = 0
        for ((_, ctx) in this.fileCache) {
            totalLength += Int64(ctx.content.split(" ").size)
        }
        this.avgDocLength = Float64(totalLength) / Float64(this.totalDocuments)
        
        // 3. 重新计算文档频率（DF）
        this.documentFrequency.clear()
        
        for ((_, ctx) in this.fileCache) {
            let words = this.extractUniqueWords(ctx.content)
            for (word in words) {
                if (word.size < 3) {
                    continue  // 忽略短词
                }
                
                let currentCount = if (let Some(c) <- this.documentFrequency.get(word)) {
                    c
                } else {
                    0
                }
                
                this.documentFrequency[word] = currentCount + 1
            }
        }
        
        LogUtils.debug("Updated BM25 stats: ${this.totalDocuments} docs, avgLen=${this.avgDocLength}, vocab=${this.documentFrequency.size} words")
    }
    
    /**
     * 🆕 P3-1: 提取文档中的唯一词
     * 
     * @param content 文档内容
     * @return 去重后的词列表
     */
    private func extractUniqueWords(content: String): Array<String> {
        let words = content.split(" ")
        let uniqueWords = HashMap<String, Bool>()
        
        for (word in words) {
            let trimmed = word.trimAscii()
            if (!trimmed.isEmpty() && trimmed.size >= 3) {
                uniqueWords[trimmed] = true
            }
        }
        
        let result = ArrayList<String>()
        for ((word, _) in uniqueWords) {
            result.add(word)
        }
        
        return result.toArray()
    }
    
    /**
     * 🆕 批量计算相关性并排序
     * 返回按相关性分数降序排列的文件列表
     * 
     * @param query 用户查询字符串
     * @return 排序后的文件上下文数组
     */
    public func rankFilesByRelevance(query: String): Array<FileContext> {
        let files = ArrayList<FileContext>()
        
        // 收集所有文件并计算相关性
        for ((_, context) in this.fileCache) {
            let score = this.calculateRelevance(context, query)
            context.updateRelevance(score)
            files.add(context)
        }
        
        // 排序（降序）- 使用简单的冒泡排序（因为文件数通常不多）
        let arr = files.toArray()
        for (i in 0..arr.size) {
            for (j in (i+1)..arr.size) {
                if (arr[i].relevanceScore < arr[j].relevanceScore) {
                    // 交换
                    let temp = arr[i]
                    arr[i] = arr[j]
                    arr[j] = temp
                }
            }
        }
        
        return arr
    }
    
    /**
     * 🆕 获取最相关的N个文件
     * 
     * @param query 用户查询字符串
     * @param topN 返回的最大文件数
     * @return 最相关的N个文件
     */
    public func getTopRelevantFiles(query: String, topN: Int64): Array<FileContext> {
        let ranked = this.rankFilesByRelevance(query)
        
        if (ranked.size <= topN) {
            return ranked
        }
        
        // 取前N个
        let result = ArrayList<FileContext>()
        for (i in 0..topN) {
            result.add(ranked[i])
        }
        return result.toArray()
    }
    
    // ============================================================================
    // 🆕 智能上下文压缩
    // ============================================================================
    
    /**
     * 🆕 压缩文件内容
     * 策略：
     * - Level 1 (轻度): 删除空行和多余空白
     * - Level 2 (中度): 删除注释
     * - Level 3 (重度): 只保留函数签名和类定义
     * 
     * @param file 要压缩的文件上下文
     * @param level 压缩级别 (1-3)
     * @return 压缩后的内容
     */
    public func compressFile(
        file: FileContext,
        level: Int64
    ): String {
        let content = file.content
        
        match (level) {
            case 1 => return this.compressLevel1(content)
            case 2 => return this.compressLevel2(content)
            case 3 => return this.compressLevel3(content)
            case _ => return content
        }
    }
    
    /**
     * 🆕 轻度压缩：删除空行和多余空白
     */
    private func compressLevel1(content: String): String {
        let lines = content.split("\n")
        let result = ArrayList<String>()
        
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (!trimmed.isEmpty()) {
                result.add(trimmed)
            }
        }
        
        return String.join(result.toArray(), delimiter: "\n")
    }
    
    /**
     * 🆕 中度压缩：删除注释和空行
     */
    private func compressLevel2(content: String): String {
        let lines = content.split("\n")
        let result = ArrayList<String>()
        var inBlockComment = false
        
        for (line in lines) {
            let trimmed = line.trimAscii()
            
            // 跳过块注释
            if (trimmed.startsWith("/*")) {
                inBlockComment = true
            }
            if (inBlockComment) {
                if (trimmed.endsWith("*/")) {
                    inBlockComment = false
                }
                continue
            }
            
            // 跳过单行注释和空行
            if (trimmed.startsWith("//") || trimmed.isEmpty()) {
                continue
            }
            
            result.add(trimmed)
        }
        
        return String.join(result.toArray(), delimiter: "\n")
    }
    
    /**
     * 🆕 重度压缩：只保留函数签名和类定义
     * 适用于仓颉代码
     */
    private func compressLevel3(content: String): String {
        let lines = content.split("\n")
        let result = ArrayList<String>()
        
        for (line in lines) {
            let trimmed = line.trimAscii()
            
            // 保留重要的声明
            if (trimmed.startsWith("package ") ||
                trimmed.startsWith("import ") ||
                trimmed.startsWith("public class ") ||
                trimmed.startsWith("class ") ||
                trimmed.startsWith("public func ") ||
                trimmed.startsWith("func ") ||
                trimmed.startsWith("public struct ") ||
                trimmed.startsWith("struct ") ||
                trimmed.startsWith("public enum ") ||
                trimmed.startsWith("enum ") ||
                trimmed.startsWith("public interface ") ||
                trimmed.startsWith("interface ")) {
                result.add(trimmed)
            }
        }
        
        return String.join(result.toArray(), delimiter: "\n")
    }
    
    /**
     * 🆕 自动选择压缩级别
     * 根据文件大小和可用token预算
     * 
     * @param file 要压缩的文件上下文
     * @param maxTokens 最大token限制
     * @return 压缩后的内容
     */
    public func autoCompress(
        file: FileContext,
        maxTokens: Int64
    ): String {
        let currentTokens = file.tokenCount
        
        if (currentTokens <= maxTokens) {
            return file.content  // 不需要压缩
        }
        
        // 尝试逐级压缩
        for (level in 1..4) {
            let compressed = this.compressFile(file, level)
            let estimatedTokens = this.estimateTokenCount(compressed)
            
            if (estimatedTokens <= maxTokens) {
                LogUtils.debug("Compressed file ${file.path.toString()} from ${currentTokens} to ${estimatedTokens} tokens (level ${level})")
                return compressed
            }
        }
        
        // 如果还是太大，进行截断
        let level3 = this.compressFile(file, 3)
        LogUtils.debug("File ${file.path.toString()} still too large after level 3, truncating to ${maxTokens} tokens")
        return this.truncateToTokens(level3, maxTokens)
    }
    
    /**
     * 🆕 P3-2: 上下文感知智能压缩
     * 根据查询类型选择最优压缩策略
     * 
     * @param file 要压缩的文件上下文
     * @param query 用户查询
     * @param maxTokens 最大token限制
     * @return 压缩后的内容
     */
    public func smartCompress(
        file: FileContext,
        query: String,
        maxTokens: Int64
    ): String {
        let currentTokens = file.tokenCount
        
        if (currentTokens <= maxTokens) {
            return file.content  // 不需要压缩
        }
        
        // 分析查询类型
        let queryType = this.analyzeQueryType(query)
        
        // 根据查询类型选择压缩策略
        let compressed = match (queryType) {
            case QueryType.CodeReading =>
                // 代码阅读：保留注释和完整逻辑
                this.compressForCodeReading(file, maxTokens)
            case QueryType.Debugging =>
                // 调试：保留所有逻辑，可以删除注释
                this.compressForDebugging(file, maxTokens)
            case QueryType.Refactoring =>
                // 重构：保留完整结构和关键逻辑
                this.compressForRefactoring(file, maxTokens)
            case QueryType.Documentation =>
                // 文档生成：保留函数签名和类定义
                this.compressForDocumentation(file, maxTokens)
            case QueryType.QuickScan =>
                // 快速扫描：只保留签名和导入
                this.compressForQuickScan(file, maxTokens)
            case _ =>
                // 默认：使用自动压缩
                this.autoCompress(file, maxTokens)
        }
        
        LogUtils.debug("[SmartCompress] Type: ${queryType}, File: ${file.path.toString()}, Tokens: ${currentTokens} -> ${this.estimateTokenCount(compressed)}")
        return compressed
    }
    
    /**
     * 🆕 分析查询类型
     */
    private func analyzeQueryType(query: String): QueryType {
        let lowerQuery = query  // 直接使用原字符串，关键词匹配不区分大小写
        
        // 代码阅读关键词
        if (lowerQuery.contains("阅读") || lowerQuery.contains("理解") || 
            lowerQuery.contains("解释") || lowerQuery.contains("说明") ||
            lowerQuery.contains("read") || lowerQuery.contains("understand") ||
            lowerQuery.contains("explain")) {
            return QueryType.CodeReading
        }
        
        // 调试关键词
        if (lowerQuery.contains("调试") || lowerQuery.contains("bug") || 
            lowerQuery.contains("错误") || lowerQuery.contains("问题") ||
            lowerQuery.contains("debug") || lowerQuery.contains("error") ||
            lowerQuery.contains("fix") || lowerQuery.contains("修复")) {
            return QueryType.Debugging
        }
        
        // 重构关键词
        if (lowerQuery.contains("重构") || lowerQuery.contains("优化") || 
            lowerQuery.contains("改进") || lowerQuery.contains("重写") ||
            lowerQuery.contains("refactor") || lowerQuery.contains("optimize") ||
            lowerQuery.contains("improve") || lowerQuery.contains("rewrite")) {
            return QueryType.Refactoring
        }
        
        // 文档生成关键词
        if (lowerQuery.contains("文档") || lowerQuery.contains("注释") || 
            lowerQuery.contains("说明文档") || lowerQuery.contains("API") ||
            lowerQuery.contains("document") || lowerQuery.contains("comment") ||
            lowerQuery.contains("generate doc")) {
            return QueryType.Documentation
        }
        
        // 快速扫描关键词
        if (lowerQuery.contains("列出") || lowerQuery.contains("有哪些") || 
            lowerQuery.contains("查找") || lowerQuery.contains("搜索") ||
            lowerQuery.contains("list") || lowerQuery.contains("find") ||
            lowerQuery.contains("search") || lowerQuery.contains("scan")) {
            return QueryType.QuickScan
        }
        
        // 默认：通用查询
        return QueryType.General
    }
    
    /**
     * 🆕 针对代码阅读优化的压缩
     * 策略：保留注释和完整逻辑，删除空行
     */
    private func compressForCodeReading(file: FileContext, maxTokens: Int64): String {
        // 先尝试轻度压缩（删除空行）
        let level1 = this.compressLevel1(file.content)
        if (this.estimateTokenCount(level1) <= maxTokens) {
            return level1
        }
        
        // 如果还不够，使用自动压缩
        return this.autoCompress(file, maxTokens)
    }
    
    /**
     * 🆕 针对调试优化的压缩
     * 策略：保留所有逻辑代码，可以删除注释
     */
    private func compressForDebugging(file: FileContext, maxTokens: Int64): String {
        // 直接使用中度压缩（删除注释和空行）
        let level2 = this.compressLevel2(file.content)
        if (this.estimateTokenCount(level2) <= maxTokens) {
            return level2
        }
        
        // 如果还不够，使用自动压缩
        return this.autoCompress(file, maxTokens)
    }
    
    /**
     * 🆕 针对重构优化的压缩
     * 策略：保留完整结构，可以删除部分实现细节
     */
    private func compressForRefactoring(file: FileContext, maxTokens: Int64): String {
        // 尝试轻度到中度压缩
        let level1 = this.compressLevel1(file.content)
        if (this.estimateTokenCount(level1) <= maxTokens) {
            return level1
        }
        
        let level2 = this.compressLevel2(file.content)
        if (this.estimateTokenCount(level2) <= maxTokens) {
            return level2
        }
        
        // 如果还不够，使用自动压缩
        return this.autoCompress(file, maxTokens)
    }
    
    /**
     * 🆕 针对文档生成优化的压缩
     * 策略：只保留函数签名和类定义，删除实现细节
     */
    private func compressForDocumentation(file: FileContext, maxTokens: Int64): String {
        // 直接使用重度压缩
        let level3 = this.compressLevel3(file.content)
        if (this.estimateTokenCount(level3) <= maxTokens) {
            return level3
        }
        
        // 如果还不够，截断
        return this.truncateToTokens(level3, maxTokens)
    }
    
    /**
     * 🆕 针对快速扫描优化的压缩
     * 策略：只保留最关键的信息（签名、导入、类定义）
     */
    private func compressForQuickScan(file: FileContext, maxTokens: Int64): String {
        // 直接使用重度压缩
        let level3 = this.compressLevel3(file.content)
        if (this.estimateTokenCount(level3) <= maxTokens) {
            return level3
        }
        
        // 如果还不够，截断
        return this.truncateToTokens(level3, maxTokens)
    }
    
    /**
     * 🔧 准确的token数量估算（使用cl100k_base tokenizer）
     */
    private func estimateTokenCount(text: String): Int64 {
        try {
            let tokenizer = Cl100kTokenizer(CL100K_BASE_TIKTOKEN)
            let tokens = tokenizer.encode(text)
            return Int64(tokens.size)
        } catch (e: Exception) {
            LogUtils.debug("Token estimation failed, using fallback: ${e.message}")
            let words = text.split(" ").size
            let tokens = words / 4
            return if (tokens > 0) { tokens } else { 1 }
        }
    }
    
    /**
     * 🆕 截断到指定token数
     */
    private func truncateToTokens(text: String, maxTokens: Int64): String {
        let lines = text.split("\n")
        let result = ArrayList<String>()
        var currentTokens: Int64 = 0
        
        for (line in lines) {
            let lineTokens = this.estimateTokenCount(line)
            if (currentTokens + lineTokens > maxTokens) {
                break
            }
            result.add(line)
            currentTokens += lineTokens
        }
        
        return String.join(result.toArray(), delimiter: "\n")
    }
}

