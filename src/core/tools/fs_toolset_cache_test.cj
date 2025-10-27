package cli.core.tools

import cli.core.context.{ContextEngine, FileWatcher}
import cli.core.tools.FSToolset
import std.fs.{Path, File}
import std.unittest.*
import magic.log.LogUtils

/**
 * FSToolset 缓存功能测试
 * 
 * 测试目标:
 * 1. Cache HIT/MISS 逻辑
 * 2. 缓存更新机制
 * 3. FileWatcher 集成
 */
@Test
class FSToolsetCacheTest {
    
    /**
     * 测试1: 基本缓存HIT/MISS
     */
    @TestCase
    func testBasicCacheHitMiss() {
        LogUtils.info("========== Test 1: Basic Cache HIT/MISS ==========")
        
        // 1. 创建测试环境
        let engine = ContextEngine(maxCacheSize: 10)
        let watcher = FileWatcher(engine)
        FSToolset.setContextEngine(engine)
        FSToolset.setFileWatcher(watcher)
        
        // 2. 准备测试文件
        let testPath = Path("/tmp/test_cache_basic.txt")
        let testContent = "Hello, Cache Test!"
        File.writeTo(testPath, testContent.toUtf8())
        
        // 3. 第一次读取 - 应该 Cache MISS
        LogUtils.info("First read (expect Cache MISS)...")
        let toolset = FSToolset()
        let content1 = toolset.readFile("/tmp/test_cache_basic.txt")
        @Assert.equals(content1, testContent, "First read should return correct content")
        
        // 4. 验证文件已缓存
        let cached = engine.getFileContext(testPath)
        @Assert.isTrue(cached.isSome(), "File should be cached after first read")
        
        // 5. 第二次读取 - 应该 Cache HIT
        LogUtils.info("Second read (expect Cache HIT)...")
        let content2 = toolset.readFile("/tmp/test_cache_basic.txt")
        @Assert.equals(content2, testContent, "Second read should return same content")
        
        // 6. 验证访问计数增加
        if (let Some(ctx) <- engine.getFileContext(testPath)) {
            @Assert.isTrue(ctx.accessCount >= 2, "Access count should be >= 2")
            LogUtils.info("✅ Access count: ${ctx.accessCount}")
        }
        
        // 清理
        testPath.remove()
        LogUtils.info("✅ Test 1 PASSED")
    }
    
