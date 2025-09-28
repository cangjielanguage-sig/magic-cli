package cli.lsp

import std.collection.*
import std.io.*
import std.fs.*

public class FileManager {
    private let cache = HashMap<String, String>()
    private let lineCache = HashMap<String, Array<String>>()

    public func getFileContent(path: String): String {
        if (this.cache.contains(path)) {
            return this.cache[path]
        }

        let content = readFileContent(path)
        this.cache[path] = content
        return content
    }

    public func getFileRangeContent(path: Path, range: Range): String {
        let lines = this.getFileLines(path, range.start.line+1, range.end.line+1) // Convert to 1-based
        if (lines.size == 1) {
            return lines[0][range.start.character..range.end.character]
        }
        let strBuilder = StringBuilder(lines[0][range.start.character..]) // Add the first line
        for (i in 1..lines.size-1) {
            strBuilder.append("\n${lines[i]}\n") // Add middle lines
        }
        strBuilder.append(lines[lines.size-1][0..range.end.character]) // Add the last line
        return strBuilder.toString()
    }

    public func getFileLines(path: Path, startLine: Int64, endLine: Int64): Array<String> {
        let pathKey = canonicalize(path).toString()
        let lines = if (this.lineCache.contains(pathKey)) {
            this.lineCache[pathKey]
        } else {
            let lines = this.getFileContent(pathKey).split("\n")
            this.lineCache.add(pathKey, lines)
            lines
        }

        if (startLine < 1 || endLine < 1 || startLine > endLine) {
            return []
        }

        let actualEndLine = min(lines.size, endLine)

        if (startLine > lines.size) {
            return []
        }
        return lines[(startLine-1)..=(actualEndLine-1)]
    }

    private func readFileContent(path: String): String {
        return String.fromUtf8(File.readFrom(path))
    }
}