package cli.lsp

import std.fs.File
import std.fs.Path
import std.fs.*
import std.process.*
import std.collection.*
import std.io.*
import stdx.encoding.json.*
import magic.dsl.jsonable
import magic.log.LogUtils

/**
 * LSP Client for communicating with Cangjie Language Server
 */
public class LSPClient {
    private let jsonRpcClient: JSONRPCClient
    private var initialized: Bool = false
    private var capabilities: Option<ServerCapabilities> = None

    public init(serverPath: String, serverArgs!: Array<String> = Array<String>()) {
        this.jsonRpcClient = JSONRPCClient(serverPath, serverArgs: serverArgs)
    }

    /**
     * Initialize the LSP connection
     */
    public func initialize(rootUri!: String = "file:///"): Unit {
        try {
            if (this.initialized) {
                return
            }

            let initializeParams = InitializeParams(
                capabilities: ClientCapabilities(
                    textDocument: TextDocumentClientCapabilities(
                        semanticTokens: SemanticTokensClientCapabilities(
                            dynamicRegistration: true,
                            requests: SemanticTokensClientCapabilitiesRequests(
                                full: SemanticTokensFullOptions(delta: false)
                            )
                        )
                        ,
                        hover: HoverClientCapabilities(
                            dynamicRegistration: true,
                            contentFormat: ["markdown", "plaintext"]
                        ),
                        documentSymbol: DocumentSymbolClientCapabilities(
                            dynamicRegistration: true
                        )
                    )
                ),
                processId: 0,
                rootUri: rootUri,
                clientInfo: ClientInfo()
            )
            let result = this.jsonRpcClient.sendRequest("initialize", params: (initializeParams.toJsonValue().asObject()))
            let initResult = InitializeResult.fromJsonValue(result)
            this.capabilities = Some<ServerCapabilities>(initResult.capabilities)
            this.initialized = true

            // Send initialized notification
            this.jsonRpcClient.sendNotification("initialized")

            LogUtils.info("LSP client initialized successfully")
        } catch (ex: Exception) {
            LogUtils.error("Failed to initialize LSP client: ${ex}")
            LogUtils.debug(ex)
            for (ste in ex.getStackTrace()) {
                println("${ste.fileName}:${ste.lineNumber} ${ste.methodName}")
            }
            println("SSS")
            throw Exception("LSP initialization failed: ${ex.message}")
        }
    }

