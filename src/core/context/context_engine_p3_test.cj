package cli.core.context

import std.fs.{Path}
import std.unittest.*
import cli.core.context.{ContextEngine, FileContext}
import magic.log.LogUtils

/**
 * P3功能测试
 * 
 * 测试内容：
 * - P3-1: BM25关键词匹配
 */
@Test
public class ContextEngineP3Test {
    
    /**
     * 测试P3-1: BM25 TF计算
     */
    @TestCase
    public func testBM25TermFrequency(): Unit {
        let engine = ContextEngine(maxCacheSize: 10)
        
        // 添加测试文件
        let content = "func calculateTokens() { let tokens = tokenCount; return tokens }"
        engine.addFile(Path("test1.cj"), content)
        
        // 查询包含高频词
        let query = "tokens"
        
        // 获取文件并检查相关性分数
        let ranked = engine.rankFilesByRelevance(query)
        @Assert(ranked.size == 1)
        
        // BM25应该能够识别高频词
        let score = ranked[0].relevanceScore
        @Assert(score > 0.0)
        
        LogUtils.debug("Test testBM25TermFrequency: score=${score}")
    }
    
    /**
     * 测试P3-1: BM25 IDF计算
     */
    @TestCase
    public func testBM25IDF(): Unit {
        let engine = ContextEngine(maxCacheSize: 10)
        
        // 添加多个文件，其中一个包含罕见词
        engine.addFile(Path("file1.cj"), "func hello() { println(\"common word\") }")
        engine.addFile(Path("file2.cj"), "func world() { println(\"common word\") }")
        engine.addFile(Path("file3.cj"), "func rare() { Cl100kTokenizer encoder }")
        
        // 查询罕见词（IDF应该高）
        let query = "Cl100kTokenizer"
        let ranked = engine.rankFilesByRelevance(query)
        
        @Assert(ranked.size == 3)
        // file3应该排在最前面（因为包含罕见词）
        @Assert(ranked[0].path.toString().contains("file3"))
        
        LogUtils.debug("Test testBM25IDF: top file=${ranked[0].path.toString()}, score=${ranked[0].relevanceScore}")
    }
    
    /**
     * 测试P3-1: BM25 文档长度归一化
     */
    @TestCase
    public func testBM25LengthNormalization(): Unit {
        let engine = ContextEngine(maxCacheSize: 10)
        
        // 添加长文档
        let longDoc = """
            func longFunction() {
                let a = 1
                let b = 2
                let c = 3
                let d = 4
                let e = 5
                let f = 6
                let g = 7
                let h = 8
                let i = 9
                let j = 10
                return word
            }
        """
        
        // 添加短文档（包含相同的词）
        let shortDoc = "func shortFunction() { return word }"
        
        engine.addFile(Path("long.cj"), longDoc)
        engine.addFile(Path("short.cj"), shortDoc)
        
        // 查询"word"
        let query = "word"
        let ranked = engine.rankFilesByRelevance(query)
        
        @Assert(ranked.size == 2)
        
        // 两个文档都包含"word"，但BM25会进行长度归一化
        // 短文档的相关性应该稍高（因为词密度更高）
        LogUtils.debug("Test testBM25LengthNormalization: long=${ranked[0].path.toString()} score=${ranked[0].relevanceScore}, short=${ranked[1].path.toString()} score=${ranked[1].relevanceScore}")
    }
    
    /**
     * 测试P3-1: BM25 多词查询
     */
    @TestCase
    public func testBM25MultiWordQuery(): Unit {
        let engine = ContextEngine(maxCacheSize: 10)
        
        engine.addFile(Path("file1.cj"), "func calculateTokens() { let count = estimateTokens(content) }")
        engine.addFile(Path("file2.cj"), "func processFile() { let result = readFile(path) }")
        engine.addFile(Path("file3.cj"), "func estimateTokens() { return tokenCount }")
        
        // 查询两个词
        let query = "tokens estimate"
        let ranked = engine.rankFilesByRelevance(query)
        
        @Assert(ranked.size == 3)
        
        // file1和file3应该排在前面（包含两个词）
        let top = ranked[0].path.toString()
        @Assert(top.contains("file1") || top.contains("file3"))
        
        LogUtils.debug("Test testBM25MultiWordQuery: top=${ranked[0].path.toString()}, score=${ranked[0].relevanceScore}")
    }
    
    /**
     * 测试P3-1: BM25 vs 简单匹配对比
     */
    @TestCase
    public func testBM25VsSimpleMatch(): Unit {
        let engine = ContextEngine(maxCacheSize: 10)
        
        // 场景：多个文件包含相同词，但词频不同
        engine.addFile(Path("freq1.cj"), "word")
        engine.addFile(Path("freq3.cj"), "word word word")
        engine.addFile(Path("freq5.cj"), "word word word word word")
        
        let query = "word"
        let ranked = engine.rankFilesByRelevance(query)
        
        @Assert(ranked.size == 3)
        
        // BM25应该能够识别词频差异
        // freq5应该有最高的分数（但会进行TF饱和）
        @Assert(ranked[0].relevanceScore >= ranked[1].relevanceScore)
        @Assert(ranked[1].relevanceScore >= ranked[2].relevanceScore)
        
        LogUtils.debug("Test testBM25VsSimpleMatch: freq1=${ranked[2].relevanceScore}, freq3=${ranked[1].relevanceScore}, freq5=${ranked[0].relevanceScore}")
    }
    
