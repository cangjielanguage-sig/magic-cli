package cli.core.context

import std.fs.{Path, exists, File, canonicalize}
import std.collection.ArrayList
import magic.log.LogUtils
import cli.core.config.CliConfig

/**
 * 文件引用信息（增强版 v2.0）
 * 支持：
 * - 整个文件引用：@filename
 * - 行范围引用：@filename:10-20
 * - 单行引用：@filename:42
 * - 符号引用：@filename:MyClass
 */
public class FileMention {
    public let path: Path
    public let originalText: String
    
    // 🆕 新增：行范围信息
    public let startLine: Option<Int64>
    public let endLine: Option<Int64>
    public let symbolName: Option<String>  // 🆕 符号名称
    
    // 完整构造函数
    public init(
        path: Path,
        originalText: String,
        startLine: Option<Int64>,
        endLine: Option<Int64>,
        symbolName: Option<String>
    ) {
        this.path = path
        this.originalText = originalText
        this.startLine = startLine
        this.endLine = endLine
        this.symbolName = symbolName
    }
    
    // 简化构造函数（只有路径和原始文本）
    public init(path: Path, originalText: String) {
        this.path = path
        this.originalText = originalText
        this.startLine = None
        this.endLine = None
        this.symbolName = None
    }
    
    /**
     * 🆕 是否有行范围限制
     */
    public func hasLineRange(): Bool {
        return this.startLine.isSome() || this.endLine.isSome()
    }
    
    /**
     * 🆕 是否是符号引用
     */
    public func isSymbolReference(): Bool {
        return this.symbolName.isSome()
    }
}

/**
 * 解析结果
 */
public class ParseResult {
    public let cleanedInput: String
    public let mentions: Array<FileMention>
    
    public init(cleanedInput: String, mentions: Array<FileMention>) {
        this.cleanedInput = cleanedInput
        this.mentions = mentions
    }
}

/**
 * @mention 解析器 - 增强版 v2.0
 * 支持格式:
 * - @filename           整个文件
 * - @filename:10-20     行范围
 * - @filename:42        单行
 * - @filename:MyClass   符号引用
 */
public class MentionParser {
    
    /**
     * 🔧 改进的解析方法
     * 解析输入中的 @mention 引用，支持多种格式
     */
    public static func parse(input: String): ParseResult {
        let mentions = ArrayList<FileMention>()
        var cleanedInput = input
        
        // 遍历查找所有 @word 模式
        let words = input.split(" ")
        for (word in words) {
            if (!word.startsWith("@") || word.size <= 1) {
                continue
            }
            
            // 解析 @mention（可能包含 :行号 或 :符号）
            let parsedMention = MentionParser.parseSingleMention(word)
            if (parsedMention.isSome()) {
                let mention = parsedMention.getOrThrow()
                mentions.add(mention)
                
                // 替换为友好显示
                let displayText = MentionParser.formatMentionDisplay(mention)
                cleanedInput = cleanedInput.replace(word, displayText)
            }
        }
        
        return ParseResult(cleanedInput, mentions.toArray())
    }
    
    /**
     * 🆕 解析单个mention
     * 格式：@filename 或 @filename:suffix
     * suffix可以是：10-20（行范围）、42（单行）、MyClass（符号）
     */
    private static func parseSingleMention(word: String): Option<FileMention> {
        // 去掉 @ 符号
        let mentionText = word[1..]
        
        // 查找 : 分隔符
        let colonIndexOpt = mentionText.indexOf(":")
        
        if (colonIndexOpt.isNone()) {
            // 简单格式：@filename
            let resolvedPath = resolveFile(mentionText)
            if (resolvedPath.isSome()) {
                return Some(FileMention(resolvedPath.getOrThrow(), word))
            }
            return None
        }
        
        // 复杂格式：@filename:suffix
        let colonIndex = colonIndexOpt.getOrThrow()
        let filename = mentionText[0..colonIndex]
        let suffix = mentionText[(colonIndex + 1)..]
        
        // 解析 suffix
        let resolvedPath = resolveFile(filename)
        if (resolvedPath.isSome()) {
            let path = resolvedPath.getOrThrow()
            
            // 尝试解析行范围或符号
            let lineRange = MentionParser.parseLineRange(suffix)
            if (lineRange.isSome()) {
                let (start, end) = lineRange.getOrThrow()
                // 是行范围
                return Some(FileMention(
                    path, 
                    word,
                    Some(start),
                    Some(end),
                    None
                ))
            }
            
            // 检查是否是单个数字（单行）
            let singleLine = MentionParser.parseNumber(suffix)
            if (singleLine.isSome()) {
                let lineNum = singleLine.getOrThrow()
                return Some(FileMention(
                    path,
                    word,
                    Some(lineNum),
                    Some(lineNum),  // 单行：start = end
                    None
                ))
            }
            
            // 不是数字，可能是符号名
            if (suffix.size > 0 && !suffix.contains("-")) {
                return Some(FileMention(
                    path,
                    word,
                    None,
                    None,
                    Some(suffix)
                ))
            }
        }
        
        return None
    }
    
    /**
     * 🆕 解析行范围 "10-20"
     * 返回 (startLine, endLine)
     */
    private static func parseLineRange(text: String): Option<(Int64, Int64)> {
        let dashIndexOpt = text.indexOf("-")
        if (dashIndexOpt.isNone()) {
            return None
        }
        
        let dashIndex = dashIndexOpt.getOrThrow()
        if (dashIndex == 0 || dashIndex == text.size - 1) {
            return None
        }
        
        let startStr = text[0..dashIndex]
        let endStr = text[(dashIndex + 1)..]
        
        let start = MentionParser.parseNumber(startStr)
        let end = MentionParser.parseNumber(endStr)
        
        if (start.isSome() && end.isSome()) {
            return Some((start.getOrThrow(), end.getOrThrow()))
        }
        
        return None
    }
    
