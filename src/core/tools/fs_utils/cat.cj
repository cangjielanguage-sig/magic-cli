package cli.core.tools.fs_utils

import std.fs.*
import std.io.*
import std.collection.*

/**
 * Reads and returns the full content of a single file with line numbers.
 * Similar to Unix cat -n command, shows content with line numbers for easy reference.
 *
 * @param filePath Absolute path to the file to read
 * @return String containing the full file content with line numbers
 */
public func cat(filePath: String): String {
    if (!Path(filePath).isAbsolute()) {
        return "File path must be absolute"
    }

    if (!exists(filePath)) {
        return "File does not exist: ${filePath}"
    }

    let path = Path(filePath)
    if (!FileInfo(path).isRegular()) {
        return "Path is not a regular file: ${filePath}"
    }

    try (file = File(filePath, Read)) {
        let result = StringBuilder()
        var lineNumber: Int64 = 1
        let reader = StringReader(file)
        while (let Some(line) <- reader.readln()) {
            if (line.isEmpty()) {
                // End of file reached
                break
            }

            // Format with line number (right-aligned, tab-separated)
            let lineNo = lineNumber.toString()
            result.append("${lineNo.padEnd(6)}:${line}\n")
            lineNumber += 1
        }

        if (result.size == 0) {
            return "File is empty: ${filePath}"
        }

        return result.toString()
    } catch (e: FSException) {
        return "Failed to read file: ${e}"
    } catch (e: Exception) {
        return "Error reading file: ${e}"
    }
    throw UnsupportedException("Unreachable")
}

/**
 * Reads and returns a specific range of lines from a file with line numbers.
 * Useful for viewing specific sections of large files.
 *
 * @param filePath Absolute path to the file to read
 * @param startLine Starting line number (1-based, inclusive)
 * @param endLine Ending line number (1-based, inclusive). If 0 or negative, reads to end of file
 * @return String containing the specified line range with line numbers
 */
public func catRange(filePath: String, startLine: Int64, endLine!: Int64 = 0): String {
    if (!Path(filePath).isAbsolute()) {
        return "File path must be absolute"
    }

    if (!exists(filePath)) {
        return "File does not exist: ${filePath}"
    }

    let path = Path(filePath)
    if (!FileInfo(path).isRegular()) {
        return "Path is not a regular file: ${filePath}"
    }

    if (startLine <= 0) {
        return "Start line must be positive (1-based)"
    }

    if (endLine > 0 && endLine < startLine) {
        return "End line must be greater than or equal to start line"
    }

    try(file = File(filePath, Read)) {
        let result = StringBuilder()
        var currentLine: Int64 = 1
        let reader = StringReader(file)

        // Skip lines before startLine
        while (currentLine < startLine) {
            if (let Some(line) <- reader.readln()) {
                line
            } else {
                // End of file reached
                return "Start line ${startLine} exceeds file length"
            }

            currentLine += 1
        }

        // Read and format lines in range
        while (true) {
            let line = if (let Some(line) <- reader.readln()) {
                line
            } else {
                // End of file reached
                break
            }

            // Format with line number
            let lineNo = currentLine.toString()
            result.append("${lineNo.padEnd(6)}:${line}\n")

            currentLine += 1

            // Stop if we've reached the end line
            if (endLine > 0 && currentLine > endLine) {
                break
            }
        }

        if (result.size == 0) {
            return "No lines found in specified range"
        }

        return result.toString()
    } catch (e: FSException) {
        return "Failed to read file: ${e}"
    } catch (e: Exception) {
        return "Error reading file: ${e}"
    }
    throw UnsupportedException("Unreachable")
}