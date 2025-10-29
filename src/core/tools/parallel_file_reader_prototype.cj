package cli.core.tools

import std.sync.*
import std.collection.*
import std.fs.{Path, File}
import std.time.DateTime
import magic.log.LogUtils

/**
 * 🚀 P0-1 并行工具执行原型 - Step 1: 原型验证（简化版本）
 * 
 * 目标：
 * 1. 验证 spawn 并行执行的可行性
 * 2. 测量并行读取vs串行读取的性能提升
 * 3. 验证线程安全性
 * 
 * 策略：
 * - 使用 Mutex + Condition 实现同步
 * - 使用简单的计数器追踪完成状态
 * - 限制并发数避免资源耗尽
 * 
 * 预期：
 * - 并行读取比串行快 1.5-2倍
 * - 线程安全
 * - 内存可控
 */
public class ParallelFileReaderPrototype {
    
    // 最大并发数限制（避免资源耗尽）
    private static let MAX_CONCURRENCY: Int = 4
    
    /**
     * 串行读取多个文件（基准测试）
     */
    public static func serialReadFiles(filePaths: Array<String>): HashMap<String, String> {
        let startMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let results = HashMap<String, String>()
        
        LogUtils.info("[Serial] Starting to read ${filePaths.size} files...")
        
        for (filePath in filePaths) {
            try {
                let path = Path(filePath)
                let content = String.fromUtf8(File.readFrom(path))
                results[filePath] = content
                LogUtils.debug("[Serial] Read ${filePath} (${content.size} bytes)")
            } catch (e: Exception) {
                results[filePath] = "Error: ${e.message}"
                LogUtils.error("[Serial] Failed to read ${filePath}: ${e.message}")
            }
        }
        
        let endMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let durationMs = endMs - startMs
        LogUtils.info("[Serial] Completed in ${durationMs}ms")
        
        return results
    }
    
    /**
     * 并行读取多个文件（使用 Mutex + Condition）
     * 
     * 策略：分批并发，每批最多MAX_CONCURRENCY个文件
     */
    public static func parallelReadFiles(filePaths: Array<String>): HashMap<String, String> {
        let startMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let results = HashMap<String, String>()
        let totalFiles = filePaths.size
        
        LogUtils.info("[Parallel] Starting to read ${totalFiles} files in parallel (max ${MAX_CONCURRENCY} concurrent)...")
        
        // 分批处理
        var index = 0
        while (index < totalFiles) {
            let batchEnd = if (index + MAX_CONCURRENCY < totalFiles) {
                index + MAX_CONCURRENCY
            } else {
                totalFiles
            }
            let batchSize = batchEnd - index
            
            LogUtils.debug("[Parallel] Processing batch: files ${index} to ${batchEnd - 1}")
            
            // 为当前批次创建并发任务
            // 使用 ArrayList 存储完成状态，避免lambda捕获可变变量问题
            let completionList = ArrayList<Bool>()
            let mutex = Mutex()
            let condition = synchronized(mutex) { mutex.condition() }
            
            var i = index
            while (i < batchEnd) {
                let filePath = filePaths[i]
                spawn {
                    try {
                        let path = Path(filePath)
                        let content = String.fromUtf8(File.readFrom(path))
                        
                        synchronized(mutex) {
                            results[filePath] = content
                            completionList.add(true)
                            condition.notifyAll()
                        }
                        LogUtils.debug("[Parallel] Read ${filePath} (${content.size} bytes)")
                    } catch (e: Exception) {
                        synchronized(mutex) {
                            results[filePath] = "Error: ${e.message}"
                            completionList.add(true)
                            condition.notifyAll()
                        }
                        LogUtils.error("[Parallel] Failed to read ${filePath}: ${e.message}")
                    }
                }
                i += 1
            }
            
            // 等待当前批次完成
            synchronized(mutex) {
                condition.waitUntil({ => completionList.size >= batchSize })
            }
            
            index = batchEnd
        }
        
        let endMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let durationMs = endMs - startMs
        LogUtils.info("[Parallel] Completed in ${durationMs}ms")
        
        return results
    }
    
    /**
     * 简化的性能对比测试
     * 
     * 返回：加速比
     */
    public static func simplePerformanceTest(filePaths: Array<String>): Float64 {
        LogUtils.info("═══════════════════════════════════════════════════════")
        LogUtils.info("🚀 Simple Performance Test (${filePaths.size} files)")
        LogUtils.info("═══════════════════════════════════════════════════════")
        
        // 串行测试
        LogUtils.info("📊 Serial Reading...")
        let serialStart = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let serialResults = ParallelFileReaderPrototype.serialReadFiles(filePaths)
        let serialEnd = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let serialDuration = serialEnd - serialStart
        
        // 并行测试
        LogUtils.info("📊 Parallel Reading...")
        let parallelStart = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let parallelResults = ParallelFileReaderPrototype.parallelReadFiles(filePaths)
        let parallelEnd = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let parallelDuration = parallelEnd - parallelStart
        
        // 计算加速比
        let speedup = if (parallelDuration > 0 && serialDuration > 0) {
            Float64(serialDuration) / Float64(parallelDuration)
        } else {
            0.0
        }
        
        // 结果
        LogUtils.info("═══════════════════════════════════════════════════════")
        LogUtils.info("📈 Results")
        LogUtils.info("   Serial:   ${serialDuration}ms (${serialResults.size} files)")
        LogUtils.info("   Parallel: ${parallelDuration}ms (${parallelResults.size} files)")
        LogUtils.info("   Speedup:  ${speedup}x")
        
        if (speedup >= 1.5) {
            LogUtils.info("   ✅ PASS (≥1.5x)")
        } else if (speedup > 1.0) {
            LogUtils.info("   ⚠️  MARGINAL (>1x)")
        } else {
            LogUtils.info("   ❌ FAIL (≤1x)")
        }
        LogUtils.info("═══════════════════════════════════════════════════════")
        
        return speedup
    }
    
}