    /**
     * 🆕 解析数字
     */
    private static func parseNumber(str: String): Option<Int64> {
        if (str.isEmpty()) {
            return None
        }
        
        try {
            var result: Int64 = 0
            for (ch in str.toRuneArray()) {
                if (ch >= r'0' && ch <= r'9') {
                    result = result * 10 + Int64(UInt32(ch) - UInt32(r'0'))
                } else {
                    return None
                }
            }
            return Some(result)
        } catch (_: Exception) {
            return None
        }
    }
    
    /**
     * 🆕 格式化mention显示
     */
    private static func formatMentionDisplay(mention: FileMention): String {
        let filename = mention.path.toString()
        
        // 符号引用
        if (let Some(symbol) <- mention.symbolName) {
            return "[File: ${filename} -> ${symbol}]"
        }
        
        // 行范围引用
        if (let Some(start) <- mention.startLine) {
            if (let Some(end) <- mention.endLine) {
                if (start == end) {
                    return "[File: ${filename}:${start}]"
                } else {
                    return "[File: ${filename}:${start}-${end}]"
                }
            } else {
                return "[File: ${filename}:${start}]"
            }
        }
        
        // 整个文件
        return "[File: ${filename}]"
    }
    
    /**
     * 解析文件路径
     */
    public static func resolveFile(mention: String): Option<Path> {
        try {
            // 尝试相对路径
            let relativePath = CliConfig.cwd.join(mention)
            if (exists(relativePath)) {
                return Some(canonicalize(relativePath))
            }
            
            // 尝试绝对路径
            let absolutePath = Path(mention)
            if (exists(absolutePath)) {
                return Some(canonicalize(absolutePath))
            }
            
            return None
        } catch (e: Exception) {
            LogUtils.error("Failed to resolve file ${mention}: ${e.message}")
            return None
        }
    }
    
    /**
     * 🔧 改进的读取文件内容（支持行范围和符号引用）
     */
    public static func readFileContent(mention: FileMention): String {
        try {
            let fullContent = String.fromUtf8(File.readFrom(mention.path))
            
            // 如果有行范围限制，只返回指定行
            if (mention.hasLineRange()) {
                return MentionParser.extractLineRange(fullContent, mention)
            }
            
            // 如果是符号引用，尝试提取符号定义
            if (mention.symbolName.isSome()) {
                let symbol = mention.symbolName.getOrThrow()
                return MentionParser.extractSymbol(fullContent, symbol)
            }
            
            return fullContent
        } catch (e: Exception) {
            LogUtils.error("Failed to read file ${mention.path}: ${e.message}")
            return ""
        }
    }
    
    /**
     * 🆕 提取指定行范围
     */
    private static func extractLineRange(
        content: String,
        mention: FileMention
    ): String {
        let lines = content.split("\n")
        
        let start = if (mention.startLine.isSome()) {
            let s = mention.startLine.getOrThrow()
            if (s > 0 && s <= lines.size) { s - 1 } else { 0 }
        } else {
            0
        }
        
        let end = if (mention.endLine.isSome()) {
            let e = mention.endLine.getOrThrow()
            if (e > 0 && e <= lines.size) { e } else { lines.size }
        } else {
            lines.size
        }
        
        // 提取范围内的行
        let result = ArrayList<String>()
        for (i in start..end) {
            result.add(lines[i])
        }
        
        return String.join(result.toArray(), delimiter: "\n")
    }
    
    /**
     * 🆕 提取符号定义（简化版）
     * 查找包含符号名称的类、函数、结构体定义
     */
    private static func extractSymbol(
        content: String,
        symbolName: String
    ): String {
        let lines = content.split("\n")
        let result = ArrayList<String>()
        var inDefinition = false
        var braceCount: Int64 = 0
        
        for (line in lines) {
            let trimmed = line.trimAscii()
            
            // 检查是否是目标符号的定义
            if (!inDefinition) {
                let isTargetSymbol = 
                    trimmed.contains("class ${symbolName}") ||
                    trimmed.contains("func ${symbolName}") ||
                    trimmed.contains("struct ${symbolName}") ||
                    trimmed.contains("enum ${symbolName}") ||
                    trimmed.contains("interface ${symbolName}")
                
                if (isTargetSymbol) {
                    inDefinition = true
                }
            }
            
            if (inDefinition) {
                result.add(line)
                
                // 统计大括号
                for (ch in line.toRuneArray()) {
                    if (ch == r'{') {
                        braceCount += 1
                    } else if (ch == r'}') {
                        braceCount -= 1
                    }
                }
                
                // 定义结束
                if (braceCount == 0 && result.size > 1) {
                    break
                }
            }
        }
        
        if (result.size == 0) {
            return "// Symbol '${symbolName}' not found"
        }
        
        return String.join(result.toArray(), delimiter: "\n")
    }
    
    /**
     * 格式化文件引用信息用于显示
     */
    public static func formatMentionInfo(mention: FileMention): String {
        try {
            let content = String.fromUtf8(File.readFrom(mention.path))
            let lines = content.split("\n")
            let lineCount = lines.size
            return "${mention.path.toString()} (${lineCount} lines)"
        } catch (_: Exception) {
            return mention.path.toString()
        }
    }
}
