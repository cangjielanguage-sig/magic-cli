package cli.core.context

import std.unittest.*
import std.unittest.testmacro.*
import std.fs.{Path, File}
import std.collection.ArrayList
import cli.core.config.CliConfig

@Test
class MentionParserTest {
    
    @TestCase
    func testParseSimpleMention() {
        // 创建一个临时测试文件
        let testFilePath = CliConfig.cwd.join("test_file.txt")
        try {
            File.writeTo(testFilePath, "Test content\nLine 2\n".toArray())
            
            // 测试解析
            let input = "Please explain @test_file.txt to me"
            let result = MentionParser.parse(input)
            
            // 验证
            @Assert(result.mentions.size == 1, "Should find one mention")
            @Assert(result.mentions[0].originalText == "@test_file.txt", "Should preserve original text")
            @Assert(result.cleanedInput.contains("[File: test_file.txt]"), "Should replace @mention in input")
            
        } finally {
            // 清理测试文件
            try {
                std.fs.remove(testFilePath)
            } catch (_: Exception) {
                ()
            }
        }
    }
    
    @TestCase
    func testParseNoMention() {
        let input = "This is a normal text without any mention"
        let result = MentionParser.parse(input)
        
        @Assert(result.mentions.size == 0, "Should find no mentions")
        @Assert(result.cleanedInput == input, "Input should remain unchanged")
    }
    
    @TestCase
    func testParseMultipleMentions() {
        // 创建测试文件
        let file1 = CliConfig.cwd.join("file1.txt")
        let file2 = CliConfig.cwd.join("file2.txt")
        
        try {
            File.writeTo(file1, "Content 1\n".toArray())
            File.writeTo(file2, "Content 2\n".toArray())
            
            let input = "Compare @file1.txt and @file2.txt"
            let result = MentionParser.parse(input)
            
            @Assert(result.mentions.size == 2, "Should find two mentions")
            
        } finally {
            try {
                std.fs.remove(file1)
                std.fs.remove(file2)
            } catch (_: Exception) {
                ()
            }
        }
    }
    
    @TestCase
    func testReadFileContent() {
        let testFile = CliConfig.cwd.join("test_content.txt")
        let testContent = "Line 1\nLine 2\nLine 3\n"
        
        try {
            File.writeTo(testFile, testContent.toArray())
            
            let resolvedPath = MentionParser.resolveFile("test_content.txt")
            @Assert(resolvedPath != None, "Should resolve existing file")
            
            if (let Some(path) <- resolvedPath) {
                let mention = FileMention(path, "@test_content.txt")
                let content = MentionParser.readFileContent(mention)
                @Assert(content == testContent, "Should read correct content")
            }
            
        } finally {
            try {
                std.fs.remove(testFile)
            } catch (_: Exception) {
                ()
            }
        }
    }
    
    @TestCase
    func testFormatMentionInfo() {
        let testFile = CliConfig.cwd.join("test_info.txt")
        try {
            File.writeTo(testFile, "Line 1\nLine 2\n".toArray())
            
            if (let Some(path) <- MentionParser.resolveFile("test_info.txt")) {
                let mention = FileMention(path, "@test_info.txt")
                let info = MentionParser.formatMentionInfo(mention)
                @Assert(info.contains("2 lines"), "Should show line count")
            }
            
        } finally {
            try {
                std.fs.remove(testFile)
            } catch (_: Exception) {
                ()
            }
        }
    }
}

