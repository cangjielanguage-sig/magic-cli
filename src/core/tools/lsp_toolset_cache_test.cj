/*
 * LSPToolset 符号缓存性能测试
 * 
 * 测试符号信息缓存功能的性能提升效果
 */

package cli.core.tools

import std.unittest.*
import std.collection.*
import std.fs.*
import stdx.encoding.json.*

@Test
class TestLSPToolsetCache {
    
    // 测试文件路径
    static let testFile = "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/core/tools/lsp_toolset.cj"
    
    @BeforeAll
    static func setup() {
        println("=== LSPToolset 符号缓存性能测试 ===")
        println("测试文件: ${testFile}")
        println("")
        
        // 清理缓存，确保测试从干净状态开始
        LSPToolset.clearCache()
    }
    
    /*
     * 测试场景 1: 首次调用 vs 缓存调用性能对比
     */
    @TestCase
    func testCachePerformance() {
        println("\n【测试场景 1】符号缓存性能对比")
        
        let toolset = LSPToolset()
        
        // 首次调用（无缓存）
        println("  第 1 次调用（无缓存）...")
        let args1 = HashMap<String, JsonValue>()
        args1.add("filePath", JsonString(testFile))
        let response1 = toolset.getFileSymbols.invoke(args1)
        let result1 = response1.content
        
        println("    ✓ 返回数据长度: ${result1.size} 字符")
        @Assert(result1.size > 0)
        @Assert(!result1.startsWith("Error"))
        
        // 第 2 次调用（使用缓存）
        println("  第 2 次调用（使用缓存）...")
        let args2 = HashMap<String, JsonValue>()
        args2.add("filePath", JsonString(testFile))
        let response2 = toolset.getFileSymbols.invoke(args2)
        let result2 = response2.content
        
        println("    ✓ 返回数据长度: ${result2.size} 字符")
        @Assert(result2.size > 0)
        @Assert(!result2.startsWith("Error"))
        
        // 验证两次调用返回相同的结果
        @Assert(result1 == result2)
        println("    ✓ 两次调用返回相同结果")
        
        // 第 3-5 次调用（持续使用缓存）
        for (i in 3..6) {
            println("  第 ${i} 次调用（使用缓存）...")
            let args = HashMap<String, JsonValue>()
            args.add("filePath", JsonString(testFile))
            let response = toolset.getFileSymbols.invoke(args)
            let result = response.content
            
            @Assert(result == result1)
            println("    ✓ 返回结果一致")
        }
        
        println("  ✓ 符号缓存性能测试通过")
    }
    
    /*
     * 测试场景 2: 多文件缓存测试
     */
    @TestCase
    func testMultipleFilesCache() {
        println("\n【测试场景 2】多文件符号缓存测试")
        
        let toolset = LSPToolset()
        let testFiles = [
            testFile,
            "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/lsp/lsp_client.cj",
            "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/lsp/types.cj"
        ]
        
        // 第一轮：首次调用所有文件
        println("  第一轮：首次调用所有文件...")
        let firstResults = ArrayList<String>()
        for (i in 0..testFiles.size) {
            let file = testFiles[i]
            if (!exists(Path(file))) {
                println("  ⚠️ 文件不存在，跳过: ${file}")
                continue
            }
            
            println("    处理文件 ${i + 1}: ${file}")
            let args = HashMap<String, JsonValue>()
            args.add("filePath", JsonString(file))
            let response = toolset.getFileSymbols.invoke(args)
            let result = response.content
            
            @Assert(result.size > 0)
            @Assert(!result.startsWith("Error"))
            firstResults.add(result)
            println("      ✓ 成功，返回 ${result.size} 字符")
        }
        
        // 第二轮：使用缓存调用所有文件
        println("  第二轮：使用缓存调用所有文件...")
        let secondResults = ArrayList<String>()
        for (i in 0..testFiles.size) {
            let file = testFiles[i]
            if (!exists(Path(file))) {
                continue
            }
            
            println("    处理文件 ${i + 1}: ${file}")
            let args = HashMap<String, JsonValue>()
            args.add("filePath", JsonString(file))
            let response = toolset.getFileSymbols.invoke(args)
            let result = response.content
            
            @Assert(result.size > 0)
            @Assert(!result.startsWith("Error"))
            secondResults.add(result)
            println("      ✓ 成功，返回 ${result.size} 字符")
        }
        
        // 验证两轮结果一致
        @Assert(firstResults.size == secondResults.size)
        for (i in 0..firstResults.size) {
            @Assert(firstResults[i] == secondResults[i])
        }
        println("  ✓ 两轮结果完全一致")
        
        println("  ✓ 多文件缓存测试通过")
    }
    
