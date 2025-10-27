package cli.core.context

import std.fs.{Path}
import std.unittest.*
import std.unittest.testmacro.*

/**
 * ContextEngine v2.0 增强功能测试
 * 测试新增的相关性评分、智能压缩、优化的淘汰策略
 */
@Test
class ContextEngineV2Test {
    
    @TestCase
    func testFileContextMetadata(): Unit {
    // 测试FileContext的元数据字段初始化
    let path = Path("/test/file.cj")
    let content = "package test\n\nfunc hello() {\n    println(\"hello\")\n}"
    let context = FileContext(path, content)
    
    // 验证元数据初始化
    @Assert(context.relevanceScore == 0.0, "初始相关性分数应为0")
    @Assert(context.tokenCount > 0, "token计数应大于0")
    @Assert(context.lineCount > 0, "行数应大于0")
    @Assert(context.accessCount == 0, "初始访问次数应为0")
    @Assert(!context.isCompressed, "初始应未压缩")
    @Assert(context.originalSize > 0, "原始大小应大于0")
}

    @TestCase
    func testRelevanceScoring(): Unit {
    // 测试相关性评分系统
    let engine = ContextEngine(maxCacheSize: 10)
    
    // 添加包含关键词的文件
    let path1 = Path("/test/file1.cj")
    let content1 = "func calculateSum(a: Int64, b: Int64): Int64 { return a + b }"
    engine.addFile(path1, content1)
    
    // 添加不相关的文件
    let path2 = Path("/test/file2.cj")
    let content2 = "package test\nimport std.fs.Path"
    engine.addFile(path2, content2)
    
    // 使用查询测试相关性
    let ranked = engine.rankFilesByRelevance("calculate sum")
    
    @Assert(ranked.size == 2, "应该返回2个文件")
    // file1应该比file2相关性更高（因为包含关键词）
    @Assert(ranked[0].path.toString() == path1.toString(), "file1应该排在前面")
}

    @TestCase
    func testGetTopRelevantFiles(): Unit {
    // 测试获取最相关的N个文件
    let engine = ContextEngine(maxCacheSize: 10)
    
    // 添加多个文件
    for (i in 0..5) {
        let path = Path("/test/file${i}.cj")
        let content = "func test${i}() { println(\"test\") }"
        engine.addFile(path, content)
    }
    
    // 获取前3个最相关的
    let top3 = engine.getTopRelevantFiles("test", 3)
    @Assert(top3.size == 3, "应该返回3个文件")
}

    @TestCase
    func testCompressionLevel1(): Unit {
    // 测试轻度压缩（删除空行）
    let engine = ContextEngine(maxCacheSize: 10)
    let path = Path("/test/compress.cj")
    let content = """
package test


func hello() {
    println("hello")
}

"""
    engine.addFile(path, content)
    
    if (let Some(ctx) <- engine.getFileContext(path)) {
        let compressed = engine.compressFile(ctx, 1)
        
        // 压缩后不应包含空行（多个连续换行）
        @Assert(!compressed.contains("\n\n\n"), "压缩后不应有多个连续换行")
        // 应该保留代码内容
        @Assert(compressed.contains("hello"), "应该保留函数名")
    } else {
        @Assert(false, "应该能获取到文件上下文")
    }
}

    @TestCase
    func testCompressionLevel2(): Unit {
    // 测试中度压缩（删除注释）
    let engine = ContextEngine(maxCacheSize: 10)
    let path = Path("/test/compress2.cj")
    let content = """
package test
// This is a comment
func hello() {
    // Another comment
    println("hello")
}
"""
    engine.addFile(path, content)
    
    if (let Some(ctx) <- engine.getFileContext(path)) {
        let compressed = engine.compressFile(ctx, 2)
        
        // 压缩后不应包含注释
        @Assert(!compressed.contains("// This is a comment"), "应该删除注释")
        @Assert(compressed.contains("hello"), "应该保留代码")
    } else {
        @Assert(false, "应该能获取到文件上下文")
    }
}

