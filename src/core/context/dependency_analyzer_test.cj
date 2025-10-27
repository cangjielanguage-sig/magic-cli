package cli.core.context

import std.unittest.*
import std.unittest.testmacro.*
import std.fs.{Path, File}
import cli.core.config.CliConfig

@Test
class DependencyAnalyzerTest {
    
    @TestCase
    func testExtractImports() {
        let engine = ContextEngine(maxCacheSize: 10)
        let analyzer = DependencyAnalyzer(engine)
        
        let testPath = CliConfig.cwd.join("test_imports.cj")
        let testContent = """
package test

import std.fs.{Path, File}
import cli.core.config.CliConfig
import magic.log.LogUtils

func main() {
    // Some code
}
"""
        
        try {
            File.writeTo(testPath, testContent.toArray())
            
            // 分析文件
            let deps = analyzer.analyzeFile(testPath)
            
            @Assert(deps.imports.size == 3, "Should find 3 imports")
            
        } finally {
            try {
                std.fs.remove(testPath)
            } catch (_: Exception) {
                ()
            }
        }
    }
    
    @TestCase
    func testDependencyGraph() {
        let engine = ContextEngine(maxCacheSize: 10)
        let analyzer = DependencyAnalyzer(engine)
        let graph = analyzer.getGraph()
        
        // 添加一些依赖
        let file1 = Path("file1.cj")
        let file2 = Path("file2.cj")
        
        graph.addNode(file1)
        graph.addNode(file2)
        
        graph.addDependency(file1, "std.fs")
        graph.addDependency(file1, "cli.core.config")
        graph.addDependency(file2, "std.fs")
        
        // 检查依赖
        let deps1 = graph.getDependencies(file1)
        @Assert(deps1.size == 2, "File1 should have 2 dependencies")
        
        let deps2 = graph.getDependencies(file2)
        @Assert(deps2.size == 1, "File2 should have 1 dependency")
    }
    
    @TestCase
    func testFindDependents() {
        let engine = ContextEngine(maxCacheSize: 10)
        let analyzer = DependencyAnalyzer(engine)
        let graph = analyzer.getGraph()
        
        let file1 = Path("file1.cj")
        let file2 = Path("file2.cj")
        let file3 = Path("file3.cj")
        
        // 所有文件都依赖 std.fs
        graph.addDependency(file1, "std.fs")
        graph.addDependency(file2, "std.fs")
        graph.addDependency(file3, "cli.core")
        
        // 查找依赖 std.fs 的文件
        let dependents = analyzer.findDependents("std.fs")
        @Assert(dependents.size == 2, "Should find 2 files depending on std.fs")
    }
    
    @TestCase
    func testClearGraph() {
        let engine = ContextEngine(maxCacheSize: 10)
        let analyzer = DependencyAnalyzer(engine)
        let graph = analyzer.getGraph()
        
        graph.addNode(Path("file1.cj"))
        graph.addNode(Path("file2.cj"))
        
        @Assert(graph.size() == 2, "Should have 2 nodes")
        
        analyzer.clear()
        
        @Assert(graph.size() == 0, "Graph should be empty after clear")
    }
    
    @TestCase
    func testAnalyzeFromCache() {
        let engine = ContextEngine(maxCacheSize: 10)
        let analyzer = DependencyAnalyzer(engine)
        
        let testPath = CliConfig.cwd.join("test_cache.cj")
        let testContent = """
package test
import std.fs.Path
func main() {}
"""
        
        try {
            File.writeTo(testPath, testContent.toArray())
            
            // 添加到缓存
            engine.addFile(testPath, testContent)
            
            // 从缓存分析
            let deps = analyzer.analyzeFile(testPath)
            @Assert(deps.imports.size == 1, "Should find 1 import from cache")
            
        } finally {
            try {
                std.fs.remove(testPath)
            } catch (_: Exception) {
                ()
            }
        }
    }
    
    @TestCase
    func testImportWithBraces() {
        let engine = ContextEngine(maxCacheSize: 10)
        let analyzer = DependencyAnalyzer(engine)
        
        let testPath = CliConfig.cwd.join("test_braces.cj")
        let testContent = """
package test
import std.fs.{Path, File, exists}
import cli.core.config.{CliConfig, ModelConfig}
"""
        
        try {
            File.writeTo(testPath, testContent.toArray())
            
            let deps = analyzer.analyzeFile(testPath)
            
            // 应该提取出 "std.fs" 和 "cli.core.config"
            @Assert(deps.imports.size == 2, "Should extract 2 packages")
            
        } finally {
            try {
                std.fs.remove(testPath)
            } catch (_: Exception) {
                ()
            }
        }
    }
}

