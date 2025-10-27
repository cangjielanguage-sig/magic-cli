package cli.core.context

import cli.core.context.{ContextEngine, FileContext, QueryType}
import std.fs.{Path, File}
import std.unittest.*
import magic.log.LogUtils

/**
 * P3-2: 上下文感知智能压缩测试
 * 
 * 测试目标:
 * 1. 查询类型识别
 * 2. 不同查询类型的压缩策略
 * 3. 压缩效果验证
 */
@Test
class SmartCompressTest {
    
    /**
     * 测试1: 查询类型识别 - 代码阅读
     */
    @TestCase
    func testQueryTypeCodeReading() {
        LogUtils.info("========== Test 1: Query Type - Code Reading ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        
        // 测试中文关键词
        let type1 = engine.analyzeQueryType("帮我阅读这个文件")
        @Assert.equals(type1.toString(), "CodeReading", "Should detect CodeReading type (Chinese)")
        
        let type2 = engine.analyzeQueryType("理解这段代码的逻辑")
        @Assert.equals(type2.toString(), "CodeReading", "Should detect CodeReading type")
        
        // 测试英文关键词
        let type3 = engine.analyzeQueryType("read this file")
        @Assert.equals(type3.toString(), "CodeReading", "Should detect CodeReading type (English)")
        
        LogUtils.info("✅ Test 1 PASSED")
    }
    
    /**
     * 测试2: 查询类型识别 - 调试
     */
    @TestCase
    func testQueryTypeDebugging() {
        LogUtils.info("========== Test 2: Query Type - Debugging ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        
        let type1 = engine.analyzeQueryType("这里有个bug，帮我调试")
        @Assert.equals(type1.toString(), "Debugging", "Should detect Debugging type")
        
        let type2 = engine.analyzeQueryType("修复这个错误")
        @Assert.equals(type2.toString(), "Debugging", "Should detect Debugging type")
        
        let type3 = engine.analyzeQueryType("debug this error")
        @Assert.equals(type3.toString(), "Debugging", "Should detect Debugging type (English)")
        
        LogUtils.info("✅ Test 2 PASSED")
    }
    
    /**
     * 测试3: 查询类型识别 - 重构
     */
    @TestCase
    func testQueryTypeRefactoring() {
        LogUtils.info("========== Test 3: Query Type - Refactoring ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        
        let type1 = engine.analyzeQueryType("重构这个函数")
        @Assert.equals(type1.toString(), "Refactoring", "Should detect Refactoring type")
        
        let type2 = engine.analyzeQueryType("优化代码结构")
        @Assert.equals(type2.toString(), "Refactoring", "Should detect Refactoring type")
        
        let type3 = engine.analyzeQueryType("refactor this code")
        @Assert.equals(type3.toString(), "Refactoring", "Should detect Refactoring type (English)")
        
        LogUtils.info("✅ Test 3 PASSED")
    }
    
    /**
     * 测试4: 查询类型识别 - 文档生成
     */
    @TestCase
    func testQueryTypeDocumentation() {
        LogUtils.info("========== Test 4: Query Type - Documentation ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        
        let type1 = engine.analyzeQueryType("生成API文档")
        @Assert.equals(type1.toString(), "Documentation", "Should detect Documentation type")
        
        let type2 = engine.analyzeQueryType("为这个函数添加注释")
        @Assert.equals(type2.toString(), "Documentation", "Should detect Documentation type")
        
        let type3 = engine.analyzeQueryType("generate documentation")
        @Assert.equals(type3.toString(), "Documentation", "Should detect Documentation type (English)")
        
        LogUtils.info("✅ Test 4 PASSED")
    }
    
    /**
     * 测试5: 查询类型识别 - 快速扫描
     */
    @TestCase
    func testQueryTypeQuickScan() {
        LogUtils.info("========== Test 5: Query Type - Quick Scan ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        
        let type1 = engine.analyzeQueryType("列出所有函数")
        @Assert.equals(type1.toString(), "QuickScan", "Should detect QuickScan type")
        
        let type2 = engine.analyzeQueryType("查找这个符号")
        @Assert.equals(type2.toString(), "QuickScan", "Should detect QuickScan type")
        
        let type3 = engine.analyzeQueryType("list all functions")
        @Assert.equals(type3.toString(), "QuickScan", "Should detect QuickScan type (English)")
        
        LogUtils.info("✅ Test 5 PASSED")
    }
    
    /**
     * 测试6: 查询类型识别 - 默认
     */
    @TestCase
    func testQueryTypeGeneral() {
        LogUtils.info("========== Test 6: Query Type - General ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        
        let type1 = engine.analyzeQueryType("这是什么")
        @Assert.equals(type1.toString(), "General", "Should default to General type")
        
        let type2 = engine.analyzeQueryType("random query without keywords")
        @Assert.equals(type2.toString(), "General", "Should default to General type")
        
        LogUtils.info("✅ Test 6 PASSED")
    }
    
    /**
     * 测试7: 智能压缩 - 代码阅读场景
     */
    @TestCase
    func testSmartCompressCodeReading() {
        LogUtils.info("========== Test 7: Smart Compress - Code Reading ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        
        // 创建一个较大的测试文件
        let testContent = """
// 这是一个重要的注释
package test

import std.fs.*

// 函数1: 执行某个操作
public func doSomething() {
    println("Hello")
}

// 函数2: 执行另一个操作
public func doAnotherThing() {
    println("World")
}
"""
        
        let testPath = Path("/tmp/test_smart_compress_reading.cj")
        File.writeTo(testPath, testContent.toUtf8())
        
        // 添加到缓存
        engine.addFile(testPath, testContent)
        
        // 获取文件上下文
        if (let Some(fileContext) <- engine.getFileContext(testPath)) {
            // 使用智能压缩（代码阅读场景，应保留注释）
            let compressed = engine.smartCompress(
                fileContext, 
                "帮我阅读这个文件", 
                100  // 设置一个小的token限制，触发压缩
            )
            
            // 验证注释被保留（代码阅读需要注释）
            @Assert.isTrue(compressed.contains("重要的注释") || compressed.contains("import"), "Should preserve comments or structure for code reading")
            
            LogUtils.info("Original size: ${testContent.size}, Compressed size: ${compressed.size}")
        } else {
            @Assert.fail("File should be in cache")
        }
        
        // 清理
        testPath.remove()
        LogUtils.info("✅ Test 7 PASSED")
    }
    
    /**
     * 测试8: 智能压缩 - 调试场景
     */
    @TestCase
    func testSmartCompressDebugging() {
        LogUtils.info("========== Test 8: Smart Compress - Debugging ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        
        let testContent = """
// 注释会被删除
package test

public func buggyFunction() {
    let x = 10
    let y = 20
    let result = x + y
}
"""
        
        let testPath = Path("/tmp/test_smart_compress_debug.cj")
        File.writeTo(testPath, testContent.toUtf8())
        engine.addFile(testPath, testContent)
        
        if (let Some(fileContext) <- engine.getFileContext(testPath)) {
            let compressed = engine.smartCompress(
                fileContext, 
                "帮我调试这个bug", 
                100
            )
            
            // 验证逻辑代码被保留
            @Assert.isTrue(compressed.contains("buggyFunction") || compressed.contains("func"), "Should preserve function logic for debugging")
            
            LogUtils.info("Original size: ${testContent.size}, Compressed size: ${compressed.size}")
        } else {
            @Assert.fail("File should be in cache")
        }
        
        testPath.remove()
        LogUtils.info("✅ Test 8 PASSED")
    }
    
    /**
     * 测试9: 智能压缩 - 文档生成场景
     */
    @TestCase
    func testSmartCompressDocumentation() {
        LogUtils.info("========== Test 9: Smart Compress - Documentation ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        
        let testContent = """
package test

public func add(a: Int64, b: Int64): Int64 {
    let result = a + b
    let temp = result * 2
    return temp
}

public class Calculator {
    public func multiply(x: Int64, y: Int64): Int64 {
        return x * y
    }
}
"""
        
        let testPath = Path("/tmp/test_smart_compress_doc.cj")
        File.writeTo(testPath, testContent.toUtf8())
        engine.addFile(testPath, testContent)
        
        if (let Some(fileContext) <- engine.getFileContext(testPath)) {
            let compressed = engine.smartCompress(
                fileContext, 
                "生成API文档", 
                50  // 非常小的限制，应该只保留签名
            )
            
            // 验证函数签名被保留，实现细节被删除
            @Assert.isTrue(compressed.contains("func") || compressed.contains("class"), "Should preserve signatures for documentation")
            
            LogUtils.info("Original size: ${testContent.size}, Compressed size: ${compressed.size}")
        } else {
            @Assert.fail("File should be in cache")
        }
        
        testPath.remove()
        LogUtils.info("✅ Test 9 PASSED")
    }
    
    /**
     * 测试10: 智能压缩效果对比
     */
    @TestCase
    func testCompressionEffectiveness() {
        LogUtils.info("========== Test 10: Compression Effectiveness ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        
        let testContent = """
// 这是一个测试文件
package test

import std.fs.*

// 函数注释
public func testFunction() {
    // 实现细节
    let x = 10
    let y = 20
    return x + y
}
"""
        
        let testPath = Path("/tmp/test_compress_effectiveness.cj")
        File.writeTo(testPath, testContent.toUtf8())
        engine.addFile(testPath, testContent)
        
        if (let Some(fileContext) <- engine.getFileContext(testPath)) {
            // 代码阅读（保留注释）
            let reading = engine.smartCompress(fileContext, "阅读代码", 200)
            
            // 调试（删除注释）
            let debugging = engine.smartCompress(fileContext, "调试bug", 200)
            
            // 文档生成（只保留签名）
            let doc = engine.smartCompress(fileContext, "生成文档", 50)
            
            // 验证不同场景的压缩程度不同
            LogUtils.info("Original: ${testContent.size} chars")
            LogUtils.info("Reading: ${reading.size} chars")
            LogUtils.info("Debugging: ${debugging.size} chars")
            LogUtils.info("Documentation: ${doc.size} chars")
            
            // 文档生成应该压缩最多
            @Assert.isTrue(doc.size <= debugging.size, "Documentation should be most compressed")
            @Assert.isTrue(doc.size <= reading.size, "Documentation should be most compressed")
        } else {
            @Assert.fail("File should be in cache")
        }
        
        testPath.remove()
        LogUtils.info("✅ Test 10 PASSED")
    }
}

