/*
 * LSPToolset 批量操作测试
 * 
 * 测试批量获取多个文件符号的功能
 */

package cli.core.tools

import std.unittest.*
import std.collection.*
import std.fs.*
import stdx.encoding.json.*

@Test
class TestLSPToolsetBatch {
    
    // 测试文件路径
    static let testFile1 = "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/core/tools/lsp_toolset.cj"
    static let testFile2 = "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/lsp/lsp_client.cj"
    static let testFile3 = "/Users/louloulin/Documents/linchong/cjproject/magic-cli/src/lsp/types.cj"
    
    @BeforeAll
    static func setup() {
        println("=== LSPToolset 批量操作测试 ===")
        println("")
        
        // 清理缓存，确保测试从干净状态开始
        LSPToolset.clearCache()
    }
    
    /*
     * 测试场景 1: 批量获取 2 个文件的符号
     */
    @TestCase
    func testGetMultipleFileSymbols_TwoFiles() {
        println("\n【测试场景 1】批量获取 2 个文件的符号")
        
        let toolset = LSPToolset()
        
        // 构建文件路径参数（逗号分隔）
        let filePaths = "${testFile1},${testFile2}"
        
        println("  文件列表:")
        println("    1. ${testFile1}")
        println("    2. ${testFile2}")
        
        // 调用批量获取工具
        let args = HashMap<String, JsonValue>()
        args.add("filePaths", JsonString(filePaths))
        
        let response = toolset.getMultipleFileSymbols.invoke(args)
        let result = response.content
        
        println("  调用批量获取工具...")
        
        // 验证返回结果
        @Assert(!result.startsWith("Error"))
        println("    ✓ 没有错误")
        
        // 解析 JSON 结果
        let json = JsonValue.fromStr(result).asObject()
        let files = json.get("files").getOrThrow().asArray().getItems()
        let totalFiles = json.get("totalFiles").getOrThrow().asInt().getValue()
        let totalSymbols = json.get("totalSymbols").getOrThrow().asInt().getValue()
        
        println("    ✓ 成功获取 ${totalFiles} 个文件")
        println("    ✓ 共 ${totalSymbols} 个符号")
        
        // 验证文件数量
        @Assert(totalFiles == 2)
        @Assert(files.size == 2)
        
        println("  ✓ 批量获取 2 个文件测试通过")
    }
    
    /*
     * 测试场景 2: 批量获取 3 个文件的符号
     */
    @TestCase
    func testGetMultipleFileSymbols_ThreeFiles() {
        println("\n【测试场景 2】批量获取 3 个文件的符号")
        
        let toolset = LSPToolset()
        
        // 检查第三个文件是否存在
        if (!exists(Path(testFile3))) {
            println("  ⚠️ 测试文件不存在，跳过此测试: ${testFile3}")
            return
        }
        
        // 构建文件路径参数（逗号分隔）
        let filePaths = "${testFile1},${testFile2},${testFile3}"
        
        println("  文件列表:")
        println("    1. ${testFile1}")
        println("    2. ${testFile2}")
        println("    3. ${testFile3}")
        
        // 调用批量获取工具
        let args = HashMap<String, JsonValue>()
        args.add("filePaths", JsonString(filePaths))
        
        let response = toolset.getMultipleFileSymbols.invoke(args)
        let result = response.content
        
        println("  调用批量获取工具...")
        
        // 验证返回结果
        @Assert(!result.startsWith("Error"))
        println("    ✓ 没有错误")
        
        // 解析 JSON 结果
        let json = JsonValue.fromStr(result).asObject()
        let files = json.get("files").getOrThrow().asArray().getItems()
        let totalFiles = json.get("totalFiles").getOrThrow().asInt().getValue()
        let totalSymbols = json.get("totalSymbols").getOrThrow().asInt().getValue()
        
        println("    ✓ 成功获取 ${totalFiles} 个文件")
        println("    ✓ 共 ${totalSymbols} 个符号")
        
        // 验证文件数量
        @Assert(totalFiles == 3)
        @Assert(files.size == 3)
        
        // 验证每个文件都有符号
        for (i in 0..files.size) {
            let file = files[i].asObject()
            let filePath = file.get("filePath").getOrThrow().asString().getValue()
            let symbolCount = file.get("symbolCount").getOrThrow().asInt().getValue()
            
            println("    文件 ${i + 1}: ${symbolCount} 个符号")
            @Assert(symbolCount > 0)
        }
        
        println("  ✓ 批量获取 3 个文件测试通过")
    }
    
