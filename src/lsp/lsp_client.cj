package cli.lsp

import magic.dsl.jsonable
import magic.log.LogUtils

import cli.utils.Toml

import std.fs.File
import std.fs.Path
import std.fs.*
import std.process.*
import std.collection.*
import std.io.*
import stdx.encoding.json.*


/**
 * LSP Client for communicating with Cangjie Language Server
 */
public class LSPClient {
    private let jsonRpcClient: JSONRPCClient
    private var initialized: Bool = false
    private var capabilities: Option<ServerCapabilities> = None
    private let fileManager = FileManager()

    // Set when initialization
    // Standard LSP token types
    var tokenTypes: Array<String> = []
    // Standard LSP token modifiers
    var tokenModifiers: Array<String> = []

    public init(serverPath: String, serverArgs!: Array<String> = Array<String>()) {
        this.jsonRpcClient = JSONRPCClient(serverPath, serverArgs: serverArgs)
    }

    /**
     * Initialize the LSP connection
     */
    public func initialize(root!: String = "."): Unit {
        let rootUri = "file://${root}"
        try {
            if (this.initialized) {
                return
            }

            let initializeParams = InitializeParams(
                rootUri: rootUri,
                rootPath: root
            )
            let initJo = JsonValue.fromStr(CLIENT_INIT_VALUE).asObject()
            initJo.put(
                "initializationOptions",
                JsonObject(HashMap<String, JsonValue>([
                    (
                        "multiModuleOption",
                        JsonObject(HashMap([
                            (rootUri, this.parseMultiModuleOption(root))
                        ]))
                    )
                ]))
            )
            // Merge the Json object
            for ((key, value) in initializeParams.toJsonValue().asObject().getFields()) {
                initJo.put(key, value)
            }
            let result = this.jsonRpcClient.sendRequest("initialize", params: initJo)
            let initResult = InitializeResult.fromJsonValue(result)
            this.capabilities = Some<ServerCapabilities>(initResult.capabilities)
            this.tokenTypes = initResult.capabilities.semanticTokensProvider.legend.tokenTypes
            this.tokenModifiers = initResult.capabilities.semanticTokensProvider.legend.tokenModifiers
            this.initialized = true

            // Send initialized notification
            this.jsonRpcClient.sendNotification("initialized")

            LogUtils.info("LSP client initialized successfully")
        } catch (ex: Exception) {
            LogUtils.error("Failed to initialize LSP client: ${ex}")
            LogUtils.debug(ex)
            throw Exception("LSP initialization failed: ${ex.message}")
        }
    }

    /**
     * Parse the cjpm.toml as MultiModuleOption
     */
    private func parseMultiModuleOption(path: String): JsonValue {
        let toml = Toml("./cjpm.toml")
        MultiModuleOption(
            name: toml.get<String>("package.name"),
            package_requires: JsonObject(HashMap<String, JsonValue>([
            ])),
            requires: JsonObject(HashMap<String, JsonValue>([
            ]))
        ).toJsonValue()
    }

