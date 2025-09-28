package cli.lsp

import std.fs.Path
import magic.dsl.jsonable
import magic.log.LogUtils

/**
 * Main entry point for getting semantic information from Cangjie files
 */
public func getSemanticInfo(path: Path, line: Int64, serverPath!: String = "LSPServer", serverArgs!: Array<String> = []): SemanticInfoResult {
    try {
        LogUtils.info("Getting semantic info for ${path}:${line} with server ${serverPath}")

        // Create LSP client
        let lspClient = LSPClient(serverPath, serverArgs: serverArgs)

        try {
            // Initialize LSP client
            let rootPath = path.parent
            let rootUri = rootPath.toString()
            lspClient.initialize(rootUri: "file://${rootUri}")

            // Get semantic info
            let result = lspClient.getSemanticInfo(path, line)
            LogUtils.info("Successfully retrieved semantic info for ${path}:${line}")
            return result
        } finally {
            // Always close the LSP client
            lspClient.close()
        }
    } catch (ex: Exception) {
        LogUtils.error("Failed to get semantic info for ${path}:${line}: ${ex}")
        // Return empty result on error
        return SemanticInfoResult(
            filePath: path.toString(),
            line: line,
            tokens: [],
            symbols: [],
            timestamp: 0,
            hoverInfos: []
        )
    }
}

/**
 * Get a summary of semantic information for debugging
 */
public func getSemanticInfoSummary(result: SemanticInfoResult): String {
    let summary = StringBuilder()

    summary.append("Semantic Info Summary for ${result.filePath}:${result.line}\n")
    summary.append("========================================\n")
    summary.append("Timestamp: ${result.timestamp}\n")
    summary.append("Tokens found: ${result.tokens.size}\n")

    if (!result.hoverInfos.isEmpty()) {
        summary.append("\nHovers:\n")
        summary.append("--------\n")
        for (hover in result.hoverInfos) {
            summary.append("  Hover info available at line ${hover.line}:${hover.character}\n")
        }
    }

    summary.append("Symbols found: ${result.symbols.size}\n")

    if (!result.tokens.isEmpty()) {
        summary.append("\nTokens:\n")
        summary.append("--------\n")
        for (token in result.tokens) {
            summary.append("  Line ${token.line}:${token.character} (${token.length} chars)\n")
            summary.append("  Type: ${token.tokenType}\n")
            summary.append("  Modifiers: ${String.join(token.tokenModifiers, delimiter: ", ")}\n")
            summary.append("  Text: '${token.text}'\n")
            summary.append("\n")
        }
    }

    if (!result.symbols.isEmpty()) {
        summary.append("\nSymbols:\n")
        summary.append("--------\n")
        for (symbol in result.symbols) {
            summary.append("  ${symbol.name} (${getSymbolKindName(symbol.kind)})\n")
            match (symbol.detail) {
                case Some(detail) => summary.append("  Detail: ${detail}\n")
                case _ => ()
            }
            summary.append("  Range: ${symbol.range.start.line}:${symbol.range.start.character} - ${symbol.range.end.line}:${symbol.range.end.character}\n")
            summary.append("\n")
        }
    }

    return summary.toString()
}

// Helper function to get symbol kind name
private func getSymbolKindName(kind: Int64): String {
    match (kind) {
        case 1 => "File"
        case 2 => "Module"
        case 3 => "Namespace"
        case 4 => "Package"
        case 5 => "Class"
        case 6 => "Method"
        case 7 => "Property"
        case 8 => "Field"
        case 9 => "Constructor"
        case 10 => "Enum"
        case 11 => "Interface"
        case 12 => "Function"
        case 13 => "Variable"
        case 14 => "Constant"
        case 15 => "String"
        case 16 => "Number"
        case 17 => "Boolean"
        case 18 => "Array"
        case 19 => "Object"
        case 20 => "Key"
        case 21 => "Null"
        case 22 => "EnumMember"
        case 23 => "Struct"
        case 24 => "Event"
        case 25 => "Operator"
        case 26 => "TypeParameter"
        case _ => "Unknown"
    }
}