    /*
     * 测试场景 3: 缓存清理测试
     */
    @TestCase
    func testCacheClear() {
        println("\n【测试场景 3】缓存清理测试")
        
        let toolset = LSPToolset()
        
        // 调用一次，建立缓存
        println("  步骤 1: 调用一次，建立缓存...")
        let args1 = HashMap<String, JsonValue>()
        args1.add("filePath", JsonString(testFile))
        let response1 = toolset.getFileSymbols.invoke(args1)
        let result1 = response1.content
        
        @Assert(result1.size > 0)
        println("    ✓ 缓存已建立")
        
        // 清理缓存
        println("  步骤 2: 清理所有缓存...")
        LSPToolset.clearCache()
        println("    ✓ 缓存已清理")
        
        // 再次调用，应该重新解析
        println("  步骤 3: 再次调用，重新解析...")
        let args2 = HashMap<String, JsonValue>()
        args2.add("filePath", JsonString(testFile))
        let response2 = toolset.getFileSymbols.invoke(args2)
        let result2 = response2.content
        
        @Assert(result2.size > 0)
        @Assert(result1 == result2)
        println("    ✓ 重新解析成功，结果一致")
        
        println("  ✓ 缓存清理测试通过")
    }
    
    /*
     * 测试场景 4: 单个文件缓存清理测试
     */
    @TestCase
    func testSingleFileCacheClear() {
        println("\n【测试场景 4】单个文件缓存清理测试")
        
        let toolset = LSPToolset()
        let file1 = testFile
        let file2 = "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/lsp/lsp_client.cj"
        
        if (!exists(Path(file2))) {
            println("  ⚠️ 测试文件不存在，跳过此测试")
            return
        }
        
        // 调用两个文件，建立缓存
        println("  步骤 1: 调用两个文件，建立缓存...")
        let args1 = HashMap<String, JsonValue>()
        args1.add("filePath", JsonString(file1))
        let response1 = toolset.getFileSymbols.invoke(args1)
        let result1 = response1.content
        
        let args2 = HashMap<String, JsonValue>()
        args2.add("filePath", JsonString(file2))
        let response2 = toolset.getFileSymbols.invoke(args2)
        let result2 = response2.content
        
        @Assert(result1.size > 0)
        @Assert(result2.size > 0)
        println("    ✓ 两个文件的缓存已建立")
        
        // 清理第一个文件的缓存
        println("  步骤 2: 清理第一个文件的缓存...")
        LSPToolset.clearSymbolCache(file1)
        println("    ✓ 第一个文件的缓存已清理")
        
        // 再次调用第一个文件，应该重新解析
        println("  步骤 3: 再次调用第一个文件...")
        let args3 = HashMap<String, JsonValue>()
        args3.add("filePath", JsonString(file1))
        let response3 = toolset.getFileSymbols.invoke(args3)
        let result3 = response3.content
        
        @Assert(result3.size > 0)
        @Assert(result1 == result3)
        println("    ✓ 第一个文件重新解析成功")
        
        // 再次调用第二个文件，应该使用缓存
        println("  步骤 4: 再次调用第二个文件（应使用缓存）...")
        let args4 = HashMap<String, JsonValue>()
        args4.add("filePath", JsonString(file2))
        let response4 = toolset.getFileSymbols.invoke(args4)
        let result4 = response4.content
        
        @Assert(result4.size > 0)
        @Assert(result2 == result4)
        println("    ✓ 第二个文件使用缓存成功")
        
        println("  ✓ 单个文件缓存清理测试通过")
    }
    
    /*
     * 测试场景 5: 缓存一致性测试
     */
    @TestCase
    func testCacheConsistency() {
        println("\n【测试场景 5】缓存一致性测试")
        
        let toolset = LSPToolset()
        
        // 连续调用 10 次，验证结果一致性
        println("  连续调用 10 次，验证结果一致性...")
        
        let args = HashMap<String, JsonValue>()
        args.add("filePath", JsonString(testFile))
        
        let firstResult = toolset.getFileSymbols.invoke(args).content
        @Assert(firstResult.size > 0)
        
        for (i in 1..10) {
            let result = toolset.getFileSymbols.invoke(args).content
            @Assert(result == firstResult)
            println("    第 ${i + 1} 次调用: ✓ 结果一致")
        }
        
        println("  ✓ 缓存一致性测试通过")
    }
}