    /**
     * Open a text document in the LSP server
     */
    public func openDocument(filePath: Path): Unit {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            let content = try {
                let file = File(filePath, OpenMode.Read)
                let reader = StringReader<File>(file)
                reader.readToEnd()
            } catch (ex: Exception) {
                throw Exception("Failed to read file: ${ex.message}")
            }
            let textDocument = TextDocumentItem(
                uri: this.pathToUri(filePath),
                languageId: "Cangjie",
                version: 1,
                text: content
            )

            // Create params object directly without HashMap conversion
            let jo = JsonObject()
            jo.put("textDocument", textDocument.toJsonValue())

            this.jsonRpcClient.sendNotification("textDocument/didOpen", params: jo)
            LogUtils.info("Opened document: ${filePath}")
        } catch (ex: Exception) {
            LogUtils.error("Failed to open document ${filePath}: ${ex}")
            throw Exception("Failed to open document: ${ex.message}")
        }
    }

    /**
     * Get semantic tokens for a document
     */
    public func getSemanticTokens(filePath: Path): Array<SemanticTokenInfo> {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            let params = SemanticTokensParams(
                textDocument: TextDocumentIdentifier(
                    uri: this.pathToUri(filePath)
                )
            )

            let result = this.jsonRpcClient.sendRequest("textDocument/semanticTokens/full", params: params.toJsonValue().asObject())
            let semanticTokens = SemanticTokensResult.fromJsonValue(result)

            return this.decodeSemanticTokens(semanticTokens.data)
        } catch (ex: Exception) {
            LogUtils.error("Failed to get semantic tokens for ${filePath}: ${ex}")
            return Array<SemanticTokenInfo>()
        }
    }

    /**
     * Get hover information at a specific position
     */
    public func getHover(filePath: Path, line: Int64, character: Int64): Option<HoverInfo> {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            let params = HoverParams(
                textDocument: TextDocumentIdentifier(
                    uri: this.pathToUri(filePath)
                ),
                position: Position(line: line, character: character)
            )

            let result = this.jsonRpcClient.sendRequest("textDocument/hover", params: (params.toJsonValue().asObject()))

            // Check if result is null (JSON null)
            // Since JsonValue doesn't have isNull(), we'll need to handle this differently
            // For now, assume the result is valid

            let hoverResult = HoverResult.fromJsonValue(result)
            var hoverContent = StringBuilder()

            for (markedString in hoverResult.contents) {
                match (markedString.language) {
                    case Some(language) =>
                        hoverContent.append("```${language}\n")
                        hoverContent.append(markedString.value)
                        hoverContent.append("\n```\n")
                    case _ =>
                        hoverContent.append(markedString.value)
                }
            }

            return HoverInfo(
                line: line,
                character: character,
                contents: hoverContent.toString(),
                range: hoverResult.range
            )
        } catch (ex: Exception) {
            LogUtils.error("Failed to get hover info for ${filePath}:${line}:${character}: ${ex}")
            return None
        }
    }

    /**
     * Get document symbols
     */
    public func getDocumentSymbols(filePath: Path): Array<DocumentSymbol> {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            let params = DocumentSymbolParams(
                textDocument: TextDocumentIdentifier(
                    uri: this.pathToUri(filePath)
                )
            )

            let result = this.jsonRpcClient.sendRequest("textDocument/documentSymbol", params: (params.toJsonValue().asObject()))
            return Array<DocumentSymbol>.fromJsonValue(result)
        } catch (ex: Exception) {
            LogUtils.error("Failed to get document symbols for ${filePath}: ${ex}")
            return Array<DocumentSymbol>()
        }
    }

    /**
     * Get semantic information for a specific line
     */
    public func getSemanticInfo(filePath: Path, line: Int64): SemanticInfoResult {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            // Open the document
            this.openDocument(filePath)

            // Get all semantic tokens for the document
            let allTokens = this.getSemanticTokens(filePath)

            // Filter tokens for the specified line
            let lineTokens = ArrayList<SemanticTokenInfo>()
            for (token in allTokens) {
                if (token.line == line) {
                    lineTokens.add(token)
                }
            }
            let lineTokensArray = lineTokens.toArray()

            // Get hover info for the beginning of the line
            let hoverInfo = this.getHover(filePath, line, 0)

            // Get document symbols
            let symbols = this.getDocumentSymbols(filePath)

            // Get the actual file content to extract token text
            let content = try {
                let file = File(filePath, OpenMode.Read)
                let reader = StringReader<File>(file)
                reader.readToEnd()
            } catch (ex: Exception) {
                LogUtils.error("Failed to read file content for ${filePath}: ${ex}")
                ""
            }

            // Extract token text from content
            let tokensWithText = this.extractTokenText(lineTokensArray, content)

            return SemanticInfoResult(
                filePath: filePath.toString(),
                line: line,
                tokens: tokensWithText,
                symbols: symbols,
                hoverInfo: hoverInfo,
                timestamp: 0
            )
        } catch (ex: Exception) {
            LogUtils.error("Failed to get semantic info for ${filePath}:${line}: ${ex}")
            // Return empty result on error
            return SemanticInfoResult(
                filePath: filePath.toString(),
                line: line,
                tokens: [],
                symbols: [],
                timestamp: 0,
                hoverInfo: None
            )
        }
    }

    /**
     * Check if the server supports semantic tokens
     */
    public func supportsSemanticTokens(): Bool {
        match (this.capabilities) {
            case Some(caps) => match (caps.semanticTokensProvider) {
                case Some(_) => true
                case _ => false
            }
            case _ => false
        }
    }

    /**
     * Check if the server supports hover
     */
    public func supportsHover(): Bool {
        match (this.capabilities) {
            case Some(caps) => caps.hoverProvider
            case _ => false
        }
    }

    /**
     * Get server capabilities
     */
    public func getCapabilities(): ServerCapabilities {
        match (this.capabilities) {
            case Some(caps) => caps
            case _ => ServerCapabilities()
        }
    }

    /**
     * Close the LSP connection
     */
    public func close(): Unit {
        this.jsonRpcClient.close()
        this.initialized = false
        this.capabilities = None<ServerCapabilities>
    }

    // Helper methods

    private func pathToUri(path: Path): String {
        return "file://${path.toString()}"
    }

    private func decodeSemanticTokens(data: Array<Int64>): Array<SemanticTokenInfo> {
        let tokens = ArrayList<SemanticTokenInfo>()

        if (data.size < 5) {
            return tokens.toArray()
        }

        // Standard LSP token types
        let tokenTypes = [
            "namespace", "type", "class", "enum", "interface", "struct",
            "typeParameter", "parameter", "variable", "property", "enumMember",
            "function", "method", "macro", "keyword", "modifier", "comment",
            "string", "number", "regexp", "operator", "decorator"
        ]

        // Standard LSP token modifiers
        let tokenModifiersArray = [
            "declaration", "definition", "readonly", "static", "deprecated",
            "abstract", "async", "modification", "documentation", "defaultLibrary"
        ]

        var currentLine: Int64 = 0
        var currentChar: Int64 = 0

        var i: Int64 = 0
        while (i < data.size) {
            if (i + 4 >= data.size) {
                break
            }

            let deltaLine = data[i]
            let deltaChar = data[i + 1]
            let length = data[i + 2]
            let tokenType = data[i + 3]
            let tokenModifiersBitmask = data[i + 4]

            if (deltaLine > 0) {
                currentLine += deltaLine
                currentChar = deltaChar
            } else {
                currentChar += deltaChar
            }

            // Decode token modifiers
            let modifiers = ArrayList<String>()
            // Check each bit position in the tokenModifiers bitmask
            for (j in 0..32) { // Assume 32 bits max for modifiers
                if ((tokenModifiersBitmask & (1 << j)) != 0) {
                    if (j < tokenModifiersArray.size) {
                        modifiers.add(tokenModifiersArray[j])
                    }
                }
            }

            tokens.add(SemanticTokenInfo(
                line: currentLine,
                character: currentChar,
                length: length,
                tokenType: if (tokenType < tokenTypes.size) { tokenTypes[tokenType] } else { "unknown" },
                tokenModifiers: modifiers.toArray(),
                text: "" // Will be filled later
            ))

            i += 5
        }

        return tokens.toArray()
    }

    private func extractTokenText(tokens: Array<SemanticTokenInfo>, content: String): Array<SemanticTokenInfo> {
        let lines = content.split("\n")
        let tokensWithText = ArrayList<SemanticTokenInfo>()

        for (token in tokens) {
            var text = ""
            if (token.line < lines.size) {
                let line = lines[token.line]
                let start = if (token.character < line.size) { token.character } else { line.size }
                let end = if (start + token.length <= line.size) { start + token.length } else { line.size }
                text = if (end > line.size) { line[start..] } else { line[start..end] }
            }

            tokensWithText.add(SemanticTokenInfo(
                line: token.line,
                character: token.character,
                length: token.length,
                tokenType: token.tokenType,
                tokenModifiers: token.tokenModifiers,
                text: text
            ))
        }

        return tokensWithText.toArray()
    }
}