    /**
     * 测试P3-1: BM25 空文档处理
     */
    @TestCase
    public func testBM25EmptyDocument(): Unit {
        let engine = ContextEngine(maxCacheSize: 10)
        
        engine.addFile(Path("empty.cj"), "")
        engine.addFile(Path("normal.cj"), "func test() { return value }")
        
        let query = "test"
        let ranked = engine.rankFilesByRelevance(query)
        
        // 空文档不应该崩溃
        @Assert(ranked.size == 2)
        
        // normal.cj应该排在前面
        @Assert(ranked[0].path.toString().contains("normal"))
        
        LogUtils.debug("Test testBM25EmptyDocument: empty=${ranked[1].relevanceScore}, normal=${ranked[0].relevanceScore}")
    }
    
    /**
     * 测试P3-1: BM25 统计更新
     */
    @TestCase
    public func testBM25StatsUpdate(): Unit {
        let engine = ContextEngine(maxCacheSize: 10)
        
        // 添加文件
        engine.addFile(Path("file1.cj"), "func one() { return 1 }")
        engine.addFile(Path("file2.cj"), "func two() { return 2 }")
        
        // 查询
        let query1 = "func"
        let ranked1 = engine.rankFilesByRelevance(query1)
        @Assert(ranked1.size == 2)
        
        // 删除一个文件
        engine.removeFile(Path("file1.cj"))
        
        // 再次查询（统计应该更新）
        let ranked2 = engine.rankFilesByRelevance(query1)
        @Assert(ranked2.size == 1)
        @Assert(ranked2[0].path.toString().contains("file2"))
        
        LogUtils.debug("Test testBM25StatsUpdate: after removal, remaining file score=${ranked2[0].relevanceScore}")
    }
    
    /**
     * 测试P3-1: BM25 回退机制
     */
    @TestCase
    public func testBM25Fallback(): Unit {
        let engine = ContextEngine(maxCacheSize: 10)
        
        // 添加第一个文件（此时avgDocLength仍为0）
        engine.addFile(Path("first.cj"), "func test() { return 1 }")
        
        // 查询应该使用回退机制（不会崩溃）
        let query = "test"
        let ranked = engine.rankFilesByRelevance(query)
        
        @Assert(ranked.size == 1)
        @Assert(ranked[0].relevanceScore > 0.0)
        
        LogUtils.debug("Test testBM25Fallback: score=${ranked[0].relevanceScore}")
    }
    
    /**
     * 测试P3-1: BM25 性能（大规模）
     */
    @TestCase
    public func testBM25Performance(): Unit {
        let engine = ContextEngine(maxCacheSize: 50)
        
        // 添加多个文件
        for (i in 0..20) {
            let content = "func test${i}() { let value = ${i}; return value }"
            engine.addFile(Path("file${i}.cj"), content)
        }
        
        // 查询
        let query = "value"
        let ranked = engine.rankFilesByRelevance(query)
        
        @Assert(ranked.size == 20)
        @Assert(ranked[0].relevanceScore > 0.0)
        
        LogUtils.debug("Test testBM25Performance: ranked ${ranked.size} files")
    }
    
    /**
     * 测试P3-1: BM25 综合场景
     */
    @TestCase
    public func testBM25Comprehensive(): Unit {
        let engine = ContextEngine(maxCacheSize: 20)
        
        // 模拟真实场景：代码库搜索
        engine.addFile(Path("token_utils.cj"), """
            func estimateTokens(text: String): Int64 {
                let tokenizer = Cl100kTokenizer()
                return tokenizer.encode(text)
            }
        """)
        
        engine.addFile(Path("file_context.cj"), """
            public class FileContext {
                public var tokenCount: Int64
                public func estimateTokens(content: String): Unit {
                    this.tokenCount = calculateTokenCount(content)
                }
            }
        """)
        
        engine.addFile(Path("context_engine.cj"), """
            public class ContextEngine {
                public func addFile(path: Path, content: String): Unit {
                    let context = FileContext(path, content)
                    let tokenCount = context.tokenCount
                }
            }
        """)
        
        // 查询"tokenCount"
        let query = "tokenCount"
        let ranked = engine.rankFilesByRelevance(query)
        
        @Assert(ranked.size == 3)
        
        // file_context.cj应该排在最前面（词频最高）
        @Assert(ranked[0].path.toString().contains("file_context") || 
                ranked[0].path.toString().contains("context_engine"))
        
        LogUtils.debug("Test testBM25Comprehensive: top=${ranked[0].path.toString()}, score=${ranked[0].relevanceScore}")
    }
    
    /**
     * 测试P3-1: BM25 准确率验证
     */
    @TestCase
    public func testBM25Accuracy(): Unit {
        let engine = ContextEngine(maxCacheSize: 10)
        
        // 添加文件：目标文件 vs 干扰文件
        engine.addFile(Path("target.cj"), "BM25 algorithm implementation with term frequency and inverse document frequency")
        engine.addFile(Path("distractor1.cj"), "simple algorithm")
        engine.addFile(Path("distractor2.cj"), "term frequency")
        engine.addFile(Path("distractor3.cj"), "document frequency")
        
        // 查询"BM25 algorithm"
        let query = "BM25 algorithm"
        let ranked = engine.rankFilesByRelevance(query)
        
        @Assert(ranked.size == 4)
        
        // target.cj应该排在第一位（最相关）
        @Assert(ranked[0].path.toString().contains("target"))
        
        LogUtils.debug("Test testBM25Accuracy: top=${ranked[0].path.toString()}, score=${ranked[0].relevanceScore}")
    }
}