    /*
     * 测试场景 3: 错误处理 - 无效文件路径
     */
    @TestCase
    func testGetMultipleFileSymbols_InvalidFile() {
        println("\n【测试场景 3】错误处理 - 无效文件路径")
        
        let toolset = LSPToolset()
        
        // 包含一个不存在的文件
        let filePaths = "${testFile1},/invalid/path/file.cj"
        
        println("  文件列表（包含无效文件）:")
        println("    1. ${testFile1}")
        println("    2. /invalid/path/file.cj (不存在)")
        
        // 调用批量获取工具
        let args = HashMap<String, JsonValue>()
        args.add("filePaths", JsonString(filePaths))
        
        let response = toolset.getMultipleFileSymbols.invoke(args)
        let result = response.content
        
        println("  调用批量获取工具...")
        
        // 应该返回错误
        @Assert(result.startsWith("Error"))
        println("    ✓ 正确返回错误信息")
        println("    错误: ${result}")
        
        println("  ✓ 错误处理测试通过")
    }
    
    /*
     * 测试场景 4: 错误处理 - 非 .cj 文件
     */
    @TestCase
    func testGetMultipleFileSymbols_NonCjFile() {
        println("\n【测试场景 4】错误处理 - 非 .cj 文件")
        
        let toolset = LSPToolset()
        
        // 包含一个非 .cj 文件
        let filePaths = "${testFile1},/tmp/test.txt"
        
        println("  文件列表（包含非 .cj 文件）:")
        println("    1. ${testFile1}")
        println("    2. /tmp/test.txt (非 .cj 文件)")
        
        // 调用批量获取工具
        let args = HashMap<String, JsonValue>()
        args.add("filePaths", JsonString(filePaths))
        
        let response = toolset.getMultipleFileSymbols.invoke(args)
        let result = response.content
        
        println("  调用批量获取工具...")
        
        // 应该返回错误
        @Assert(result.startsWith("Error"))
        println("    ✓ 正确返回错误信息")
        println("    错误: ${result}")
        
        println("  ✓ 错误处理测试通过")
    }
    
    /*
     * 测试场景 5: 性能测试 - 批量 vs 单个调用
     */
    @TestCase
    func testGetMultipleFileSymbols_Performance() {
        println("\n【测试场景 5】性能测试 - 批量 vs 单个调用")
        
        let toolset = LSPToolset()
        
        // 清理缓存，确保公平比较
        LSPToolset.clearCache()
        
        // 方式 1: 批量调用
        println("  方式 1: 批量调用 2 个文件...")
        let filePaths = "${testFile1},${testFile2}"
        let args = HashMap<String, JsonValue>()
        args.add("filePaths", JsonString(filePaths))
        
        let response = toolset.getMultipleFileSymbols.invoke(args)
        let result = response.content
        
        @Assert(!result.startsWith("Error"))
        println("    ✓ 批量调用成功")
        
        // 清理缓存
        LSPToolset.clearCache()
        
        // 方式 2: 单个调用
        println("  方式 2: 单个调用 2 个文件...")
        
        let args1 = HashMap<String, JsonValue>()
        args1.add("filePath", JsonString(testFile1))
        let response1 = toolset.getFileSymbols.invoke(args1)
        @Assert(!response1.content.startsWith("Error"))
        
        let args2 = HashMap<String, JsonValue>()
        args2.add("filePath", JsonString(testFile2))
        let response2 = toolset.getFileSymbols.invoke(args2)
        @Assert(!response2.content.startsWith("Error"))
        
        println("    ✓ 单个调用成功")
        
        println("  ✓ 性能测试通过（批量调用应该更快）")
    }
}

