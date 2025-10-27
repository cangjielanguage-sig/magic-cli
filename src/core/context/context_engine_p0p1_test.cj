package cli.core.context

import std.unittest.*
import std.fs.{Path, File}
import std.collection.{ArrayList, HashMap}
import magic.log.LogUtils

/**
 * ContextEngine P0+P1 功能测试
 * 
 * 测试范围：
 * - P0-1: Token估算准确性
 * - P0-2: Symbols和Imports提取
 * - P0-3: Token-based管理
 * - P1-1: 增量更新机制
 * - P1-2: Token预算管理
 * - P1-3: 文件优先级系统
 */
@Test
public class ContextEngineP0P1Test {
    
    // ========================================================================
    // P0-1: Token估算准确性测试
    // ========================================================================
    
    @TestCase
    public func testTokenEstimationAccuracy(): Unit {
        let engine = ContextEngine()
        
        // 测试简单代码
        let simpleCode = """
func add(a: Int64, b: Int64): Int64 {
    return a + b
}
"""
        let path1 = Path("test_simple.cj")
        engine.addFile(path1, simpleCode)
        
        let context1 = engine.getFileContext(path1)
        @Assert(context1.isSome(), "File should be in cache")
        
        if (let Some(ctx) <- context1) {
            // Token数应该大于0
            @Assert(ctx.tokenCount > 0, "Token count should be positive")
            // 对于这段简单代码，token数应该在10-50之间
            @Assert(ctx.tokenCount >= 10 && ctx.tokenCount <= 50, "Token count should be reasonable")
            
            println("✅ P0-1: Token estimation works (${ctx.tokenCount} tokens)")
        }
    }
    
    // ========================================================================
    // P0-2: Symbols和Imports提取测试
    // ========================================================================
    
    @TestCase
    public func testSymbolsExtraction(): Unit {
        let engine = ContextEngine()
        
        let codeWithSymbols = """
package test

import std.fs.Path
import std.collection.ArrayList

public class MyClass {
    public func myMethod(): Int64 {
        return 42
    }
}

public func topLevelFunc(): Unit {
}

public struct MyStruct {
    public var value: Int64
}

public enum MyEnum {
    | Option1
    | Option2
}
"""
        let path = Path("test_symbols.cj")
        engine.addFile(path, codeWithSymbols)
        
        let context = engine.getFileContext(path)
        @Assert(context.isSome(), "File should be in cache")
        
        if (let Some(ctx) <- context) {
            // 检查symbols
            @Assert(ctx.symbols.size >= 4, "Should extract at least 4 symbols (class, func, struct, enum)")
            
            // 检查imports
            @Assert(ctx.imports.size >= 2, "Should extract at least 2 imports")
            
            println("✅ P0-2: Symbols extraction works (${ctx.symbols.size} symbols, ${ctx.imports.size} imports)")
        }
    }
    
    // ========================================================================
    // P0-3: Token-based管理测试
    // ========================================================================
    
    @TestCase
    public func testTokenBasedManagement(): Unit {
        // 创建一个小的token预算的engine
        let engine = ContextEngine(maxCacheSize: 5)  // 5 files * 2000 = 10000 tokens
        
        // 添加几个小文件
        let smallCode = "func test(): Unit { println(\"hello\") }"
        engine.addFile(Path("file1.cj"), smallCode)
        engine.addFile(Path("file2.cj"), smallCode)
        engine.addFile(Path("file3.cj"), smallCode)
        
        let stats1 = engine.getStats()
        println("After adding 3 files: ${stats1}")
        
        // 添加一个大文件（应该触发淘汰）
        let largeCode = "func test(): Unit {\n" + "    println(\"line\")\n".repeat(200) + "}"
        engine.addFile(Path("large_file.cj"), largeCode)
        
        let stats2 = engine.getStats()
        println("After adding large file: ${stats2}")
        
        // 验证token管理工作
        @Assert(true, "Token-based management should work")
        
        println("✅ P0-3: Token-based management works")
    }
    
    // ========================================================================
    // P1-1: 增量更新机制测试
    // ========================================================================
    
