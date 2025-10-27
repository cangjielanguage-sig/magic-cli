package cli.core.context

import std.unittest.*
import std.unittest.testmacro.*
import std.fs.{Path, File}
import cli.core.config.CliConfig

@Test
class ContextEngineTest {
    
    @TestCase
    func testAddAndGetFile() {
        let engine = ContextEngine(maxCacheSize: 10)
        let testPath = CliConfig.cwd.join("test_file.txt")
        let testContent = "Test content\nLine 2\n"
        
        try {
            File.writeTo(testPath, testContent.toArray())
            
            // 添加文件
            engine.addFile(testPath, testContent)
            
            // 获取文件
            let result = engine.getFile(testPath)
            @Assert(result != None, "Should retrieve cached file")
            
            if (let Some(content) <- result) {
                @Assert(content == testContent, "Content should match")
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
    func testRemoveFile() {
        let engine = ContextEngine(maxCacheSize: 10)
        let testPath = Path("test.txt")
        let testContent = "content"
        
        engine.addFile(testPath, testContent)
        @Assert(engine.contains(testPath), "Should contain file")
        
        engine.removeFile(testPath)
        @Assert(!engine.contains(testPath), "Should not contain file after removal")
    }
    
    @TestCase
    func testMaxCacheSize() {
        let engine = ContextEngine(maxCacheSize: 3)
        
        // 添加4个文件，应该淘汰最旧的
        engine.addFile(Path("file1.txt"), "content1")
        engine.addFile(Path("file2.txt"), "content2")
        engine.addFile(Path("file3.txt"), "content3")
        
        @Assert(engine.size() == 3, "Should have 3 files")
        
        // 添加第4个文件，应该淘汰 file1
        engine.addFile(Path("file4.txt"), "content4")
        
        @Assert(engine.size() == 3, "Should still have 3 files")
        @Assert(!engine.contains(Path("file1.txt")), "Oldest file should be evicted")
        @Assert(engine.contains(Path("file4.txt")), "New file should be cached")
    }
    
    @TestCase
    func testGetAllFiles() {
        let engine = ContextEngine(maxCacheSize: 10)
        
        engine.addFile(Path("file1.txt"), "content1")
        engine.addFile(Path("file2.txt"), "content2")
        
        let allFiles = engine.getAllFiles()
        @Assert(allFiles.size == 2, "Should return all cached files")
    }
    
    @TestCase
    func testClear() {
        let engine = ContextEngine(maxCacheSize: 10)
        
        engine.addFile(Path("file1.txt"), "content1")
        engine.addFile(Path("file2.txt"), "content2")
        
        @Assert(engine.size() == 2, "Should have 2 files")
        
        engine.clear()
        @Assert(engine.size() == 0, "Should be empty after clear")
    }
    
    @TestCase
    func testLRUEviction() {
        let engine = ContextEngine(maxCacheSize: 2)
        
        engine.addFile(Path("file1.txt"), "content1")
        engine.addFile(Path("file2.txt"), "content2")
        
        // 访问 file1，使其成为最近使用
        let _ = engine.getFile(Path("file1.txt"))
        
        // 添加 file3，应该淘汰 file2（最久未使用）
        engine.addFile(Path("file3.txt"), "content3")
        
        @Assert(engine.contains(Path("file1.txt")), "Recently accessed file should remain")
        @Assert(!engine.contains(Path("file2.txt")), "Least recently used should be evicted")
        @Assert(engine.contains(Path("file3.txt")), "New file should be cached")
    }
}