    /**
     * Get semantic information for a specific line
     * line is 0-based
     */
    public func getSemanticInfo(filePath: Path, line: Int64): SemanticInfoResult {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            // Open the document
            this.openDocument(filePath)

            // Get all semantic tokens for the document
            let allSemanticTokens = this.getSemanticTokens(filePath)

            // Get the actual file content to extract token text
            let content = this.fileManager.getFileContent(filePath)

            // Filter tokens for the specified line
            let filteredSemanticTokens = allSemanticTokens |>
                filter { token => token.line == line } |>
                collectArray

            // Extract token text from content
            for (token in filteredSemanticTokens) {
                token.text = this.fileManager.getFileRangeContent(
                    filePath,
                    Range(
                        start: Position(line: token.line, character: token.character),
                        end: Position(line: token.line, character: token.character + token.length)
                    )
                )
            }
            // println(allSemanticTokens.toJsonValue().toJsonString())

            sleep(Duration.second * 3)

            // Get hover info for the beginning of the line
            let hoverInfos = this.getHovers(filePath, filteredSemanticTokens)

            this.getHover(filePath, 35, 17)

            // Get document symbols
            let symbols = this.getDocumentSymbols(filePath)

            return SemanticInfoResult(
                filePath: filePath.toString(),
                line: line,
                tokens: filteredSemanticTokens,
                symbols: symbols,
                hoverInfos: hoverInfos,
                timestamp: 0
            )
        } catch (ex: Exception) {
            LogUtils.error("Failed to get semantic info for ${filePath}:${line}: ${ex}")
            LogUtils.error(ex)
            // Return empty result on error
            return SemanticInfoResult(
                filePath: filePath.toString(),
                line: line,
                tokens: [],
                symbols: [],
                timestamp: 0,
                hoverInfos: []
            )
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

    public func getHovers(filePath: Path, tokens: Array<SemanticTokenInfo>): Array<HoverInfo> {
        let hovers = ArrayList<HoverInfo>()
        for (token in tokens) {
            if (let Some(hover) <- this.getHover(filePath, token.line, token.character)) {
                if (!hover.contents.isEmpty()) {
                    hovers.add(hover)
                }
            }
        }
        return hovers.toArray()
    }

    /**
     * Get hover information at a specific position
     */
    private func getHover(filePath: Path, line: Int64, character: Int64): Option<HoverInfo> {
        try {
            if (!this.initialized) {
                throw Exception("LSP client not initialized")
            }

            let params = HoverParams(
                textDocument: TextDocumentIdentifier(
                    uri: this.pathToUri(filePath)
                ),
                position: Position(
                    line: line,
                    character: character
                )
            )

            let result = this.jsonRpcClient.sendRequest("textDocument/hover", params: (params.toJsonValue().asObject()))

            // Check if result is null (JSON null)
            // Since JsonValue doesn't have isNull(), we'll need to handle this differently
            // For now, assume the result is valid

            let hoverResult = HoverResult.fromJsonValue(result)
            var hoverContent = this.parseHoverContent(hoverResult.contents.value)
            let symbol = if (let Some(range) <- hoverResult.range) {
                this.fileManager.getFileRangeContent(filePath, range)
            } else {
                ""
            }
            return HoverInfo(
                line: line,
                character: character,
                contents: hoverContent.toString(),
                range: hoverResult.range,
                symbol: symbol
            )
        } catch (ex: Exception) {
            LogUtils.error("Failed to get hover info for ${filePath}:${line}:${character}: ${ex}")
            return None
        }
    }

    private func parseHoverContent(jsonValue: JsonValue): String {
        let hoverContent = StringBuilder()
        match (jsonValue.kind()) {
            case JsonKind.JsString =>
                hoverContent.append(jsonValue.asString().getValue())
            case JsonKind.JsObject =>
                let markedString = MarkedString.fromJsonValue(jsonValue)
                match (markedString.language) {
                    case Some(language) =>
                        // hoverContent.append("```${language}\n")
                        hoverContent.append(markedString.value)
                        // hoverContent.append("\n```\n")
                    case _ =>
                        hoverContent.append(markedString.value)
                }
            case JsonKind.JsArray =>
                let allContent = ArrayList<String>()
                for (item in jsonValue.asArray().getItems()) {
                    allContent.add(this.parseHoverContent(item))
                }
                hoverContent.append(String.join(allContent.toArray(), delimiter: " "))
            case _ => throw UnsupportedException("Unreachable")
        }
        return hoverContent.toString()
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
            if (let JsonKind.JsArray <- result.kind()) {
                return Array<DocumentSymbol>.fromJsonValue(result)
            } else {
                LogUtils.debug("Failed to get document symbols for ${filePath}: ${result}")
                return []
            }
        } catch (ex: Exception) {
            LogUtils.error("Failed to get document symbols for ${filePath}: ${ex}")
            LogUtils.error(ex)
            return Array<DocumentSymbol>()
        }
    }

    /**
     * Check if the server supports semantic tokens
     */
    public func supportsSemanticTokens(): Bool {
        match (this.capabilities) {
            case Some(_) => return true
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

        var currentLine: Int64 = 0
        var currentChar: Int64 = 0

        var i: Int64 = 0
        while (i + 4 < data.size) {
            let deltaLine = data[i]
            let deltaChar = data[i + 1]
            let length = data[i + 2]
            let tokenType = data[i + 3]
            let tokenModifiersBitmask = data[i + 4]

            currentLine += deltaLine
            if (deltaLine > 0) {
                currentChar = deltaChar
            } else {
                currentChar += deltaChar
            }

            // Decode token modifiers
            let modifiers = ArrayList<String>()
            // Check each bit position in the tokenModifiers bitmask
            for (j in 0..32) { // Assume 32 bits max for modifiers
                if ((tokenModifiersBitmask & (1 << j)) != 0) {
                    if (j < this.tokenModifiers.size) {
                        modifiers.add(this.tokenModifiers[j])
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