    /**
     * 测试2: writeFile 缓存更新
     */
    @TestCase
    func testWriteFileCacheUpdate() {
        LogUtils.info("========== Test 2: writeFile Cache Update ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        FSToolset.setContextEngine(engine)
        let toolset = FSToolset()
        
        let testPath = Path("/tmp/test_cache_write.txt")
        let originalContent = "Original Content"
        let updatedContent = "Updated Content"
        
        // 1. 写入原始内容并读取（缓存）
        File.writeTo(testPath, originalContent.toUtf8())
        let read1 = toolset.readFile("/tmp/test_cache_write.txt")
        @Assert.equals(read1, originalContent, "Should read original content")
        
        // 2. 使用 writeFile 更新内容
        LogUtils.info("Writing new content via writeFile...")
        toolset.writeFile("/tmp/test_cache_write.txt", updatedContent)
        
        // 3. 验证缓存已更新
        if (let Some(ctx) <- engine.getFileContext(testPath)) {
            @Assert.equals(ctx.content, updatedContent, "Cache should contain updated content")
            LogUtils.info("✅ Cache updated successfully")
        } else {
            @Assert.fail("File should still be in cache after writeFile")
        }
        
        // 4. 读取验证（应该从缓存获取更新后的内容）
        let read2 = toolset.readFile("/tmp/test_cache_write.txt")
        @Assert.equals(read2, updatedContent, "Should read updated content from cache")
        
        // 清理
        testPath.remove()
        LogUtils.info("✅ Test 2 PASSED")
    }
    
    /**
     * 测试3: editFile 缓存更新
     */
    @TestCase
    func testEditFileCacheUpdate() {
        LogUtils.info("========== Test 3: editFile Cache Update ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        FSToolset.setContextEngine(engine)
        let toolset = FSToolset()
        
        let testPath = Path("/tmp/test_cache_edit.txt")
        let originalContent = "Line 1\nLine 2\nLine 3\n"
        let expectedContent = "Line 1\nModified Line 2\nLine 3\n"
        
        // 1. 创建测试文件并缓存
        File.writeTo(testPath, originalContent.toUtf8())
        toolset.readFile("/tmp/test_cache_edit.txt")
        
        // 2. 使用 editFile 修改内容
        LogUtils.info("Editing file via editFile...")
        toolset.editFile(
            filePath: "/tmp/test_cache_edit.txt",
            oldString: "Line 2",
            newString: "Modified Line 2"
        )
        
        // 3. 验证缓存已更新
        if (let Some(ctx) <- engine.getFileContext(testPath)) {
            @Assert.equals(ctx.content, expectedContent, "Cache should contain edited content")
            LogUtils.info("✅ Cache updated after edit")
        } else {
            @Assert.fail("File should still be in cache after editFile")
        }
        
        // 清理
        testPath.remove()
        LogUtils.info("✅ Test 3 PASSED")
    }
    
    /**
     * 测试4: 部分文件读取（startLine/endLine）不使用缓存
     */
    @TestCase
    func testPartialReadNoCache() {
        LogUtils.info("========== Test 4: Partial Read (No Cache) ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        FSToolset.setContextEngine(engine)
        let toolset = FSToolset()
        
        let testPath = Path("/tmp/test_cache_partial.txt")
        let content = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n"
        File.writeTo(testPath, content.toUtf8())
        
        // 1. 部分读取（指定行范围）
        LogUtils.info("Reading lines 1-2 (should NOT use cache)...")
        let partial = toolset.readFile(
            filePath: "/tmp/test_cache_partial.txt",
            startLine: Some(1),
            endLine: Some(2)
        )
        @Assert.equals(partial, "Line 1\nLine 2\n", "Should read partial content")
        
        // 2. 验证文件未被缓存（因为是部分读取）
        let cached = engine.getFileContext(testPath)
        @Assert.isTrue(cached.isNone(), "Partial read should NOT cache the file")
        
        // 3. 完整读取（应该缓存）
        LogUtils.info("Reading full file (should cache)...")
        let full = toolset.readFile("/tmp/test_cache_partial.txt")
        @Assert.equals(full, content, "Should read full content")
        
        // 4. 验证现在已缓存
        let cachedNow = engine.getFileContext(testPath)
        @Assert.isTrue(cachedNow.isSome(), "Full read should cache the file")
        
        // 清理
        testPath.remove()
        LogUtils.info("✅ Test 4 PASSED")
    }
    
    /**
     * 测试5: 多文件缓存
     */
    @TestCase
    func testMultipleFilesCache() {
        LogUtils.info("========== Test 5: Multiple Files Cache ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        FSToolset.setContextEngine(engine)
        let toolset = FSToolset()
        
        // 1. 创建多个测试文件
        let files = [
            ("/tmp/test_cache_multi_1.txt", "Content 1"),
            ("/tmp/test_cache_multi_2.txt", "Content 2"),
            ("/tmp/test_cache_multi_3.txt", "Content 3")
        ]
        
        for ((path, content) in files) {
            File.writeTo(Path(path), content.toUtf8())
        }
        
        // 2. 读取所有文件（应该全部缓存）
        LogUtils.info("Reading ${files.size} files...")
        for ((path, expectedContent) in files) {
            let content = toolset.readFile(path)
            @Assert.equals(content, expectedContent, "Should read correct content for ${path}")
        }
        
        // 3. 验证所有文件都已缓存
        let stats = engine.getStats()
        LogUtils.info("Cache stats: ${stats}")
        @Assert.isTrue(engine.getFileContext(Path("/tmp/test_cache_multi_1.txt")).isSome(), "File 1 should be cached")
        @Assert.isTrue(engine.getFileContext(Path("/tmp/test_cache_multi_2.txt")).isSome(), "File 2 should be cached")
        @Assert.isTrue(engine.getFileContext(Path("/tmp/test_cache_multi_3.txt")).isSome(), "File 3 should be cached")
        
        // 4. 再次读取（应该全部 Cache HIT）
        LogUtils.info("Reading again (expect all Cache HITs)...")
        for ((path, expectedContent) in files) {
            let content = toolset.readFile(path)
            @Assert.equals(content, expectedContent, "Should read from cache for ${path}")
        }
        
        // 清理
        for ((path, _) in files) {
            Path(path).remove()
        }
        LogUtils.info("✅ Test 5 PASSED")
    }
    
    /**
     * 测试6: FileWatcher 集成
     */
    @TestCase
    func testFileWatcherIntegration() {
        LogUtils.info("========== Test 6: FileWatcher Integration ==========")
        
        let engine = ContextEngine(maxCacheSize: 10)
        let watcher = FileWatcher(engine)
        FSToolset.setContextEngine(engine)
        FSToolset.setFileWatcher(watcher)
        let toolset = FSToolset()
        
        let testPath = Path("/tmp/test_cache_watcher.txt")
        let content1 = "Version 1"
        let content2 = "Version 2"
        
        // 1. 创建文件并读取（缓存 + 监听）
        File.writeTo(testPath, content1.toUtf8())
        toolset.readFile("/tmp/test_cache_watcher.txt")
        
        // 2. 验证文件被监听
        @Assert.isTrue(watcher.isWatching(testPath), "File should be watched")
        LogUtils.info("✅ File is being watched")
        
        // 3. 模拟文件修改（直接写入文件系统）
        LogUtils.info("Simulating file modification...")
        File.writeTo(testPath, content2.toUtf8())
        
        // 4. 触发 FileWatcher 检查
        watcher.checkChanges()
        watcher.syncContext()
        
        // 5. 验证缓存已更新（通过 FileWatcher）
        if (let Some(ctx) <- engine.getFileContext(testPath)) {
            @Assert.equals(ctx.content, content2, "Cache should be updated by FileWatcher")
            LogUtils.info("✅ FileWatcher successfully updated cache")
        } else {
            @Assert.fail("File should still be in cache after FileWatcher sync")
        }
        
        // 清理
        testPath.remove()
        LogUtils.info("✅ Test 6 PASSED")
    }
}

