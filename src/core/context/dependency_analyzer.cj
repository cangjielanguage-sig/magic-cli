package cli.core.context

import std.fs.{Path, File, exists}
import std.collection.{HashMap, ArrayList}
import magic.log.LogUtils

/**
 * 文件依赖信息
 */
public class FileDependencies {
    public let filePath: Path
    public let imports: Array<String>
    
    public init(filePath: Path, imports: Array<String>) {
        this.filePath = filePath
        this.imports = imports
    }
}

/**
 * 依赖图节点
 */
public class DependencyNode {
    public let path: Path
    public var dependencies: ArrayList<String>   // 依赖的包名
    public var dependents: ArrayList<Path>       // 被哪些文件依赖
    
    public init(path: Path) {
        this.path = path
        this.dependencies = ArrayList<String>()
        this.dependents = ArrayList<Path>()
    }
}

/**
 * 依赖图
 */
public class DependencyGraph {
    private var nodes: HashMap<String, DependencyNode>
    
    public init() {
        this.nodes = HashMap<String, DependencyNode>()
    }
    
    /**
     * 添加节点
     */
    public func addNode(path: Path): Unit {
        let key = path.toString()
        if (this.nodes.get(key).isNone()) {
            this.nodes[key] = DependencyNode(path)
        }
    }
    
    /**
     * 添加依赖边（from 依赖 importPkg）
     */
    public func addDependency(from: Path, importPkg: String): Unit {
        this.addNode(from)
        
        if (let Some(n) <- this.nodes.get(from.toString())) {
            // 检查是否已存在
            var found = false
            for (dep in n.dependencies) {
                if (dep == importPkg) {
                    found = true
                    break
                }
            }
            if (!found) {
                n.dependencies.add(importPkg)
            }
        }
    }
    
    /**
     * 获取文件的所有导入包
     */
    public func getDependencies(path: Path): Array<String> {
        if (let Some(n) <- this.nodes.get(path.toString())) {
            return n.dependencies.toArray()
        }
        return ArrayList<String>().toArray()
    }
    
    /**
     * 获取所有节点的路径
     */
    public func getAllNodes(): Array<Path> {
        let paths = ArrayList<Path>()
        for ((_, node) in this.nodes) {
            paths.add(node.path)
        }
        return paths.toArray()
    }
    
    /**
     * 获取节点数量
     */
    public func size(): Int64 {
        return this.nodes.size
    }
    
    /**
     * 清空依赖图
     */
    public func clear(): Unit {
        this.nodes.clear()
    }
}

/**
 * 依赖分析器 - 简化版 v1.0
 * 
 * 功能：
 * - 分析仓颉文件的 import 依赖
 * - 构建项目依赖图
 * - 提供依赖查询
 */
public class DependencyAnalyzer {
    private var graph: DependencyGraph
    private var contextEngine: ContextEngine
    
    public init(contextEngine: ContextEngine) {
        this.graph = DependencyGraph()
        this.contextEngine = contextEngine
    }
    
    /**
     * 分析单个文件的依赖
     */
    public func analyzeFile(path: Path): FileDependencies {
        var imports = ArrayList<String>()
        
        // 读取文件内容（优先从缓存）
        var content = ""
        if (let Some(c) <- this.contextEngine.getFile(path)) {
            content = c
        } else {
            // 从磁盘读取
            if (exists(path)) {
                try {
                    content = String.fromUtf8(File.readFrom(path))
                    } catch (e: Exception) {
                        LogUtils.error("Failed to read file ${path.toString()}: ${e.message}")
                        return FileDependencies(path, ArrayList<String>().toArray())
                    }
                } else {
                    return FileDependencies(path, ArrayList<String>().toArray())
                }
        }
        
        // 提取 import 语句
        imports = this.extractImports(content)
        
        // 更新依赖图
        for (importPkg in imports) {
            this.graph.addDependency(path, importPkg)
        }
        
        LogUtils.debug("Analyzed file ${path.toString()}: found ${imports.size} imports")
        
        return FileDependencies(path, imports.toArray())
    }
    
    /**
     * 提取 import 语句
     */
    private func extractImports(content: String): ArrayList<String> {
        let imports = ArrayList<String>()
        
        // 逐行扫描
        for (line in content.split("\n")) {
            let trimmed = line.trimAscii()
            
            // 检查是否是 import 语句
            if (trimmed.startsWith("import ")) {
                let importPkg = this.extractPackageName(trimmed)
                if (!importPkg.isEmpty()) {
                    imports.add(importPkg)
                }
            }
        }
        
        return imports
    }
    
    /**
     * 从 import 语句提取包名
     * 例如：
     * - "import std.fs.{Path, File}" -> "std.fs"
     * - "import cli.core.config.CliConfig" -> "cli.core.config"
     */
    private func extractPackageName(importLine: String): String {
        // 移除 "import " 前缀（7个字符）
        if (importLine.size < 8) {
            return ""
        }
        
        var line = importLine[7..].trimAscii()
        
        // 处理花括号 {xxx}
        if (let Some(braceIndex) <- line.indexOf("{")) {
            line = line[0..braceIndex].trimAscii()
            // 移除末尾的点
            if (line.endsWith(".")) {
                if (line.size > 1) {
                    line = line[0..(line.size - 1)]
                } else {
                    return ""
                }
            }
        } else {
            // 没有花括号，可能是单个符号导入
            // 例如 "import cli.core.config.CliConfig"
            // 我们只保留包路径，移除最后一个点后的部分
            if (let Some(lastDotIndex) <- line.lastIndexOf(".")) {
                line = line[0..lastDotIndex]
            }
        }
        
        return line
    }
    
