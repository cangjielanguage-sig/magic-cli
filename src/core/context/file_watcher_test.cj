package cli.core.context

import std.unittest.*
import std.unittest.testmacro.*
import std.fs.{Path, File}
import cli.core.config.CliConfig

@Test
class FileWatcherTest {
    
    @TestCase
    func testTrackFile() {
        let engine = ContextEngine(maxCacheSize: 10)
        let watcher = FileWatcher(engine)
        let testPath = CliConfig.cwd.join("test_watch.txt")
        let testContent = "Initial content\n"
        
        try {
            // 创建测试文件
            File.writeTo(testPath, testContent.toArray())
            engine.addFile(testPath, testContent)
            
            // 跟踪文件
            watcher.track(testPath)
            
            @Assert(watcher.getTrackedCount() == 1, "Should track one file")
            
            // 检查变更（应该没有）
            let changes = watcher.checkChanges()
            @Assert(changes.size == 0, "Should have no changes initially")
            
        } finally {
            try {
                std.fs.remove(testPath)
            } catch (_: Exception) {
                ()
            }
        }
    }
    
    @TestCase
    func testDetectModification() {
        let engine = ContextEngine(maxCacheSize: 10)
        let watcher = FileWatcher(engine)
        let testPath = CliConfig.cwd.join("test_modify.txt")
        let initialContent = "Initial content\n"
        let modifiedContent = "Modified content\n"
        
        try {
            // 创建并跟踪文件
            File.writeTo(testPath, initialContent.toArray())
            engine.addFile(testPath, initialContent)
            watcher.track(testPath)
            
            // 修改文件
            File.writeTo(testPath, modifiedContent.toArray())
            
            // 检查变更
            let changes = watcher.checkChanges()
            @Assert(changes.size == 1, "Should detect one change")
            
            if (changes.size > 0) {
                match (changes[0].changeType) {
                    case ChangeType.Modified => ()
                    case _ => @Assert(false, "Change type should be Modified")
                }
            }
            
        } finally {
            try {
                std.fs.remove(testPath)
            } catch (_: Exception) {
                ()
            }
        }
    }
    
    @TestCase
    func testDetectDeletion() {
        let engine = ContextEngine(maxCacheSize: 10)
        let watcher = FileWatcher(engine)
        let testPath = CliConfig.cwd.join("test_delete.txt")
        let testContent = "Content\n"
        
        try {
            // 创建并跟踪文件
            File.writeTo(testPath, testContent.toArray())
            engine.addFile(testPath, testContent)
            watcher.track(testPath)
            
            // 删除文件
            std.fs.remove(testPath)
            
            // 检查变更
            let changes = watcher.checkChanges()
            @Assert(changes.size == 1, "Should detect deletion")
            
            if (changes.size > 0) {
                match (changes[0].changeType) {
                    case ChangeType.Deleted => ()
                    case _ => @Assert(false, "Change type should be Deleted")
                }
            }
            
        } catch (_: Exception) {
            // File already deleted, that's fine
            ()
        }
    }
    
    @TestCase
    func testSyncContext() {
        let engine = ContextEngine(maxCacheSize: 10)
        let watcher = FileWatcher(engine)
        let testPath = CliConfig.cwd.join("test_sync.txt")
        let initialContent = "Initial\n"
        let modifiedContent = "Modified\n"
        
        try {
            // 创建并跟踪文件
            File.writeTo(testPath, initialContent.toArray())
            engine.addFile(testPath, initialContent)
            watcher.track(testPath)
            
            // 修改文件
            File.writeTo(testPath, modifiedContent.toArray())
            
            // 同步上下文
            let changes = watcher.syncContext()
            @Assert(changes.size == 1, "Should sync one change")
            
            // 验证缓存已更新
            let cachedContent = engine.getFile(testPath)
            match (cachedContent) {
                case Some(content) =>
                    @Assert(content == modifiedContent, "Cache should be updated with new content")
                case _ =>
                    @Assert(false, "File should still be in cache")
            }
            
        } finally {
            try {
                std.fs.remove(testPath)
            } catch (_: Exception) {
                ()
            }
        }
    }
    
    @TestCase
    func testUntrack() {
        let engine = ContextEngine(maxCacheSize: 10)
        let watcher = FileWatcher(engine)
        let testPath = Path("test.txt")
        
        // 假设文件存在（不实际创建）
        watcher.contentHashes["test.txt"] = 12345
        
        @Assert(watcher.getTrackedCount() == 1, "Should have one tracked file")
        
        watcher.untrack(testPath)
        
        @Assert(watcher.getTrackedCount() == 0, "Should have zero tracked files after untrack")
    }
    
    @TestCase
    func testClear() {
        let engine = ContextEngine(maxCacheSize: 10)
        let watcher = FileWatcher(engine)
        
        // 添加一些跟踪
        watcher.contentHashes["file1.txt"] = 123
        watcher.contentHashes["file2.txt"] = 456
        
        @Assert(watcher.getTrackedCount() == 2, "Should have two tracked files")
        
        watcher.clear()
        
        @Assert(watcher.getTrackedCount() == 0, "Should have zero tracked files after clear")
    }
}

