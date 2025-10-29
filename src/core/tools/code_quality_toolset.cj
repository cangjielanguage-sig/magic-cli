package cli.core.tools

import std.fs.{Path, File, exists}
import std.collection.{ArrayList, HashMap}
import stdx.encoding.json.*
import magic.log.LogUtils
import magic.dsl.*
import magic.prelude.*

/**
 * 代码质量分析工具集
 * 提供函数复杂度、代码度量、代码味道检测等功能
 */
@toolset
public class CodeQualityToolset {
    
    /**
     * Tool 1: 分析函数的复杂度和质量
     */
    @tool[
        description: """
Analyze the complexity and quality of a specific function in a Cangjie file.
Provides detailed metrics including cyclomatic complexity, lines of code, nesting depth, and quality recommendations.

Use this when you want to:
- Evaluate if a function is too complex
- Check if a function needs refactoring
- Get specific quality metrics for a function
- Understand function maintainability

Returns detailed analysis including:
- Cyclomatic complexity score (1 = simple, 10+ = complex, 20+ = very complex)
- Function length in lines
- Maximum nesting depth
- Quality level assessment
- Specific recommendations for improvement

Example usage:
- "Analyze the complexity of the processOrder function"
- "Is the calculateTotal function too complex?"
- "Check the quality of the validateUser function"
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file (must end with .cj)",
            functionName: "Name of the function to analyze"
        }
    ]
    public func analyzeFunction(filePath: String, functionName: String): String {
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
        
        try {
            // 读取文件内容
            let content = String.fromUtf8(File.readFrom(path))
            
            // 查找函数
            let functionInfo = findFunction(content, functionName)
            
            match (functionInfo) {
                case Some((startLine, endLine, functionBody)) =>
                    // 分析函数
                    let complexity = calculateComplexity(functionBody)
                    let lineCount = endLine - startLine + 1
                    let maxNesting = calculateMaxNesting(functionBody)
                    
                    // 评估质量等级
                    let qualityLevel = assessQualityLevel(complexity, lineCount, maxNesting)
                    
                    // 生成建议
                    let recommendations = generateRecommendations(complexity, lineCount, maxNesting)
                    
                    // 构建结果
                    var result = StringBuilder()
                    result.append("📊 Function Analysis: ${functionName}\n\n")
                    result.append("📍 Location: lines ${startLine}-${endLine}\n")
                    result.append("📏 Lines of Code: ${lineCount}\n")
                    result.append("🔢 Cyclomatic Complexity: ${complexity}\n")
                    result.append("📐 Max Nesting Depth: ${maxNesting}\n")
                    result.append("⭐ Quality Level: ${qualityLevel}\n")
                    result.append("\n")
                    
                    if (recommendations.size > 0) {
                        result.append("💡 Recommendations:\n")
                        for (rec in recommendations) {
                            result.append("  • ${rec}\n")
                        }
                    } else {
                        result.append("✅ No issues detected. Function looks good!\n")
                    }
                    
                    return result.toString()
                    
                case None =>
                    return "Error: Function '${functionName}' not found in ${filePath}"
            }
            
        } catch (e: Exception) {
            LogUtils.error("分析函数失败: ${e}")
            return "Error: ${e.message}"
        }
    }
    
    /**
     * Tool 2: 分析整个文件的代码质量
     */
    @tool[
        description: """
Analyze the overall code quality of a Cangjie file.
Provides comprehensive metrics, identifies potential issues, and gives an overall quality assessment.

Use this when you want to:
- Get an overview of file quality
- Identify which functions need attention
- Understand file complexity distribution
- Get a quality scorecard

Returns:
- File statistics (total lines, code lines, comment lines, blank lines)
- Function complexity distribution
- List of code smells detected
- Overall quality score (0-100)
- Top issues to address

Example usage:
- "Analyze the quality of user_manager.cj"
- "What's the overall quality of database.cj?"
- "Check for issues in authentication.cj"
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file (must end with .cj)"
        }
    ]
    public func analyzeFile(filePath: String): String {
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
        
        try {
            // 读取文件内容
            let content = String.fromUtf8(File.readFrom(path))
            let lines = content.split("\n")
            
            // 统计基本指标
            let totalLines = lines.size
            let codeLines = countCodeLines(lines)
            let commentLines = countCommentLines(lines)
            let blankLines = countBlankLines(lines)
            
            // 分析所有函数
            let functions = findAllFunctions(content)
            var complexFunctions = ArrayList<(String, Int64)>()
            var longFunctions = ArrayList<(String, Int64)>()
            var totalComplexity: Int64 = 0
            
            for ((funcName, startLine, endLine, funcBody) in functions) {
                let complexity = calculateComplexity(funcBody)
                let lineCount = endLine - startLine + 1
                
                totalComplexity += complexity
                
                if (complexity > 10) {
                    complexFunctions.add((funcName, complexity))
                }
                
                if (lineCount > 50) {
                    longFunctions.add((funcName, lineCount))
                }
            }
            
            // 计算质量分数
            let qualityScore = calculateFileQualityScore(
                codeLines,
                commentLines,
                functions.size,
                complexFunctions.size,
                longFunctions.size
            )
            
            // 构建结果
            var result = StringBuilder()
            let pathParts = path.toString().split("/")
            let fileName = pathParts[pathParts.size - 1]
            
            result.append("📄 File Quality Analysis: ${fileName}\n\n")
            
            result.append("📊 Statistics:\n")
            result.append("  Total Lines: ${totalLines}\n")
            result.append("  Code Lines: ${codeLines}\n")
            result.append("  Comment Lines: ${commentLines}\n")
            result.append("  Blank Lines: ${blankLines}\n")
            result.append("  Comment Coverage: ${calculatePercentage(commentLines, codeLines)}%\n")
            result.append("\n")
            
            result.append("⚙️ Functions:\n")
            result.append("  Total Functions: ${functions.size}\n")
            if (functions.size > 0) {
                let avgComplexity = totalComplexity / functions.size
                result.append("  Average Complexity: ${avgComplexity}\n")
            }
            result.append("\n")
            
            result.append("🎯 Quality Score: ${qualityScore}/100\n")
            result.append("${getScoreEmoji(qualityScore)} ${getScoreLabel(qualityScore)}\n")
            result.append("\n")
            
            if (complexFunctions.size > 0) {
                result.append("⚠️ Complex Functions (complexity > 10):\n")
                for ((name, complexity) in complexFunctions) {
                    result.append("  • ${name}: ${complexity}\n")
                }
                result.append("\n")
            }
            
            if (longFunctions.size > 0) {
                result.append("📏 Long Functions (> 50 lines):\n")
                for ((name, lineCount) in longFunctions) {
                    result.append("  • ${name}: ${lineCount} lines\n")
                }
                result.append("\n")
            }
            
            if (complexFunctions.size == 0 && longFunctions.size == 0) {
                result.append("✅ No major issues detected!\n")
            }
            
            return result.toString()
            
        } catch (e: Exception) {
            LogUtils.error("分析文件失败: ${e}")
            return "Error: ${e.message}"
        }
    }
    
    /**
     * Tool 3: 获取代码度量指标
     */
    @tool[
        description: """
Get detailed code metrics for a Cangjie file.
Useful for understanding code characteristics, tracking quality trends, and making data-driven refactoring decisions.

Provides metrics including:
- Line counts (total, code, comments, blank)
- Symbol counts (functions, classes, structs)
- Complexity metrics (average, max, distribution)
- Function size metrics (average, max, distribution)
- Comment coverage percentage

Use this for:
- Code quality dashboards
- Tracking metrics over time
- Understanding codebase characteristics
- Identifying outliers

Example usage:
- "Show me the metrics for user_service.cj"
- "What are the stats for database.cj?"
- "Get code metrics for authentication.cj"
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file (must end with .cj)"
        }
    ]
    public func getCodeMetrics(filePath: String): String {
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
        
        try {
            // 读取文件内容
            let content = String.fromUtf8(File.readFrom(path))
            let lines = content.split("\n")
            
            // 基本统计
            let totalLines = lines.size
            let codeLines = countCodeLines(lines)
            let commentLines = countCommentLines(lines)
            let blankLines = countBlankLines(lines)
            
            // 分析函数
            let functions = findAllFunctions(content)
            var totalFuncLines: Int64 = 0
            var maxFuncLines: Int64 = 0
            var minFuncLines: Int64 = 999999
            var totalComplexity: Int64 = 0
            var maxComplexity: Int64 = 0
            
            for ((_, startLine, endLine, funcBody) in functions) {
                let funcLines = endLine - startLine + 1
                let complexity = calculateComplexity(funcBody)
                
                totalFuncLines += funcLines
                if (funcLines > maxFuncLines) { maxFuncLines = funcLines }
                if (funcLines < minFuncLines) { minFuncLines = funcLines }
                
                totalComplexity += complexity
                if (complexity > maxComplexity) { maxComplexity = complexity }
            }
            
            // 构建 JSON 结果
            let metrics = HashMap<String, JsonValue>()
            
            // Lines
            let linesMetrics = HashMap<String, JsonValue>()
            linesMetrics["total"] = JsonInt(totalLines)
            linesMetrics["code"] = JsonInt(codeLines)
            linesMetrics["comments"] = JsonInt(commentLines)
            linesMetrics["blank"] = JsonInt(blankLines)
            metrics["lines"] = JsonObject(linesMetrics)
            
            // Functions
            let funcMetrics = HashMap<String, JsonValue>()
            funcMetrics["count"] = JsonInt(functions.size)
            if (functions.size > 0) {
                funcMetrics["avgLength"] = JsonInt(totalFuncLines / functions.size)
                funcMetrics["maxLength"] = JsonInt(maxFuncLines)
                funcMetrics["minLength"] = JsonInt(minFuncLines)
                funcMetrics["avgComplexity"] = JsonInt(totalComplexity / functions.size)
                funcMetrics["maxComplexity"] = JsonInt(maxComplexity)
            }
            metrics["functions"] = JsonObject(funcMetrics)
            
            // Quality
            let qualityMetrics = HashMap<String, JsonValue>()
            qualityMetrics["commentCoverage"] = JsonInt(calculatePercentage(commentLines, codeLines))
            metrics["quality"] = JsonObject(qualityMetrics)
            
            return JsonObject(metrics).toJsonString()
            
        } catch (e: Exception) {
            LogUtils.error("获取代码度量失败: ${e}")
            return "Error: ${e.message}"
        }
    }
    
    /**
     * Tool 4: 检测代码味道
     */
    @tool[
        description: """
Detect common code smells and anti-patterns in a Cangjie file.
Helps identify areas that may need refactoring or improvement.

Detects:
- Long functions (> 50 lines)
- Complex functions (cyclomatic complexity > 10)
- Deep nesting (> 3 levels)
- Magic numbers (unnamed numeric literals)
- Poor comment coverage (< 10%)
- Very long files (> 500 lines)

Returns a prioritized list of issues with:
- Issue type and severity (high/medium/low)
- Location (file, function, line)
- Specific description
- Recommendation for fixing

Use this to:
- Find refactoring opportunities
- Improve code maintainability
- Follow best practices
- Reduce technical debt

Example usage:
- "Find code smells in user_manager.cj"
- "What needs refactoring in database.cj?"
- "Check for issues in payment_processor.cj"
""",
        parameters: {
            filePath: "Absolute path to the Cangjie file (must end with .cj)"
        }
    ]
    public func detectCodeSmells(filePath: String): String {
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
        
        try {
            // 读取文件内容
            let content = String.fromUtf8(File.readFrom(path))
            let lines = content.split("\n")
            
            var smells = ArrayList<(String, String, String, String)>() // (severity, smellType, location, description)
            
            // 检查文件长度
            if (lines.size > 500) {
                smells.add(("medium", "Long File", "entire file", "File has ${lines.size} lines (> 500). Consider splitting into smaller modules."))
            }
            
            // 检查注释覆盖率
            let codeLines = countCodeLines(lines)
            let commentLines = countCommentLines(lines)
            let commentCoverage = calculatePercentage(commentLines, codeLines)
            if (commentCoverage < 10) {
                smells.add(("low", "Low Comment Coverage", "entire file", "Only ${commentCoverage}% comment coverage. Consider adding more documentation."))
            }
            
            // 分析每个函数
            let functions = findAllFunctions(content)
            for ((funcName, startLine, endLine, funcBody) in functions) {
                let funcLines = endLine - startLine + 1
                let complexity = calculateComplexity(funcBody)
                let maxNesting = calculateMaxNesting(funcBody)
                
                // 检查长函数
                if (funcLines > 100) {
                    smells.add(("high", "Very Long Function", "${funcName} (line ${startLine})", "Function has ${funcLines} lines (> 100). Break it down into smaller functions."))
                } else if (funcLines > 50) {
                    smells.add(("medium", "Long Function", "${funcName} (line ${startLine})", "Function has ${funcLines} lines (> 50). Consider refactoring."))
                }
                
                // 检查复杂度
                if (complexity > 20) {
                    smells.add(("high", "Very Complex Function", "${funcName} (line ${startLine})", "Cyclomatic complexity is ${complexity} (> 20). Simplify control flow."))
                } else if (complexity > 10) {
                    smells.add(("medium", "Complex Function", "${funcName} (line ${startLine})", "Cyclomatic complexity is ${complexity} (> 10). Consider simplifying."))
                }
                
                // 检查嵌套深度
                if (maxNesting > 4) {
                    smells.add(("high", "Deep Nesting", "${funcName} (line ${startLine})", "Maximum nesting depth is ${maxNesting} (> 4). Flatten the code structure."))
                } else if (maxNesting > 3) {
                    smells.add(("medium", "Moderate Nesting", "${funcName} (line ${startLine})", "Maximum nesting depth is ${maxNesting} (> 3). Consider early returns."))
                }
            }
            
            // 构建结果
            var result = StringBuilder()
            let pathParts = path.toString().split("/")
            let fileName = pathParts[pathParts.size - 1]
            
            result.append("🔍 Code Smells Detection: ${fileName}\n\n")
            
            if (smells.size == 0) {
                result.append("✅ No code smells detected! The code looks clean.\n")
            } else {
                result.append("Found ${smells.size} issue(s):\n\n")
                
                // 按严重程度排序和分组
                var highSeverity = ArrayList<(String, String, String, String)>()
                var mediumSeverity = ArrayList<(String, String, String, String)>()
                var lowSeverity = ArrayList<(String, String, String, String)>()
                
                for (smell in smells) {
                    match (smell) {
                        case (severity, smellType, location, description) =>
                            if (severity == "high") {
                                highSeverity.add(smell)
                            } else if (severity == "medium") {
                                mediumSeverity.add(smell)
                            } else {
                                lowSeverity.add(smell)
                            }
                    }
                }
                
                // 输出高严重度问题
                if (highSeverity.size > 0) {
                    result.append("🔴 High Severity (${highSeverity.size}):\n")
                    for ((_, smellType, location, description) in highSeverity) {
                        result.append("  • [${smellType}] ${location}\n")
                        result.append("    ${description}\n")
                    }
                    result.append("\n")
                }
                
                // 输出中严重度问题
                if (mediumSeverity.size > 0) {
                    result.append("🟡 Medium Severity (${mediumSeverity.size}):\n")
                    for ((_, smellType, location, description) in mediumSeverity) {
                        result.append("  • [${smellType}] ${location}\n")
                        result.append("    ${description}\n")
                    }
                    result.append("\n")
                }
                
                // 输出低严重度问题
                if (lowSeverity.size > 0) {
                    result.append("🟢 Low Severity (${lowSeverity.size}):\n")
                    for ((_, smellType, location, description) in lowSeverity) {
                        result.append("  • [${smellType}] ${location}\n")
                        result.append("    ${description}\n")
                    }
                    result.append("\n")
                }
                
                result.append("💡 Tip: Address high severity issues first for maximum impact.\n")
            }
            
            return result.toString()
            
        } catch (e: Exception) {
            LogUtils.error("检测代码味道失败: ${e}")
            return "Error: ${e.message}"
        }
    }
    
    // ==================== 辅助函数 ====================
    
    /**
     * 查找函数定义并返回其位置和内容
     * 返回：Some((startLine, endLine, functionBody)) 或 None
     */
    private static func findFunction(content: String, functionName: String): Option<(Int64, Int64, String)> {
        let lines = content.split("\n")
        var startLine: Int64 = -1
        var braceCount: Int64 = 0
        var inFunction = false
        var functionBody = StringBuilder()
        
        for (i in 0..lines.size) {
            let line = lines[i]
            let trimmed = line.trimAscii()
            
            // 查找函数定义
            if (!inFunction && (trimmed.contains("func ${functionName}(") || trimmed.contains("func ${functionName} ("))) {
                startLine = i + 1 // 1-based行号
                inFunction = true
            }
            
            if (inFunction) {
                functionBody.append(line)
                functionBody.append("\n")
                
                // 统计大括号
                for (ch in line.toRuneArray()) {
                    if (ch == r'{') {
                        braceCount += 1
                    } else if (ch == r'}') {
                        braceCount -= 1
                        if (braceCount == 0) {
                            // 函数结束
                            return Some((startLine, i + 1, functionBody.toString()))
                        }
                    }
                }
            }
        }
        
        return None
    }
    
    /**
     * 查找所有函数定义
     * 返回：Array<(functionName, startLine, endLine, functionBody)>
     */
    private static func findAllFunctions(content: String): Array<(String, Int64, Int64, String)> {
        let lines = content.split("\n")
        var functions = ArrayList<(String, Int64, Int64, String)>()
        var i: Int64 = 0
        
        while (i < lines.size) {
            let line = lines[i]
            let trimmed = line.trimAscii()
            
            // 检查是否是函数定义
            if (trimmed.contains("func ") && trimmed.contains("(")) {
                // 提取函数名
                if (let Some(funcName) <- extractFunctionName(trimmed)) {
                    // 查找函数体
                    var startLine = i + 1 // 1-based
                    var braceCount: Int64 = 0
                    var functionBody = StringBuilder()
                    var j = i
                    var foundStart = false
                    
                    while (j < lines.size) {
                        let currentLine = lines[j]
                        functionBody.append(currentLine)
                        functionBody.append("\n")
                        
                        for (ch in currentLine.toRuneArray()) {
                            if (ch == r'{') {
                                braceCount += 1
                                foundStart = true
                            } else if (ch == r'}') {
                                braceCount -= 1
                                if (foundStart && braceCount == 0) {
                                    // 函数结束
                                    functions.add((funcName, startLine, j + 1, functionBody.toString()))
                                    i = j
                                    break
                                }
                            }
                        }
                        
                        if (foundStart && braceCount == 0) {
                            break
                        }
                        j += 1
                    }
                }
            }
            
            i += 1
        }
        
        return functions.toArray()
    }
    
    /**
     * 从函数定义行提取函数名
     */
    private static func extractFunctionName(line: String): Option<String> {
        // 查找 "func" 关键字
        if (let Some(funcIndex) <- line.indexOf("func ")) {
            let afterFunc = line[(funcIndex + 5)..]
            // 查找左括号
            if (let Some(parenIndex) <- afterFunc.indexOf("(")) {
                let funcName = afterFunc[0..parenIndex].trimAscii()
                if (funcName.size > 0) {
                    return Some(funcName)
                }
            }
        }
        return None
    }
    
    /**
     * 计算圈复杂度
     */
    private static func calculateComplexity(functionBody: String): Int64 {
        var complexity: Int64 = 1 // 基础复杂度
        
        // 统计控制流语句
        let keywords = [
            "if ", "else ", "match ", "case ", 
            "for ", "while ", "catch ", "&&", "||"
        ]
        
        for (keyword in keywords) {
            complexity += countOccurrences(functionBody, keyword)
        }
        
        return complexity
    }
    
    /**
     * 计算最大嵌套深度
     */
    private static func calculateMaxNesting(code: String): Int64 {
        var maxDepth: Int64 = 0
        var currentDepth: Int64 = 0
        
        for (ch in code.toRuneArray()) {
            if (ch == r'{') {
                currentDepth += 1
                if (currentDepth > maxDepth) {
                    maxDepth = currentDepth
                }
            } else if (ch == r'}') {
                currentDepth -= 1
            }
        }
        
        return maxDepth
    }
    
    /**
     * 统计字符串中子串出现次数
     */
    private static func countOccurrences(text: String, pattern: String): Int64 {
        var count: Int64 = 0
        var searchStart: Int64 = 0
        
        while (searchStart < text.size) {
            let remaining = text[searchStart..]
            if (let Some(index) <- remaining.indexOf(pattern)) {
                count += 1
                searchStart = searchStart + index + pattern.size
            } else {
                break
            }
        }
        
        return count
    }
    
    /**
     * 统计代码行数（非空非注释）
     */
    private static func countCodeLines(lines: Array<String>): Int64 {
        var count: Int64 = 0
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.size > 0 && !trimmed.startsWith("//") && !trimmed.startsWith("/*") && !trimmed.startsWith("*")) {
                count += 1
            }
        }
        return count
    }
    
    /**
     * 统计注释行数
     */
    private static func countCommentLines(lines: Array<String>): Int64 {
        var count: Int64 = 0
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.startsWith("//") || trimmed.startsWith("/*") || trimmed.startsWith("*")) {
                count += 1
            }
        }
        return count
    }
    
    /**
     * 统计空白行数
     */
    private static func countBlankLines(lines: Array<String>): Int64 {
        var count: Int64 = 0
        for (line in lines) {
            if (line.trimAscii().size == 0) {
                count += 1
            }
        }
        return count
    }
    
    /**
     * 评估质量等级
     */
    private static func assessQualityLevel(complexity: Int64, lineCount: Int64, maxNesting: Int64): String {
        var issues: Int64 = 0
        
        if (complexity > 20) { issues += 3 }
        else if (complexity > 10) { issues += 2 }
        else if (complexity > 5) { issues += 1 }
        
        if (lineCount > 100) { issues += 3 }
        else if (lineCount > 50) { issues += 2 }
        else if (lineCount > 20) { issues += 1 }
        
        if (maxNesting > 4) { issues += 3 }
        else if (maxNesting > 3) { issues += 2 }
        else if (maxNesting > 2) { issues += 1 }
        
        if (issues == 0) { return "⭐⭐⭐⭐⭐ Excellent" }
        if (issues <= 2) { return "⭐⭐⭐⭐ Good" }
        if (issues <= 4) { return "⭐⭐⭐ Fair" }
        if (issues <= 6) { return "⭐⭐ Needs Improvement" }
        return "⭐ Poor - Refactoring Recommended"
    }
    
    /**
     * 生成改进建议
     */
    private static func generateRecommendations(complexity: Int64, lineCount: Int64, maxNesting: Int64): Array<String> {
        var recommendations = ArrayList<String>()
        
        if (complexity > 20) {
            recommendations.add("Critical: Complexity is ${complexity}. Break down into smaller functions.")
        } else if (complexity > 10) {
            recommendations.add("High complexity (${complexity}). Consider simplifying control flow.")
        }
        
        if (lineCount > 100) {
            recommendations.add("Critical: Function is ${lineCount} lines. Split into multiple functions.")
        } else if (lineCount > 50) {
            recommendations.add("Function is ${lineCount} lines. Consider breaking it down.")
        }
        
        if (maxNesting > 4) {
            recommendations.add("Critical: Nesting depth is ${maxNesting}. Use early returns or extract methods.")
        } else if (maxNesting > 3) {
            recommendations.add("Nesting depth is ${maxNesting}. Consider flattening the structure.")
        }
        
        return recommendations.toArray()
    }
    
    /**
     * 计算文件质量分数
     */
    private static func calculateFileQualityScore(
        codeLines: Int64,
        commentLines: Int64,
        functionCount: Int64,
        complexFunctionCount: Int64,
        longFunctionCount: Int64
    ): Int64 {
        var score: Int64 = 100
        
        // 注释覆盖率影响
        let commentCoverage = calculatePercentage(commentLines, codeLines)
        if (commentCoverage < 5) { score -= 20 }
        else if (commentCoverage < 10) { score -= 10 }
        else if (commentCoverage < 15) { score -= 5 }
        
        // 复杂函数影响
        if (functionCount > 0) {
            let complexRatio = (complexFunctionCount * 100) / functionCount
            if (complexRatio > 50) { score -= 30 }
            else if (complexRatio > 30) { score -= 20 }
            else if (complexRatio > 10) { score -= 10 }
        }
        
        // 长函数影响
        if (functionCount > 0) {
            let longRatio = (longFunctionCount * 100) / functionCount
            if (longRatio > 50) { score -= 20 }
            else if (longRatio > 30) { score -= 15 }
            else if (longRatio > 10) { score -= 5 }
        }
        
        // 确保分数在 0-100 范围内
        if (score < 0) { score = 0 }
        if (score > 100) { score = 100 }
        
        return score
    }
    
    /**
     * 计算百分比
     */
    private static func calculatePercentage(part: Int64, total: Int64): Int64 {
        if (total == 0) { return 0 }
        return (part * 100) / total
    }
    
    /**
     * 根据分数获取emoji
     */
    private static func getScoreEmoji(score: Int64): String {
        if (score >= 90) { return "🏆" }
        if (score >= 80) { return "⭐" }
        if (score >= 70) { return "👍" }
        if (score >= 60) { return "⚠️" }
        return "❌"
    }
    
    /**
     * 根据分数获取标签
     */
    private static func getScoreLabel(score: Int64): String {
        if (score >= 90) { return "Excellent Quality" }
        if (score >= 80) { return "Good Quality" }
        if (score >= 70) { return "Fair Quality" }
        if (score >= 60) { return "Needs Improvement" }
        return "Poor Quality - Refactoring Recommended"
    }
}