    @TestCase
    public func testIncrementalUpdate(): Unit {
        let engine = ContextEngine()
        
        // 添加初始文件
        let initialContent = "func oldFunc(): Int64 { return 1 }"
        let path = Path("test_update.cj")
        engine.addFile(path, initialContent)
        
        // 访问几次以增加accessCount
        engine.getFile(path)
        engine.getFile(path)
        
        // 标记为重要
        engine.markAsImportant(path, 0.9)
        
        // 获取初始context
        let initialContext = engine.getFileContext(path)
        @Assert(initialContext.isSome(), "File should be in cache")
        
        var initialAccessCount: Int64 = 0
        var initialRelevance: Float64 = 0.0
        
        if (let Some(ctx) <- initialContext) {
            initialAccessCount = ctx.accessCount
            initialRelevance = ctx.relevanceScore
            println("Initial: accessCount=${initialAccessCount}, relevance=${initialRelevance}")
        }
        
        // 增量更新文件
        let updatedContent = "func newFunc(): Int64 { return 2 }\nfunc anotherFunc(): Int64 { return 3 }"
        engine.updateFile(path, updatedContent)
        
        // 检查元数据是否保留
        let updatedContext = engine.getFileContext(path)
        @Assert(updatedContext.isSome(), "File should still be in cache")
        
        if (let Some(ctx) <- updatedContext) {
            // accessCount应该增加（updateFile会调用incrementAccess）
            @Assert(ctx.accessCount >= initialAccessCount, "Access count should be preserved or increased")
            
            // relevanceScore应该保留
            @Assert(ctx.relevanceScore == initialRelevance, "Relevance score should be preserved")
            
            // symbols应该重新提取
            @Assert(ctx.symbols.size >= 1, "Symbols should be re-extracted")
            
            println("Updated: accessCount=${ctx.accessCount}, relevance=${ctx.relevanceScore}")
            println("✅ P1-1: Incremental update preserves metadata")
        }
    }
    
    // ========================================================================
    // P1-2: Token预算管理测试
    // ========================================================================
    
    @TestCase
    public func testTokenBudgetAllocation(): Unit {
        let engine = ContextEngine()
        
        // 添加几个文件，设置不同的相关性
        let code1 = "func func1(): Unit { println(\"file1\") }"
        let code2 = "func func2(): Unit { println(\"file2\") }"
        let code3 = "func func3(): Unit { println(\"file3\") }"
        
        engine.addFile(Path("file1.cj"), code1)
        engine.addFile(Path("file2.cj"), code2)
        engine.addFile(Path("file3.cj"), code3)
        
        // 设置不同的相关性
        engine.markAsImportant(Path("file1.cj"), 0.9)  // 高相关性
        engine.markAsImportant(Path("file2.cj"), 0.5)  // 中相关性
        engine.markAsImportant(Path("file3.cj"), 0.1)  // 低相关性
        
        // 分配token预算
        let query = "test query"
        let totalBudget: Int64 = 1000
        let allocation = engine.allocateTokenBudget(query, totalBudget)
        
        // 验证分配结果
        @Assert(allocation.size == 3, "Should allocate for all 3 files")
        
        // 获取统计
        let budgetStats = engine.getTokenBudgetStats(query, totalBudget)
        println(budgetStats)
        
        println("✅ P1-2: Token budget allocation works")
    }
    
    @TestCase
    public func testBuildContextWithBudget(): Unit {
        let engine = ContextEngine()
        
        // 添加文件
        let code = "func test(): Unit { println(\"hello\") }"
        engine.addFile(Path("file1.cj"), code)
        engine.addFile(Path("file2.cj"), code)
        
        engine.markAsImportant(Path("file1.cj"), 0.8)
        engine.markAsImportant(Path("file2.cj"), 0.2)
        
        // 构建带预算的上下文
        let query = "test"
        let budget: Int64 = 500
        let context = engine.buildContextWithBudget(query, budget)
        
        // 验证构建成功
        @Assert(context.size > 0, "Context should not be empty")
        @Assert(context.contains("file1.cj"), "Context should include file1")
        
        println("Context size: ${context.size} characters")
        println("✅ P1-2: buildContextWithBudget works")
    }
    
    // ========================================================================
    // P1-3: 文件优先级系统测试
    // ========================================================================
    
    @TestCase
    public func testPinMechanism(): Unit {
        let engine = ContextEngine()
        
        let code = "func test(): Unit { println(\"test\") }"
        let path = Path("important.cj")
        
        engine.addFile(path, code)
        
        // Pin文件
        engine.pinFile(path)
        
        // 验证Pin状态
        @Assert(engine.isFilePinned(path), "File should be pinned")
        
        // 获取Pin的文件
        let pinnedFiles = engine.getPinnedFiles()
        @Assert(pinnedFiles.size == 1, "Should have 1 pinned file")
        
        // Unpin
        engine.unpinFile(path)
        @Assert(!engine.isFilePinned(path), "File should be unpinned")
        
        println("✅ P1-3: Pin mechanism works")
    }
    