    /**
     * 获取文件的依赖包列表
     */
    public func getDependencies(path: Path): Array<String> {
        return this.graph.getDependencies(path)
    }
    
    /**
     * 查找所有依赖特定包的文件
     */
    public func findDependents(packageName: String): Array<Path> {
        let dependents = ArrayList<Path>()
        
        for (nodePath in this.graph.getAllNodes()) {
            let deps = this.graph.getDependencies(nodePath)
            for (dep in deps) {
                if (dep == packageName || dep.startsWith("${packageName}.")) {
                    dependents.add(nodePath)
                    break
                }
            }
        }
        
        return dependents.toArray()
    }
    
    /**
     * 批量分析文件
     */
    public func analyzeFiles(paths: Array<Path>): Unit {
        for (path in paths) {
            let _ = this.analyzeFile(path)
        }
    }
    
    /**
     * 获取依赖图
     */
    public func getGraph(): DependencyGraph {
        return this.graph
    }
    
    /**
     * 清空分析结果
     */
    public func clear(): Unit {
        this.graph.clear()
        LogUtils.debug("Cleared dependency graph")
    }
    
    /**
     * 获取统计信息
     */
    public func getStats(): String {
        return "DependencyAnalyzer: ${this.graph.size()} files analyzed"
    }
    
    // ============================================================================
    // 🆕 阶段三：关联文件推荐和依赖族识别
    // ============================================================================
    
    /**
     * 🆕 推荐相关文件
     * 基于依赖关系推荐与当前文件相关的其他文件
     * 
     * @param currentFile 当前文件路径
     * @param maxRecommendations 最大推荐数量（默认5）
     * @return 推荐的文件路径数组
     */
    public func recommendRelatedFiles(
        currentFile: Path,
        maxRecommendations: Int64
    ): Array<Path> {
        let related = ArrayList<Path>()
        
        // 1. 找出当前文件依赖的包
        let deps = this.getDependencies(currentFile)
        
        if (deps.size == 0) {
            return related.toArray()
        }
        
        // 2. 找出使用相同包的其他文件
        for (dep in deps) {
            let dependents = this.findDependents(dep)
            for (file in dependents) {
                if (file.toString() != currentFile.toString()) {
                    // 避免重复添加
                    var exists = false
                    for (existing in related) {
                        if (existing.toString() == file.toString()) {
                            exists = true
                            break
                        }
                    }
                    if (!exists) {
                        related.add(file)
                    }
                }
            }
        }
        
        // 3. 限制数量
        if (related.size <= maxRecommendations) {
            return related.toArray()
        }
        
        // 取前N个
        let result = ArrayList<Path>()
        for (i in 0..maxRecommendations) {
            result.add(related[i])
        }
        return result.toArray()
    }
    
    /**
     * 🆕 计算文件之间的关联度
     * 使用 Jaccard 相似度：交集大小 / 并集大小
     * 返回 0.0-1.0 之间的分数
     * 
     * @param file1 文件1路径
     * @param file2 文件2路径
     * @return 关联度分数 (0.0-1.0)
     */
    public func calculateRelatedness(file1: Path, file2: Path): Float64 {
        let deps1 = this.getDependencies(file1)
        let deps2 = this.getDependencies(file2)
        
        if (deps1.size == 0 || deps2.size == 0) {
            return 0.0
        }
        
        // 计算共同依赖的数量（交集）
        var commonCount: Int64 = 0
        for (d1 in deps1) {
            for (d2 in deps2) {
                if (d1 == d2) {
                    commonCount += 1
                    break
                }
            }
        }
        
        // Jaccard 相似度：交集 / 并集
        // 并集大小 = size1 + size2 - 交集大小
        let union = deps1.size + deps2.size - commonCount
        return if (union > 0) {
            Float64(commonCount) / Float64(union)
        } else {
            0.0
        }
    }
    
    /**
     * 🆕 获取文件的"依赖族"
     * 返回与该文件强相关的所有文件
     * 
     * @param file 目标文件路径
     * @param threshold 关联度阈值 (0.0-1.0)，建议0.3
     * @return 依赖族中的文件路径数组
     */
    public func getDependencyCluster(file: Path, threshold: Float64): Array<Path> {
        let cluster = ArrayList<Path>()
        
        for (nodePath in this.graph.getAllNodes()) {
            if (nodePath.toString() == file.toString()) {
                continue
            }
            
            let relatedness = this.calculateRelatedness(file, nodePath)
            if (relatedness >= threshold) {
                cluster.add(nodePath)
            }
        }
        
        return cluster.toArray()
    }
}

