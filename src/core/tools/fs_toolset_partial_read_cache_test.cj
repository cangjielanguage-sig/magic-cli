package cli.core.tools

import std.unittest.*
import std.fs.*
import std.collection.*
import cli.core.context.{ContextEngine, FileContext}
import magic.log.LogUtils

/**
 * ✨ P0-2改进: 部分读取缓存功能测试
 * 
 * 验证以下功能：
 * 1. 部分读取时能命中缓存
 * 2. 部分读取后自动缓存完整文件
 * 3. 多次部分读取同一文件的性能
 */
@Test
class FSToolsetPartialReadCacheTest {
    
    /**
     * 测试1: 验证extractLinesFromCache基本功能
     */
    @TestCase
    public func testExtractLinesFromCache() {
        let content = "line1\nline2\nline3\nline4\nline5"
        
        // 测试提取前3行
        let result1 = extractLinesFromCache(content, 1, Some(3))
        @Assert(result1 == "line1\nline2\nline3", "Should extract first 3 lines")
        
        // 测试提取中间行
        let result2 = extractLinesFromCache(content, 2, Some(4))
        @Assert(result2 == "line2\nline3\nline4", "Should extract middle lines")
        
        // 测试提取到结尾
        let result3 = extractLinesFromCache(content, 3, None)
        @Assert(result3 == "line3\nline4\nline5", "Should extract to end")
        
        LogUtils.info("[Test1] ✅ extractLinesFromCache basic functionality works")
    }
    
    /**
     * 测试2: 验证边界条件
     */
    @TestCase
    public func testExtractLinesBoundary() {
        let content = "line1\nline2\nline3"
        
        // 测试超出范围
        let result1 = extractLinesFromCache(content, 10, Some(20))
        @Assert(result1 == "", "Should return empty for out of range")
        
        // 测试单行
        let result2 = extractLinesFromCache(content, 2, Some(2))
        @Assert(result2 == "line2", "Should extract single line")
        
        // 测试完整内容
        let result3 = extractLinesFromCache(content, 1, None)
        @Assert(result3 == content, "Should extract all lines")
        
        LogUtils.info("[Test2] ✅ Boundary conditions handled correctly")
    }
    
    /**
     * 测试3: 模拟Agent部分读取场景
     */
    @TestCase
    public func testAgentPartialReadPattern() {
        // 创建测试文件
        let testDir = Path("./test_partial_read_cache")
        if (!testDir.exists()) {
            Directory.create(testDir.toString(), recursive: true)
        }
        
        let testFile = testDir / "test_agent.cj"
        var testContent = ""
        for (i in 0..100) {
            testContent += "Line ${i + 1}: This is test content\n"
        }
        File.writeTo(testFile.toString(), testContent.toArray())
        
        // 初始化ContextEngine
        let engine = ContextEngine()
        FSToolset.setContextEngine(engine)
        
        // 模拟Agent的典型读取模式
        // 第1次：读取前50行（应该Cache MISS，然后缓存完整文件）
        let fstoolset = FSToolset()
        let result1 = fstoolset.readFile(testFile.toString(), Some(1), Some(50))
        @Assert(result1.contains("Line 1"), "Should contain first line")
        @Assert(result1.contains("Line 50"), "Should contain line 50")
        
        // 验证完整文件已被缓存
        let cached = engine.getFileContext(testFile)
        @Assert(cached.isSome(), "Full file should be cached after partial read")
        
        // 第2次：读取51-100行（应该Cache HIT）
        let result2 = fstoolset.readFile(testFile.toString(), Some(51), Some(100))
        @Assert(result2.contains("Line 51"), "Should contain line 51")
        @Assert(result2.contains("Line 100"), "Should contain line 100")
        
        // 清理
        remove(testDir.toString(), recursive: true)
        
        LogUtils.info("[Test3] ✅ Agent partial read pattern works correctly")
    }
    
