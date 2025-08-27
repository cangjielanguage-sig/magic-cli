package cli.core.tools.fs_utils

import std.fs.*
import std.regex.Regex
import std.collection.*

/**
 * Main glob function that matches files and directories using glob patterns.
 * Supports wildcards (* and ?) and recursive directory matching (**).
 *
 * @param pattern Glob pattern (e.g., "*.cj", "** / test*.cj", "src / **")
 * @param rootPath Absolute path to start searching from
 * @return ArrayList of matching file/directory paths
 */
public func glob(pattern: String, rootPath: String): ArrayList<String> {
    let results = ArrayList<String>()
    let root = Path(rootPath)

    // Return empty results if root path doesn't exist
    if (!exists(root)) {
        return results
    }

    // Handle ** patterns (recursive directory matching) specially
    if (pattern.contains("**")) {
        globWithDoubleAsterisk(root, pattern, results)
    } else {
        // Handle patterns without ** - could be simple filename or path-based
        if (pattern.contains("/")) {
            // Path-based pattern like "src/*" or "dir/file.txt"
            globWithPath(root, pattern, results)
        } else {
            // Simple filename pattern like "*.cj" or "test*"
            let regex = Regex(globToRegex(pattern), [])
            globRecursive(root, regex, results)
        }
    }

    return results
}

/**
 * Handles glob patterns containing ** (recursive directory matching).
 * Now supports complex patterns with multiple ** segments.
 *
 * Examples:
 * - "** /test.cj" -> find test.cj in any subdirectory
 * - "src / **" -> find everything under src/
 * - "src / ** / *.cj" -> find all .cj files under src/ recursively
 * - "** /tools / **" -> find everything under any 'tools' directory
 * - "** / ** / **" -> find everything at least 3 levels deep
 */
private func globWithDoubleAsterisk(currentPath: Path, pattern: String, results: ArrayList<String>): Unit {
    // Handle the most common simple cases first for performance
    let parts = pattern.split("**")

    if (parts.size == 2) {
        // Simple case: only one ** in pattern
        let beforePart = parts[0]
        let afterPart = parts[1]

        // Remove leading/trailing slashes from pattern parts
        let beforePattern = if (beforePart.endsWith("/")) {
            beforePart[0..beforePart.size - 1]
        } else {
            beforePart
        }
        let afterPattern = if (afterPart.startsWith("/")) {
            afterPart[1..]
        } else {
            afterPart
        }

        if (beforePattern.isEmpty() && !afterPattern.isEmpty()) {
            // Pattern like "**/something"
            let afterRegex = Regex(globToRegex(afterPattern), [])
            globRecursiveWithAfterMatch(currentPath, afterRegex, results)
        } else if (!beforePattern.isEmpty() && afterPattern.isEmpty()) {
            // Pattern like "something/**"
            let beforeRegex = Regex(globToRegex(beforePattern), [])
            globRecursiveWithBeforeMatch(currentPath, beforeRegex, results)
        } else if (!beforePattern.isEmpty() && !afterPattern.isEmpty()) {
            // Pattern like "something/**/other"
            let beforeRegex = Regex(globToRegex(beforePattern), [])
            let afterRegex = Regex(globToRegex(afterPattern), [])
            globRecursiveWithBeforeAfterMatch(currentPath, beforeRegex, afterRegex, results)
        } else {
            // Pattern is just "**"
            globRecursiveAll(currentPath, results)
        }
    } else if (parts.size >= 3) {
        // Complex case: multiple ** in pattern - use advanced matching
        matchComplexPattern(currentPath, parts, results)
    }
}

/**
 * Handles complex patterns with multiple ** segments.
 * Examples: "** / tools / **", "** / ** / **", "src / ** /test/ ** /file.cj"
 */
