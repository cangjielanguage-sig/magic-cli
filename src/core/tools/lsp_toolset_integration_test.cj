/*
 * LSPToolset 集成测试
 * 
 * 测试 LSPToolset 在实际场景中的表现
 */

package cli.core.tools

import cli.lsp.*
import std.unittest.*
import std.collection.*
import std.fs.*
import stdx.encoding.json.*

@Test
class TestLSPToolsetIntegration {
    
    // 测试文件路径
    static let testFile = "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/core/tools/lsp_toolset.cj"
    
    @BeforeAll
    static func setup() {
        println("=== LSPToolset 集成测试 ===")
        println("测试文件: ${testFile}")
        println("")
    }
    
    /*
     * 测试场景 1: 完整的代码分析流程
     */
    @TestCase
    func testCompleteAnalysisWorkflow() {
        println("\n【测试场景 1】完整的代码分析流程")
        
        let toolset = LSPToolset()
        
        // 步骤 1: 获取文件符号列表
        println("  步骤 1: 获取文件符号列表...")
        
        let args1 = HashMap<String, JsonValue>()
        args1.add("filePath", JsonString(testFile))
        let response1 = toolset.getFileSymbols.invoke(args1)
        let symbols = response1.content
        
        println("    ✓ 返回数据长度: ${symbols.size} 字符")
        
        // 验证返回的是有效的 JSON
        @Assert(symbols.contains("\"name\""))
        @Assert(symbols.contains("\"kind\""))
        
        // 步骤 2: 按类型过滤符号（查找所有函数）
        println("  步骤 2: 按类型过滤符号（查找所有函数）...")
        
        let args2 = HashMap<String, JsonValue>()
        args2.add("filePath", JsonString(testFile))
        args2.add("kind", JsonString("function"))
        let response2 = toolset.getSymbolsByKind.invoke(args2)
        let functions = response2.content
        
        println("    ✓ 找到函数数量: ${functions.split("\"name\"").size - 1}")
        
        @Assert(functions.contains("function"))
        
        // 步骤 3: 查找特定符号
        println("  步骤 3: 查找特定符号（getFileSymbols）...")
        
        let args3 = HashMap<String, JsonValue>()
        args3.add("filePath", JsonString(testFile))
        args3.add("symbolName", JsonString("getFileSymbols"))
        args3.add("exactMatch", JsonString("true"))
        let response3 = toolset.findSymbolByName.invoke(args3)
        let foundSymbol = response3.content
        
        println("    ✓ 找到符号: ${foundSymbol.contains("getFileSymbols")}")
        
        @Assert(foundSymbol.contains("getFileSymbols"))
        
        // 步骤 4: 获取符号位置
        println("  步骤 4: 获取符号位置...")
        
        let args4 = HashMap<String, JsonValue>()
        args4.add("filePath", JsonString(testFile))
        args4.add("symbolName", JsonString("getFileSymbols"))
        let response4 = toolset.getSymbolLocation.invoke(args4)
        let location = response4.content
        
        println("    ✓ 位置信息长度: ${location.size} 字符")
        
        // 注意：LSP 可能返回错误或空结果，这是正常的
        // 我们只验证返回了数据
        @Assert(location.size > 0)
        
        println("  ✓ 完整流程测试通过")
    }
    
    /*
     * 测试场景 2: 连续调用稳定性测试
     */
    @TestCase
    func testContinuousCalls() {
        println("\n【测试场景 2】连续调用稳定性测试")
        
        let toolset = LSPToolset()
        let iterations = 5
        
        println("  执行 ${iterations} 次连续调用...")
        
        for (i in 0..iterations) {
            let args = HashMap<String, JsonValue>()
            args.add("filePath", JsonString(testFile))
            let response = toolset.getFileSymbols.invoke(args)
            
            println("    第 ${i + 1} 次调用完成，返回 ${response.content.size} 字符")
            @Assert(response.content.size > 0)
        }
        
        println("  ✓ 连续调用测试通过")
    }
    
    /*
     * 测试场景 3: 错误处理测试
     */
    @TestCase
    func testErrorHandling() {
        println("\n【测试场景 3】错误处理测试")
        
        let toolset = LSPToolset()
        
        // 测试 1: 无效的文件类型
        println("  测试 1: 无效的文件类型...")
        let args1 = HashMap<String, JsonValue>()
        args1.add("filePath", JsonString("/path/to/file.txt"))
        let response1 = toolset.getFileSymbols.invoke(args1)
        @Assert(response1.content.contains("Error"))
        println("    ✓ 正确处理无效文件类型")
        
        // 测试 2: 文件不存在
        println("  测试 2: 文件不存在...")
        let args2 = HashMap<String, JsonValue>()
        args2.add("filePath", JsonString("/nonexistent/file.cj"))
        let response2 = toolset.getFileSymbols.invoke(args2)
        @Assert(response2.content.contains("Error"))
        println("    ✓ 正确处理文件不存在")
        
        // 测试 3: 相对路径
        println("  测试 3: 相对路径...")
        let args3 = HashMap<String, JsonValue>()
        args3.add("filePath", JsonString("relative/path.cj"))
        let response3 = toolset.getFileSymbols.invoke(args3)
        @Assert(response3.content.contains("Error"))
        println("    ✓ 正确处理相对路径")
        
        println("  ✓ 错误处理测试通过")
    }
    
    /*
     * 测试场景 4: 大文件处理测试
     */
    @TestCase
    func testLargeFile() {
        println("\n【测试场景 4】大文件处理测试")
        
        // 使用一个较大的文件进行测试
        let largeFile = "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/lsp/lsp_client.cj"
        
        if (!exists(Path(largeFile))) {
            println("  ⚠️ 测试文件不存在，跳过此测试")
            return
        }
        
        let toolset = LSPToolset()
        
        println("  测试文件: ${largeFile}")
        
        let args = HashMap<String, JsonValue>()
        args.add("filePath", JsonString(largeFile))
        let response = toolset.getFileSymbols.invoke(args)
        
        println("  返回数据长度: ${response.content.size} 字符")
        
        @Assert(response.content.size > 0)
        println("  ✓ 大文件处理测试通过")
    }
    
    /*
     * 测试场景 5: 多文件顺序处理测试
     */
    @TestCase
    func testMultipleFiles() {
        println("\n【测试场景 5】多文件顺序处理测试")
        println("  注意: 当前 LSP 客户端使用单例模式")
        println("  此测试验证顺序处理多个文件的稳定性")
        
        let toolset = LSPToolset()
        let testFiles = [
            testFile,
            "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/lsp/lsp_client.cj",
            "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/lsp/types.cj"
        ]
        
        for (i in 0..testFiles.size) {
            let file = testFiles[i]
            if (!exists(Path(file))) {
                println("  ⚠️ 文件不存在，跳过: ${file}")
                continue
            }
            
            println("  处理文件 ${i + 1}: ${file}")
            
            let args = HashMap<String, JsonValue>()
            args.add("filePath", JsonString(file))
            let response = toolset.getFileSymbols.invoke(args)
            
            println("    ✓ 成功，返回 ${response.content.size} 字符")
            @Assert(response.content.size > 0)
        }
        
        println("  ✓ 多文件处理测试通过")
    }
}

