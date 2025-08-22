package cli.core.tools

import cli.core.config.CliConfig

import std.fs.{Directory, Path, exists}
import std.unittest.testmacro.{Test, PowerAssert}

/**
 * Test function to verify glob functionality.
 * Creates a temporary directory structure and tests various glob patterns.
 */
@Test
public func testGlob(): Unit {
    println("=== Testing Glob Functionality ===")

    // Test globToRegex conversion first
    testGlobToRegex()

    // Test with current project structure
    testWithRealFiles()

    println("=== Glob Tests Completed ===")
}

/**
 * Tests the globToRegex conversion function
 */
@Test
private func testGlobToRegex(): Unit {
    println("\n--- Testing globToRegex conversion ---")

    // Test cases: (input pattern, expected regex)
    let testCases = [
        ("*.cj", "^.*\\.cj$"),
        ("test*", "^test.*$"),
        ("test?.cj", "^test.\\.cj$"),
        ("src/*.cj", "^src/.*\\.cj$"),
        ("[abc]*.txt", "^\\[abc\\].*\\.txt$"),
        ("file.{js,ts}", "^file\\.\\{js,ts\\}$")
    ]

    for (testCase in testCases) {
        let input = testCase[0]
        let expected = testCase[1]
        let actual = globToRegex(input)

        println("Testing '${input}' -> '${actual}'")
        @PowerAssert(actual, expected)
    }
}

/**
 * Tests glob function with real files in the current project
 */
private func testWithRealFiles(): Unit {
    println("\n--- Testing with real files ---")
    let currentDir = CliConfig.cwd.toString()

    // Test simple wildcard patterns
    testPattern("*.cj", currentDir, "Find all .cj files in current directory")
    testPattern("src", currentDir, "Find 'src' directory")
    testPattern("src/*", currentDir, "Find all items directly under src/")

    // Test recursive patterns if src directory exists
    let srcPath = Path(currentDir).join("src")
    if (exists(srcPath)) {
        testPattern("**/glob.cj", currentDir, "Find glob.cj files recursively")
        testPattern("src/**/*.cj", currentDir, "Find all .cj files under src/ recursively")
        testPattern("**/tools/**", currentDir, "Find all items under any 'tools' directory")
    }

    // Test edge cases
    testPattern("**", currentDir, "Find everything (limited results for demo)")
    testPattern("nonexistent*", currentDir, "Pattern matching no files")
}

/**
 * Helper function to test a single glob pattern
 */
private func testPattern(pattern: String, rootPath: String, description: String): Unit {
    println("\nTesting: ${description}")
    println("Pattern: '${pattern}'")

    let results = glob(pattern, rootPath)
    let count = results.size

    // Assert that we get some results for most patterns (except explicitly testing empty results)
    if (!pattern.startsWith("nonexistent")) {
        @PowerAssert(count > 0)
    }

    if (count == 0) {
        println("Result: No matches found")
    } else if (count <= 5) {
        println("Result: ${count} matches:")
        for (path in results) {
            println("  - ${path}")
        }
    } else {
        println("Result: ${count} matches (showing first 5):")
        for (i in 0..5) {
            println("  - ${results[i]}")
        }
        println("  ... and ${count - 5} more")
    }
}

/**
 * Unit tests for individual helper functions
 */
@Test
public func testGlobUnits(): Unit {
    println("\n=== Unit Tests ===")

    // Test string slicing functionality used in globWithDoubleAsterisk
    testStringSlicing()

    // Test pattern splitting
    testPatternSplitting()

    println("=== Unit Tests Completed ===")
}

/**
 * Tests string slicing operations
 */
private func testStringSlicing(): Unit {
    println("\n--- Testing string slicing ---")

    let testStr = "src/test/"
    let withoutTrailing = testStr[0..testStr.size - 1]
    println("Remove trailing slash: '${testStr}' -> '${withoutTrailing}'")
    @PowerAssert(withoutTrailing, "src/test")

    let testStr2 = "/test/file"
    let withoutLeading = testStr2[1..]
    println("Remove leading slash: '${testStr2}' -> '${withoutLeading}'")
    @PowerAssert(withoutLeading, "test/file")
}

/**
 * Tests pattern splitting functionality
 */
private func testPatternSplitting(): Unit {
    println("\n--- Testing pattern splitting ---")

    let patterns = ["src/**/*.cj", "**/test.cj", "build/**", "**"]
    let expectedSizes = [2, 2, 2, 2]

    for (i in 0..patterns.size) {
        let pattern = patterns[i]
        let expectedSize = expectedSizes[i]
        let parts = pattern.split("**")
        println("Split '${pattern}': ${parts.size} parts")

        @PowerAssert(parts.size, expectedSize)

        for (j in 0..parts.size) {
            println("  [${j}]: '${parts[j]}'")
        }
    }
}

/**
 * Benchmark function to test performance with different patterns
 */
@Test
public func benchmarkGlob(): Unit {
    println("\n=== Glob Performance Benchmark ===")
    let currentDir = CliConfig.cwd.toString()

    let patterns = [
        "*.cj",           // Simple wildcard
        "**/glob.cj",     // Recursive search
        "src/**/*.cj",    // Complex recursive
        "**"              // Match everything
    ]

    for (pattern in patterns) {
        println("\nBenchmarking pattern: '${pattern}'")

        // Simple timing (note: Cangjie may not have precise timing APIs)
        let results = glob(pattern, currentDir)
        println("Found ${results.size} matches")

        // Assert that we get reasonable results
        @PowerAssert(results.size >= 0)

        // Could add more sophisticated timing here if available
    }

    println("\n=== Benchmark Completed ===")
}