    /**
     * 测试4: 验证缓存命中性能
     */
    @TestCase
    public func testCacheHitPerformance() {
        // 创建测试文件
        let testDir = Path("./test_cache_performance")
        if (!testDir.exists()) {
            Directory.create(testDir.toString(), recursive: true)
        }
        
        let testFile = testDir / "test_perf.cj"
        var largeContent = ""
        for (i in 0..1000) {
            largeContent += "Line ${i + 1}: This is a longer test content for performance testing\n"
        }
        File.writeTo(testFile.toString(), largeContent.toArray())
        
        // 初始化
        let engine = ContextEngine()
        FSToolset.setContextEngine(engine)
        let fstoolset = FSToolset()
        
        // 首次读取（Cache MISS，应该缓存完整文件）
        let _ = fstoolset.readFile(testFile.toString(), Some(1), Some(50))
        
        // 验证缓存存在
        let cached = engine.getFileContext(testFile)
        @Assert(cached.isSome(), "Should have cached content")
        
        if (let Some(ctx) <- cached) {
            @Assert(ctx.lineCount > 900, "Should cache full file (1000+ lines)")
            LogUtils.info("[Test4] ✅ Cached ${ctx.lineCount} lines from partial read")
        }
        
        // 多次部分读取（都应该Cache HIT）
        for (i in 0..5) {
            let start = Int64(i * 100 + 1)
            let end = Int64((i + 1) * 100)
            let result = fstoolset.readFile(testFile.toString(), Some(start), Some(end))
            @Assert(result.contains("Line ${start}"), "Should contain correct range")
        }
        
        // 清理
        remove(testDir.toString(), recursive: true)
        
        LogUtils.info("[Test4] ✅ Cache hit performance validated")
    }
    
    /**
     * 测试5: 验证完整文件读取仍然正常
     */
    @TestCase
    public func testFullFileReadStillWorks() {
        // 创建测试文件
        let testDir = Path("./test_full_read")
        if (!testDir.exists()) {
            Directory.create(testDir.toString(), recursive: true)
        }
        
        let testFile = testDir / "test_full.cj"
        let testContent = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"
        File.writeTo(testFile.toString(), testContent.toArray())
        
        // 初始化
        let engine = ContextEngine()
        FSToolset.setContextEngine(engine)
        let fstoolset = FSToolset()
        
        // 完整文件读取（不带startLine/endLine）
        let result = fstoolset.readFile(testFile.toString(), None, None)
        @Assert(result.contains("Line 1"), "Should contain line 1")
        @Assert(result.contains("Line 5"), "Should contain line 5")
        
        // 验证被缓存
        let cached = engine.getFileContext(testFile)
        @Assert(cached.isSome(), "Full read should cache")
        
        // 清理
        remove(testDir.toString(), recursive: true)
        
        LogUtils.info("[Test5] ✅ Full file read still works correctly")
    }
    
    /**
     * 测试6: 验证缓存更新后部分读取
     */
    @TestCase
    public func testCacheUpdateThenPartialRead() {
        // 创建测试文件
        let testDir = Path("./test_cache_update")
        if (!testDir.exists()) {
            Directory.create(testDir.toString(), recursive: true)
        }
        
        let testFile = testDir / "test_update.cj"
        let initialContent = "Old Line 1\nOld Line 2\nOld Line 3"
        File.writeTo(testFile.toString(), initialContent.toArray())
        
        // 初始化
        let engine = ContextEngine()
        FSToolset.setContextEngine(engine)
        let fstoolset = FSToolset()
        
        // 首次读取
        let result1 = fstoolset.readFile(testFile.toString(), Some(1), Some(2))
        @Assert(result1.contains("Old Line 1"), "Should contain old content")
        
        // 修改文件内容（模拟writeFile）
        let newContent = "New Line 1\nNew Line 2\nNew Line 3"
        File.writeTo(testFile.toString(), newContent.toArray())
        engine.updateFile(testFile, newContent)
        
        // 再次部分读取（应该从更新后的缓存读取）
        let result2 = fstoolset.readFile(testFile.toString(), Some(1), Some(2))
        @Assert(result2.contains("New Line 1"), "Should contain new content from cache")
        
        // 清理
        remove(testDir.toString(), recursive: true)
        
        LogUtils.info("[Test6] ✅ Cache update + partial read works correctly")
    }
}