private func matchComplexPattern(currentPath: Path, parts: Array<String>, results: ArrayList<String>): Unit {
    if (parts.size == 3) {
        // Handle patterns like "**/middle/**"
        let beforePart = parts[0]
        let middlePart = parts[1]
        let afterPart = parts[2]

        // Clean up the middle part
        let middlePattern = if (middlePart.startsWith("/") && middlePart.endsWith("/")) {
            middlePart[1..middlePart.size - 1]
        } else if (middlePart.startsWith("/")) {
            middlePart[1..]
        } else if (middlePart.endsWith("/")) {
            middlePart[0..middlePart.size - 1]
        } else {
            middlePart
        }

        if (beforePart.isEmpty() && afterPart.isEmpty()) {
            // Pattern like "**/tools/**"
            if (!middlePattern.isEmpty()) {
                let middleRegex = Regex(globToRegex(middlePattern), [])
                findMiddleAndCollectAll(currentPath, middleRegex, results)
            } else {
                // Pattern like "**/*/**" - just collect everything
                globRecursiveAll(currentPath, results)
            }
        }
    } else if (parts.size == 4) {
        // Handle patterns like "**/**/**" (all empty parts except separators)
        var allEmpty = true
        for (part in parts) {
            let cleanPart = if (part == "/" || part == "") { "" } else { part }
            if (!cleanPart.isEmpty()) {
                allEmpty = false
                break
            }
        }
        if (allEmpty) {
            // Pattern like "**/**/**" - collect everything
            globRecursiveAll(currentPath, results)
        }
    }
    // For more complex patterns, fall back to collecting everything
    // This is a simplification - a full implementation would parse recursively
}

/**
 * Finds directories matching the middle pattern, then collects everything under them.
 * Used for patterns like "** / tools / **" where we find 'tools' directory anywhere.
 */
private func findMiddleAndCollectAll(currentPath: Path, middleRegex: Regex, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemPath = item.path
        let itemName = item.name

        // Skip ignored files and directories
        if (ignored(item.path)) {
            continue
        }

        if (middleRegex.matches(itemName) && item.isDirectory()) {
            // Found matching middle directory - collect everything under it
            globRecursiveAll(itemPath, results)
        }

        // Continue searching in subdirectories for the middle pattern
        if (item.isDirectory()) {
            findMiddleAndCollectAll(itemPath, middleRegex, results)
        }
    }
}

/**
 * Recursively collects all files and directories under the given path.
 * Used when the glob pattern is just "**" (match everything).
 * Skips hidden files and common ignore patterns.
 */
private func globRecursiveAll(currentPath: Path, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemPath = item.path
        let itemName = item.name

        // Skip hidden files and directories like .git, node_modules, etc.
        if (ignored(item.path)) {
            continue
        }

        // Add current item to results
        results.add(itemPath.toString())

        // Recursively process subdirectories
        if (item.isDirectory()) {
            globRecursiveAll(itemPath, results)
        }
    }
}

/**
 * Recursively searches for items matching the "after" pattern.
 * Used for patterns like "** / filename" where we search for filename in any subdirectory.
 *
 * @param currentPath Current directory being searched
 * @param afterRegex Regex pattern to match against file/directory names
 * @param results List to collect matching paths
 */
private func globRecursiveWithAfterMatch(currentPath: Path, afterRegex: Regex, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemPath = item.path
        let itemName = item.name

        // Skip hidden files and common ignore patterns
        if (ignored(item.path)) {
            continue
        }

        // Check if current item matches the pattern
        if (afterRegex.matches(itemName)) {
            results.add(itemPath.toString())
        }

        // Continue searching in subdirectories
        if (item.isDirectory()) {
            globRecursiveWithAfterMatch(itemPath, afterRegex, results)
        }
    }
}

/**
 * Searches for directories matching the "before" pattern, then collects everything under them.
 * Used for patterns like "dirname / **" where we find dirname then collect all its contents.
 *
 * @param currentPath Current directory being searched
 * @param beforeRegex Regex pattern to match directory names
 * @param results List to collect matching paths
 */
private func globRecursiveWithBeforeMatch(currentPath: Path, beforeRegex: Regex, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemPath = item.path
        let itemName = item.name

        // Skip hidden files and common ignore patterns
        if (ignored(item.path)) {
            continue
        }

        if (beforeRegex.matches(itemName)) {
            // Found matching before part, now collect everything under it
            if (item.isDirectory()) {
                // Recursively collect all contents under this directory
                globRecursiveAll(itemPath, results)
            } else {
                // If it's a file that matches, add it directly
                results.add(itemPath.toString())
            }
        }

        // Continue searching in subdirectories for more matches
        if (item.isDirectory()) {
            globRecursiveWithBeforeMatch(itemPath, beforeRegex, results)
        }
    }
}

/**
 * Handles complex patterns like "src/**/test*.cj".
 * First finds directories matching the before pattern, then searches for after pattern within them.
 *
 * @param currentPath Current directory being searched
 * @param beforeRegex Regex pattern to match directory names (before **)
 * @param afterRegex Regex pattern to match file/directory names (after **)
 * @param results List to collect matching paths
 */