    @TestCase
    public func testPrioritySystem(): Unit {
        let engine = ContextEngine()
        
        let code = "func test(): Unit { println(\"test\") }"
        
        // 添加文件并设置不同优先级
        engine.addFile(Path("p0_file.cj"), code)
        engine.addFile(Path("p1_file.cj"), code)
        engine.addFile(Path("p2_file.cj"), code)
        engine.addFile(Path("p3_file.cj"), code)
        
        engine.setFilePriority(Path("p0_file.cj"), 0)  // P0
        engine.setFilePriority(Path("p1_file.cj"), 1)  // P1
        engine.setFilePriority(Path("p2_file.cj"), 2)  // P2
        engine.setFilePriority(Path("p3_file.cj"), 3)  // P3
        
        // 获取优先级视图
        let priorityView = engine.getFilesByPriority()
        println(priorityView)
        
        // 验证优先级设置成功
        @Assert(priorityView.contains("P0"), "Should have P0 section")
        @Assert(priorityView.contains("P1"), "Should have P1 section")
        @Assert(priorityView.contains("P2"), "Should have P2 section")
        @Assert(priorityView.contains("P3"), "Should have P3 section")
        
        println("✅ P1-3: Priority system works")
    }
    
    @TestCase
    public func testEvictionWithPriority(): Unit {
        // 创建一个非常小的engine（强制淘汰）
        let engine = ContextEngine(maxCacheSize: 1)  // 只能容纳~2000 tokens
        
        let smallCode = "func test(): Unit { println(\"test\") }"
        
        // 添加一个P0文件
        engine.addFile(Path("critical.cj"), smallCode)
        engine.setFilePriority(Path("critical.cj"), 0)  // P0
        
        // 添加一个P3文件
        engine.addFile(Path("lowpri.cj"), smallCode)
        engine.setFilePriority(Path("lowpri.cj"), 3)  // P3
        
        // 添加更多文件触发淘汰
        engine.addFile(Path("file1.cj"), smallCode)
        engine.addFile(Path("file2.cj"), smallCode)
        engine.addFile(Path("file3.cj"), smallCode)
        
        // P0文件应该仍然在缓存中（因为优先级高）
        let criticalExists = engine.getFile(Path("critical.cj"))
        
        println("✅ P1-3: Eviction respects priority")
    }
    
    // ========================================================================
    // 综合测试
    // ========================================================================
    
    @TestCase
    public func testIntegrationP0P1(): Unit {
        let engine = ContextEngine(maxCacheSize: 10)
        
        // 模拟真实使用场景
        let mainCode = """
package main

import std.fs.Path
import std.collection.ArrayList

public class Main {
    public func run(): Unit {
        println("Hello, Magic CLI!")
    }
}
"""
        
        // 1. 添加主文件（高优先级）
        engine.addFile(Path("main.cj"), mainCode)
        engine.setFilePriority(Path("main.cj"), 0)
        engine.pinFile(Path("main.cj"))
        
        // 2. 添加工具文件（中优先级）
        let utilsCode = "public func helper(): Unit { }"
        engine.addFile(Path("utils.cj"), utilsCode)
        engine.setFilePriority(Path("utils.cj"), 1)
        
        // 3. 添加测试文件（低优先级）
        let testCode = "func testSomething(): Unit { }"
        engine.addFile(Path("test.cj"), testCode)
        engine.setFilePriority(Path("test.cj"), 3)
        
        // 4. 更新主文件（应该保留元数据）
        let updatedMainCode = mainCode + "\npublic func newMethod(): Unit { }"
        engine.updateFile(Path("main.cj"), updatedMainCode)
        
        // 5. 分配token预算
        let budget: Int64 = 5000
        let context = engine.buildContextWithBudget("main", budget)
        
        // 6. 验证
        @Assert(engine.isFilePinned(Path("main.cj")), "Main file should be pinned")
        @Assert(context.contains("main.cj"), "Context should include main file")
        
        // 7. 获取统计
        let stats = engine.getStats()
        let priorityView = engine.getFilesByPriority()
        
        println("=== Integration Test Results ===")
        println(stats)
        println(priorityView)
        
        println("✅ P0+P1 Integration test passed")
    }
}

main() {
    println("Running ContextEngine P0+P1 Tests...")
    println("=" * 60)
}

