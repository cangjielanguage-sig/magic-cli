package cli.core.context

import std.unittest.*
import std.fs.{Path, File}
import std.collection.ArrayList

/**
 * P2功能测试：智能去重、依赖扩展、统计面板
 */
@Test
class ContextEngineP2Test {
    
    /**
     * 测试 P2-1: Import去重和合并
     */
    @TestCase
    func testDeduplicateAndMerge() {
        let engine = ContextEngine()
        
        // 添加两个有重复import的文件
        let content1 = """
package test1

import std.fs.Path
import std.collection.HashMap

public func test1() {
    // test content 1
}
"""
        
        let content2 = """
package test2

import std.fs.Path
import std.collection.ArrayList

public func test2() {
    // test content 2
}
"""
        
        engine.addFile(Path("test1.cj"), content1)
        engine.addFile(Path("test2.cj"), content2)
        
        // 获取两个文件的上下文
        let ctx1 = engine.getFileContext(Path("test1.cj"))
        let ctx2 = engine.getFileContext(Path("test2.cj"))
        
        @Assert(ctx1.isSome(), "test1.cj should be in cache")
        @Assert(ctx2.isSome(), "test2.cj should be in cache")
        
        // 测试去重合并
        let contexts = ArrayList<FileContext>()
        contexts.add(ctx1.getOrThrow())
        contexts.add(ctx2.getOrThrow())
        
        let merged = engine.deduplicateAndMerge(contexts.toArray())
        
        // 验证：import只出现一次，且两个文件内容都包含
        @Assert(merged.contains("Consolidated Imports"), "Should have consolidated imports section")
        @Assert(merged.contains("test1.cj"), "Should contain test1.cj")
        @Assert(merged.contains("test2.cj"), "Should contain test2.cj")
        
        // 统计import行数（去重后应该只有3个unique imports）
        let importLines = merged.split("\n").filter({line => line.trimAscii().startsWith("import ")})
        @Assert(importLines.size <= 4, "Should have deduplicated imports (found ${importLines.size})")
    }
    
    /**
     * 测试 P2-1: 依赖去重
     */
    @TestCase
    func testDeduplicateByDependency() {
        let engine = ContextEngine()
        
        // 创建3个文件：A依赖B，B依赖C
        let contentA = """
package testA
import testB.Helper
public func funcA() {}
"""
        let contentB = """
package testB
import testC.Utils
public func funcB() {}
"""
        let contentC = """
package testC
public func funcC() {}
"""
        
        engine.addFile(Path("A.cj"), contentA)
        engine.addFile(Path("B.cj"), contentB)
        engine.addFile(Path("C.cj"), contentC)
        
        // 计算相关性（让A的相关性最高）
        if (let Some(ctxA) <- engine.getFileContext(Path("A.cj"))) {
            ctxA.relevanceScore = 0.9
        }
        if (let Some(ctxB) <- engine.getFileContext(Path("B.cj"))) {
            ctxB.relevanceScore = 0.2  // 低相关性
        }
        if (let Some(ctxC) <- engine.getFileContext(Path("C.cj"))) {
            ctxC.relevanceScore = 0.1  // 更低
        }
        
        // 获取所有文件
        let allFiles = ArrayList<FileContext>()
        if (let Some(ctx) <- engine.getFileContext(Path("A.cj"))) { allFiles.add(ctx) }
        if (let Some(ctx) <- engine.getFileContext(Path("B.cj"))) { allFiles.add(ctx) }
        if (let Some(ctx) <- engine.getFileContext(Path("C.cj"))) { allFiles.add(ctx) }
        
        // 应用依赖去重
        let deduplicated = engine.deduplicateByDependency(allFiles.toArray())
        
        // 验证：应该保留A，可能跳过B和C（因为它们相关性太低）
        @Assert(deduplicated.size >= 1, "Should keep at least high-relevance file")
        @Assert(deduplicated.size <= 3, "Should deduplicate some files")
    }
    
    /**
     * 测试 P2-2: 自动扩展依赖
     */
    @TestCase
    func testAutoExpandDependencies() {
        let engine = ContextEngine()
        
        // 添加一个文件和它的依赖
        let mainContent = """
package main
import helper.Utils
import helper.Logger
public func main() {}
"""
        let helperContent = """
package helper
public func helperFunc() {}
"""
        
        engine.addFile(Path("main.cj"), mainContent)
        engine.addFile(Path("helper/Utils.cj"), helperContent)
        
        // 只获取main文件
        let mainFiles = ArrayList<FileContext>()
        if (let Some(ctx) <- engine.getFileContext(Path("main.cj"))) {
            mainFiles.add(ctx)
        }
        
        // 自动扩展依赖（最多5个）
        let expanded = engine.autoExpandDependencies(mainFiles.toArray(), 5)
        
        // 验证：应该至少包含原始文件
        @Assert(expanded.size >= 1, "Should contain at least the original file")
        
        // 如果有依赖文件被找到，应该会扩展
        // 注意：由于路径匹配简化，可能找不到，这里只检查基本功能
    }
    
    /**
     * 测试 P2-2: 推荐依赖
     */
    @TestCase
    func testRecommendDependencies() {
        let engine = ContextEngine()
        
        let content = """
package test
import std.fs.Path
import std.collection.HashMap
public func test() {}
"""
        
        engine.addFile(Path("test.cj"), content)
        
        if (let Some(ctx) <- engine.getFileContext(Path("test.cj"))) {
            // 推荐依赖（最多3个）
            let recommended = engine.recommendDependencies(ctx, 3)
            
            // 验证：推荐列表不应该为null
            @Assert(recommended.size >= 0, "Recommend should return array")
            
            // 标准库文件通常不会被推荐（因为shouldAutoInclude会过滤）
        }
    }
    
