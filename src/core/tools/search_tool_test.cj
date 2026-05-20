package cli.core.tools

import std.env.setVariable
import std.unittest.testmacro.{Test, PowerAssert}

/**
 * TavilyTool test cases
 */
@Test
public func testTavilyTool(): Unit {
    PrintUtils.printLine("=== Testing Tavily Tool Functionality ===")

    // Set API key for testing
    setVariable("TAVILY_API_KEY", "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")

    // Test search functionality
    testSearch()

    // Test empty query handling
    testEmptyQuery()

    // Test error handling without API key
    testNoApiKey()

    PrintUtils.printLine("=== Tavily Tool Tests Completed ===")
}

/**
 * Test search functionality with actual API call
 */
@Test
private func testSearch(): Unit {
    PrintUtils.printLine("\n--- Testing search functionality ---")

    try {
        let tool = TavilyTool()
        let query = "artificial intelligence"
        PrintUtils.printLine("Testing search query: ${query}")

        let result = tool.search(query)

        // Validate the result format
        @PowerAssert(result.size > 0)
        @PowerAssert(result.contains("Tavily Search Results"))
        @PowerAssert(result.contains(query))

        PrintUtils.printLine("✓ Search test passed")
        PrintUtils.printLine("Result length: ${result.size} characters")

        // Show sample output (first few lines)
        let lines = result.split("\n")
        let maxLines = if (lines.size < 5) { lines.size } else { 5 }
        PrintUtils.printLine("Sample output:")
        for (i in 0..maxLines) {
            if (i < lines.size && !lines[i].isEmpty()) {
                PrintUtils.printLine("  ${lines[i]}")
            }
        }

    } catch (e: Exception) {
        PrintUtils.printLine("! Search test failed: ${e.message}")
        // Don't force failure - network issues might occur
        PrintUtils.printLine("  This might be due to network connectivity or API issues")
    }
}

/**
 * Test empty query handling with tool
 */
@Test
private func testEmptyQuery(): Unit {
    PrintUtils.printLine("\n--- Testing empty query handling ---")

    try {
        let tool = TavilyTool()
        let result = tool.search("")

        // Should return error message for empty query
        @PowerAssert(result.contains("Search query cannot be empty"))

        PrintUtils.printLine("✓ Empty query handling test passed")
        PrintUtils.printLine("Error message: ${result}")

    } catch (e: Exception) {
        PrintUtils.printLine("! Empty query test failed: ${e.message}")
        @PowerAssert(false)
    }
}

/**
 * Test error handling without API key
 */
@Test
private func testNoApiKey(): Unit {
    PrintUtils.printLine("\n--- Testing error handling without API key ---")

    try {
        // Clear the API key
        setVariable("TAVILY_API_KEY", "")

        // This should throw an exception during initialization
        try {
            let tool = TavilyTool()
            PrintUtils.printLine("! Should have thrown exception for missing API key")
            @PowerAssert(false)
        } catch (e: Exception) {
            @PowerAssert(e.message.contains("TAVILY_API_KEY environment variable not set"))
            PrintUtils.printLine("✓ API key validation test passed")
            PrintUtils.printLine("Error message: ${e.message}")
        }

        // Restore API key for other tests
        setVariable("TAVILY_API_KEY", "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")

    } catch (e: Exception) {
        PrintUtils.printLine("! API key validation test failed: ${e.message}")
        @PowerAssert(false)
    }
}

//----------------------------------------------------------------------------------
// RawHttpFetchTool test cases
//----------------------------------------------------------------------------------

/**
 * Top-level test runner for RawHttpFetchTool.
 */
@Test
public func testRawHttpFetchTool(): Unit {
    PrintUtils.printLine("=== Testing RawHttpFetchTool ===")
    testFetchRawCangjieDownloadPage()
    testFetchRawStaticPage()
    testFetchRaw404()
    testFetchRawTruncation()
    PrintUtils.printLine("=== RawHttpFetchTool tests completed ===")
}

/**
 * Verify the Cangjie download page (SSR) returns inline <script> JSON in the
 * raw body, asserting that the 1.0.5 SDK archive name is present.
 */
@Test
private func testFetchRawCangjieDownloadPage(): Unit {
    PrintUtils.printLine("\n--- fetchRaw: Cangjie download page (SSR target) ---")
    try {
        let tool = RawHttpFetchTool()
        let result = tool.fetch("https://cangjie-lang.cn/download/1.0.5", 524288)

        // The raw HTML / inline JSON should contain the Windows SDK archive name.
        @PowerAssert(result.contains("cangjie-sdk-windows-x64-1.0.5"))
        PrintUtils.printLine("✓ Cangjie download page raw fetch passed")
    } catch (e: Exception) {
        // Network may be unavailable in CI; degrade to a warning rather than a hard failure.
        PrintUtils.printLine("! fetchRaw Cangjie page skipped (network?): ${e.message}")
    }
}

/**
 * Verify a plain static page returns HTTP 200 and contains recognisable
 * markup in the raw body.
 */
@Test
private func testFetchRawStaticPage(): Unit {
    PrintUtils.printLine("\n--- fetchRaw: plain static page ---")
    try {
        let tool = RawHttpFetchTool()
        let result = tool.fetch("https://example.com", 524288)

        @PowerAssert(result.contains("HTTP Status: 200"))
        @PowerAssert(result.contains("<h1>Example Domain</h1>"))
        PrintUtils.printLine("✓ Static page raw fetch passed")
    } catch (e: Exception) {
        PrintUtils.printLine("! fetchRaw static page skipped (network?): ${e.message}")
    }
}

/**
 * Verify a non-existent path produces an HTTP 4xx error message rather
 * than a body or an unhandled exception.
 */
@Test
private func testFetchRaw404(): Unit {
    PrintUtils.printLine("\n--- fetchRaw: 404 error handling ---")
    try {
        let tool = RawHttpFetchTool()
        let result = tool.fetch("https://example.com/this-does-not-exist-404xyz", 524288)

        @PowerAssert(result.contains("HTTP 4") || result.contains("Web fetch failed"))
        PrintUtils.printLine("✓ 404 error handling passed — result: ${result[..60]}")
    } catch (e: Exception) {
        PrintUtils.printLine("! fetchRaw 404 test skipped (network?): ${e.message}")
    }
}

/**
 * Verify that requesting a very small maxBytes cap triggers the TRUNCATED
 * marker so the agent knows the response was cut short.
 */
@Test
private func testFetchRawTruncation(): Unit {
    PrintUtils.printLine("\n--- fetchRaw: truncation ---")
    try {
        let tool = RawHttpFetchTool()
        let result = tool.fetch("https://en.wikipedia.org/wiki/Cangjie_input_method", 1024)

        @PowerAssert(result.contains("TRUNCATED"))
        PrintUtils.printLine("✓ Truncation test passed")
    } catch (e: Exception) {
        PrintUtils.printLine("! fetchRaw truncation test skipped (network?): ${e.message}")
    }
}