    @TestCase
    func testCompressionLevel3(): Unit {
    // 测试重度压缩（只保留声明）
    let engine = ContextEngine(maxCacheSize: 10)
    let path = Path("/test/compress3.cj")
    let content = """
package test
import std.fs.Path
public class MyClass {
    public func myMethod() {
        let x = 1
        let y = 2
        return x + y
    }
}
"""
    engine.addFile(path, content)
    
    if (let Some(ctx) <- engine.getFileContext(path)) {
        let compressed = engine.compressFile(ctx, 3)
        
        // 应该保留package和import
        @Assert(compressed.contains("package test"), "应该保留package声明")
        @Assert(compressed.contains("import"), "应该保留import声明")
        @Assert(compressed.contains("public class MyClass"), "应该保留类声明")
        @Assert(compressed.contains("public func myMethod"), "应该保留函数声明")
        // 不应该包含实现细节
        @Assert(!compressed.contains("let x = 1"), "不应该包含函数体实现")
    } else {
        @Assert(false, "应该能获取到文件上下文")
    }
}

    @TestCase
    func testAutoCompress(): Unit {
    // 测试自动压缩
    let engine = ContextEngine(maxCacheSize: 10)
    let path = Path("/test/auto.cj")
    
    // 创建一个较大的文件
    var largeContent = "package test\n"
    for (i in 0..100) {
        largeContent += "func test${i}() { println(\"test\") }\n"
    }
    
    engine.addFile(path, largeContent)
    
    if (let Some(ctx) <- engine.getFileContext(path)) {
        // 设置一个较小的token限制
        let compressed = engine.autoCompress(ctx, 50)
        
        // 压缩后应该更小
        @Assert(compressed.size < largeContent.size, "压缩后应该更小")
        @Assert(compressed.size > 0, "压缩后不应为空")
    } else {
        @Assert(false, "应该能获取到文件上下文")
    }
}

    @TestCase
    func testImprovedEviction(): Unit {
    // 测试改进的淘汰策略
    let engine = ContextEngine(maxCacheSize: 3)
    
    // 添加3个文件
    let path1 = Path("/test/file1.cj")
    engine.addFile(path1, "content 1")
    
    let path2 = Path("/test/file2.cj")
    engine.addFile(path2, "content 2")
    
    let path3 = Path("/test/file3.cj")
    engine.addFile(path3, "content 3")
    
    @Assert(engine.size() == 3, "缓存应该有3个文件")
    
    // 标记file1为重要文件
    engine.markAsImportant(path1, 0.9)
    
    // 多次访问file2
    for (_ in 0..5) {
        let _ = engine.getFile(path2)
    }
    
    // 添加第4个文件，触发淘汰
    let path4 = Path("/test/file4.cj")
    engine.addFile(path4, "content 4")
    
    @Assert(engine.size() == 3, "缓存应该保持在3个文件")
    
    // file3应该被淘汰（最低分数：没被标记重要，也没被频繁访问）
    @Assert(!engine.contains(path3), "file3应该被淘汰")
    
    // file1和file2应该保留
    @Assert(engine.contains(path1), "file1应该保留（高重要性）")
    @Assert(engine.contains(path2), "file2应该保留（高访问频率）")
}

    @TestCase
    func testMarkAsImportant(): Unit {
    // 测试标记重要文件
    let engine = ContextEngine(maxCacheSize: 10)
    let path = Path("/test/important.cj")
    engine.addFile(path, "important content")
    
    engine.markAsImportant(path, 0.95)
    
    if (let Some(ctx) <- engine.getFileContext(path)) {
        @Assert(ctx.relevanceScore == 0.95, "相关性分数应该被更新为0.95")
    } else {
        @Assert(false, "应该能获取到文件上下文")
    }
}

    @TestCase
    func testIncrementAccess(): Unit {
    // 测试访问计数
    let path = Path("/test/file.cj")
    let context = FileContext(path, "test content")
    
    @Assert(context.accessCount == 0, "初始访问次数应为0")
    
    context.incrementAccess()
    @Assert(context.accessCount == 1, "访问次数应为1")
    
    context.incrementAccess()
    @Assert(context.accessCount == 2, "访问次数应为2")
}

    @TestCase
    func testUpdateRelevance(): Unit {
        // 测试更新相关性分数
        let path = Path("/test/file.cj")
        let context = FileContext(path, "test content")
        
        @Assert(context.relevanceScore == 0.0, "初始相关性应为0")
        
        context.updateRelevance(0.75)
        @Assert(context.relevanceScore == 0.75, "相关性应为0.75")
    }
}

