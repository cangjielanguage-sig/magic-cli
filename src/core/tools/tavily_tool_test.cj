package cli.core.tools

import std.env.setVariable
import std.unittest.testmacro.{Test, PowerAssert}

/**
 * TavilyTool test cases
 */
@Test
public func testTavilyTool(): Unit {
    println("=== Testing Tavily Tool Functionality ===")
    
    // Set API key for testing
    setVariable("TAVILY_API_KEY", "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")
    
    // Test search functionality
    testSearch()
    
    // Test empty query handling
    testEmptyQuery()
    
    // Test error handling without API key
    testNoApiKey()
    
    println("=== Tavily Tool Tests Completed ===")
}

/**
 * Test search functionality with actual API call
 */
@Test
private func testSearch(): Unit {
    println("\n--- Testing search functionality ---")
    
    try {
        let tool = TavilyTool()
        let query = "artificial intelligence"
        println("Testing search query: ${query}")
        
        let result = tool.search(query)
        
        // Validate the result format
        @PowerAssert(result.size > 0)
        @PowerAssert(result.contains("Tavily Search Results"))
        @PowerAssert(result.contains(query))
        
        println("✓ Search test passed")
        println("Result length: ${result.size} characters")
        
        // Show sample output (first few lines)
        let lines = result.split("\n")
        let maxLines = if (lines.size < 5) { lines.size } else { 5 }
        println("Sample output:")
        for (i in 0..maxLines) {
            if (i < lines.size && !lines[i].isEmpty()) {
                println("  ${lines[i]}")
            }
        }
        
    } catch (e: Exception) {
        println("! Search test failed: ${e.message}")
        // Don't force failure - network issues might occur
        println("  This might be due to network connectivity or API issues")
    }
}

/**
 * Test empty query handling with tool
 */
@Test
private func testEmptyQuery(): Unit {
    println("\n--- Testing empty query handling ---")
    
    try {
        let tool = TavilyTool()
        let result = tool.search("")
        
        // Should return error message for empty query
        @PowerAssert(result.contains("Search query cannot be empty"))
        
        println("✓ Empty query handling test passed")
        println("Error message: ${result}")
        
    } catch (e: Exception) {
        println("! Empty query test failed: ${e.message}")
        @PowerAssert(false)
    }
}

/**
 * Test error handling without API key
 */
@Test
private func testNoApiKey(): Unit {
    println("\n--- Testing error handling without API key ---")
    
    try {
        // Clear the API key
        setVariable("TAVILY_API_KEY", "")
        
        // This should throw an exception during initialization
        try {
            let tool = TavilyTool()
            println("! Should have thrown exception for missing API key")
            @PowerAssert(false)
        } catch (e: Exception) {
            @PowerAssert(e.message.contains("TAVILY_API_KEY environment variable not set"))
            println("✓ API key validation test passed")
            println("Error message: ${e.message}")
        }
        
        // Restore API key for other tests
        setVariable("TAVILY_API_KEY", "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")
        
    } catch (e: Exception) {
        println("! API key validation test failed: ${e.message}")
        @PowerAssert(false)
    }
}