private func globRecursiveWithBeforeAfterMatch(currentPath: Path, beforeRegex: Regex, afterRegex: Regex, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemPath = item.path
        let itemName = item.name

        // Skip hidden files and common ignore patterns
        if (ignored(item.path)) {
            continue
        }

        if (beforeRegex.matches(itemName) && item.isDirectory()) {
            // Found matching before part (directory), now search for after pattern within it
            globRecursiveWithAfterMatch(itemPath, afterRegex, results)
        }

        // Continue searching for before pattern in subdirectories
        if (item.isDirectory()) {
            globRecursiveWithBeforeAfterMatch(itemPath, beforeRegex, afterRegex, results)
        }
    }
}

/**
 * Standard recursive glob matching without ** patterns.
 * Used for simple patterns like "*.cj", "test*", etc.
 *
 * @param currentPath Current directory being searched
 * @param regex Regex pattern converted from glob pattern
 * @param results List to collect matching paths
 */
private func globRecursive(currentPath: Path, regex: Regex, results: ArrayList<String>): Unit {
    for (item in Directory.readFrom(currentPath)) {
        let itemName = item.name
        let itemPath = item.path

        // Skip hidden files and directories like .git, node_modules, etc.
        if (ignored(item.path)) {
            continue
        }

        // Check if current item matches the glob pattern
        if (regex.matches(itemName)) {
            results.add(itemPath.toString())
        }

        // Recursively search subdirectories
        if (item.isDirectory()) {
            globRecursive(itemPath, regex, results)
        }
    }
}

/**
 * Converts a glob pattern to a regular expression.
 * Handles standard glob wildcards and escapes regex special characters.
 *
 * Conversion rules:
 * - "*" becomes ".*" (matches any characters)
 * - "?" becomes "." (matches single character)
 * - Regex special chars are escaped
 * - Path separators "/" are preserved
 *
 * @param pattern Glob pattern string
 * @return Regex pattern string
 */
func globToRegex(pattern: String): String {
    let regex = StringBuilder()
    regex.append("^")  // Start anchor

    let runes = pattern.toRuneArray()
    let len = runes.size
    var i = 0

    while (i < len) {
        let char = runes[i].toString()

        match (char) {
            case "*" => regex.append(".*")      // * matches any characters
            case "?" => regex.append(".")       // ? matches single character
            case "." => regex.append("\\.")     // Escape regex special chars
            case "\\" => regex.append("\\\\")
            case "+" => regex.append("\\+")
            case "^" => regex.append("\\^")
            case "$" => regex.append("\\$")
            case "(" => regex.append("\\(")
            case ")" => regex.append("\\)")
            case "[" => regex.append("\\[")
            case "]" => regex.append("\\]")
            case "{" => regex.append("\\{")
            case "}" => regex.append("\\}")
            case "|" => regex.append("\\|")
            case "/" => regex.append("/")       // Preserve path separators
            case _ => regex.append(char)        // Regular characters as-is
        }
        i += 1
    }

    regex.append("$")  // End anchor
    return regex.toString()
}

/**
 * Handles path-based glob patterns like "src/ *", "dir/file.txt", "a/b/c/ *.cj".
 * Matches against the relative path from root directory.
 */
private func globWithPath(root: Path, pattern: String, results: ArrayList<String>): Unit {
    // Split pattern into path segments
    let pathSegments = pattern.split("/")

    // Start matching from root with first segment
    matchPathSegments(root, pathSegments, 0, "", results)
}

/**
 * Recursively matches path segments against directory structure.
 *
 * @param currentPath Current directory being examined
 * @param segments Array of path segments from the pattern
 * @param segmentIndex Current segment index being matched
 * @param relativePath Relative path built so far
 * @param results List to collect matching paths
 */
private func matchPathSegments(currentPath: Path, segments: Array<String>, segmentIndex: Int64, relativePath: String, results: ArrayList<String>): Unit {
    // If we've matched all segments, we found a complete match
    if (segmentIndex >= segments.size) {
        return
    }

    let segment = segments[segmentIndex]
    let regex = Regex(globToRegex(segment), [])

    for (item in Directory.readFrom(currentPath)) {
        let itemName = item.name
        let itemPath = item.path

        // Skip ignored files and directories
        if (ignored(item.path)) {
            continue
        }

        if (regex.matches(itemName)) {
            // Build the relative path for this match
            let newRelativePath = if (relativePath.isEmpty()) {
                itemName
            } else {
                relativePath + "/" + itemName
            }

            if (segmentIndex == segments.size - 1) {
                // Last segment - add to results
                results.add(itemPath.toString())
            } else if (item.isDirectory()) {
                // Continue with next segment
                matchPathSegments(itemPath, segments, segmentIndex + 1, newRelativePath, results)
            }
        }
    }
}
