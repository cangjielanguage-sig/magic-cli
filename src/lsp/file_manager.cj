package cli.lsp

import std.collection.*
import std.io.*
import std.fs.*

public class FileManager {
    private let cache = HashMap<String, String>()
    private let lineCache = HashMap<String, Array<String>>()

    public func getFileContent(path: String): String {
        return getFileContent(Path(path))
    }

    public func getFileContent(path: Path): String {
        let pathKey = canonicalize(path).toString()
        if (this.cache.contains(pathKey)) {
            return this.cache[pathKey]
        }

        let content = readFileContent(path)
        this.cache[pathKey] = content
        return content
    }

    public func getFileRangeContent(path: Path, range: Range): String {
        let lines = this.getFileLines(path, range.start.line, range.end.line)
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

        if (startLine < 0 || endLine < 0 || startLine > endLine) {
            return []
        }

        let actualEndLine = min(lines.size, endLine)

        if (startLine > lines.size) {
            return []
        }
        return lines[(startLine)..=(actualEndLine)]
    }

    private func readFileContent(path: Path): String {
        return String.fromUtf8(File.readFrom(path))
    }
}