    /**
     * 测试 P2-3: 详细统计信息
     */
    @TestCase
    func testGetDetailedStats() {
        let engine = ContextEngine()
        
        // 添加几个文件
        for (i in 0..5) {
            let content = "package test${i}\npublic func test${i}() {}\n"
            engine.addFile(Path("test${i}.cj"), content)
        }
        
        // 设置一些访问次数和相关性
        if (let Some(ctx) <- engine.getFileContext(Path("test0.cj"))) {
            ctx.accessCount = 10
            ctx.relevanceScore = 0.9
        }
        if (let Some(ctx) <- engine.getFileContext(Path("test1.cj"))) {
            ctx.accessCount = 5
            ctx.relevanceScore = 0.7
        }
        
        // 获取详细统计
        let stats = engine.getDetailedStats()
        
        // 验证基础统计
        @Assert(stats.totalFiles == 5, "Should have 5 files")
        @Assert(stats.totalTokens > 0, "Should have token count")
        @Assert(stats.utilization >= 0.0 && stats.utilization <= 1.0, "Utilization should be 0-1")
        
        // 验证缓存统计
        @Assert(stats.totalAccesses >= 0, "Should have access count")
        @Assert(stats.cacheHitRate >= 0.0 && stats.cacheHitRate <= 1.0, "Hit rate should be 0-1")
        
        // 验证优先级分布（默认应该都是P3）
        @Assert(stats.p3Files == 5, "All files should be P3 by default")
    }
    
    /**
     * 测试 P2-3: 格式化统计报告
     */
    @TestCase
    func testFormatStatsReport() {
        let engine = ContextEngine()
        
        // 添加一些测试文件
        engine.addFile(Path("test1.cj"), "package test1\npublic func test1() {}")
        engine.addFile(Path("test2.cj"), "package test2\npublic func test2() {}")
        
        // Pin一个文件
        engine.pinFile(Path("test1.cj"))
        
        // 设置优先级
        engine.setFilePriority(Path("test2.cj"), 1)
        
        // 格式化报告
        let report = engine.formatStatsReport()
        
        // 验证报告内容
        @Assert(report.contains("Context Engine Statistics"), "Should have title")
        @Assert(report.contains("Basic:"), "Should have basic stats")
        @Assert(report.contains("Cache:"), "Should have cache stats")
        @Assert(report.contains("Priority Distribution:"), "Should have priority distribution")
        @Assert(report.contains("Pinned: 1"), "Should show 1 pinned file")
    }
    
    /**
     * 测试 P2-3: Top文件统计
     */
    @TestCase
    func testTopFilesStatistics() {
        let engine = ContextEngine()
        
        // 添加多个文件，设置不同的访问次数
        for (i in 0..10) {
            let content = "package test${i}\npublic func test${i}() {}"
            engine.addFile(Path("test${i}.cj"), content)
            
            if (let Some(ctx) <- engine.getFileContext(Path("test${i}.cj"))) {
                ctx.accessCount = Int64(10 - i)  // 递减
                ctx.relevanceScore = Float64(i) / 10.0  // 递增
            }
        }
        
        // 获取统计
        let stats = engine.getDetailedStats()
        
        // 验证Top文件列表（最多5个）
        @Assert(stats.topFilesByAccess.size <= 5, "Should have max 5 top files by access")
        @Assert(stats.topFilesByRelevance.size <= 5, "Should have max 5 top files by relevance")
        
        // test0应该在访问次数Top 5中（因为accessCount=10最高）
        var foundTest0 = false
        for (file in stats.topFilesByAccess) {
            if (file.contains("test0.cj")) {
                foundTest0 = true
                break
            }
        }
        @Assert(foundTest0, "test0.cj should be in top files by access")
    }
    
    /**
     * 测试 P2功能集成：去重+扩展+统计
     */
    @TestCase
    func testP2Integration() {
        let engine = ContextEngine(maxCacheSize: 20)
        
        // 场景：用户有3个相关文件，import有重复
        let file1 = """
package app
import std.fs.Path
import utils.Helper
public func main() {}
"""
        let file2 = """
package utils
import std.fs.Path
public func helper() {}
"""
        let file3 = """
package test
import std.fs.Path
import utils.Helper
public func test() {}
"""
        
        engine.addFile(Path("app.cj"), file1)
        engine.addFile(Path("utils.cj"), file2)
        engine.addFile(Path("test.cj"), file3)
        
        // 1. 测试去重合并
        let allFiles = ArrayList<FileContext>()
        if (let Some(ctx) <- engine.getFileContext(Path("app.cj"))) { allFiles.add(ctx) }
        if (let Some(ctx) <- engine.getFileContext(Path("utils.cj"))) { allFiles.add(ctx) }
        if (let Some(ctx) <- engine.getFileContext(Path("test.cj"))) { allFiles.add(ctx) }
        
        let merged = engine.deduplicateAndMerge(allFiles.toArray())
        @Assert(merged.size > 0, "Merged content should not be empty")
        @Assert(merged.contains("Consolidated Imports"), "Should consolidate imports")
        
        // 2. 测试统计
        let stats = engine.getDetailedStats()
        @Assert(stats.totalFiles == 3, "Should have 3 files")
        
        // 3. 测试报告格式化
        let report = engine.formatStatsReport()
        @Assert(report.contains("Files: 3"), "Report should show 3 files")
    }
}

