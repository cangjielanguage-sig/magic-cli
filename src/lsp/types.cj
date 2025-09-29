package cli.lsp

import magic.dsl.jsonable
import magic.jsonable.*

import std.fs.Path
import stdx.encoding.json.*
import std.collection.*

/**
 * LSP Request Message - JSON-RPC 2.0 Request
 */
@jsonable
public struct LSPRequest {
    public var jsonrpc: String = "2.0"
    public var id: Int64
    public var method: String
    public var params: Option<JsonObject> = None
}

/**
 * Result of response is a JSON value; however, we cannot let JsonValue as Jsonable,
 * so, we introduce a wrap type here
 */
public struct LSPResult <: Jsonable<LSPResult> {
    public let value: JsonValue

    public init(value: JsonValue) {
        this.value = value
    }

    override public func toJsonValue(): JsonValue {
        this.value
    }

    redef public static func fromJsonValue(json: JsonValue): LSPResult {
        LSPResult(json)
    }

    redef public static func getTypeSchema(): TypeSchema {
        TypeSchema.Obj([])
    }
}

/**
 * LSP Response Message - JSON-RPC 2.0 Response
 */
@jsonable
public struct LSPResponse {
    public var jsonrpc: String = "2.0"
    public var id: Int64
    public var result: Option<LSPResult> = None
    public var error: Option<LSPError> = None
}

/**
 * LSP Error Information
 */
@jsonable
public struct LSPError {
    public var code: Int64
    public var message: String
    public var data: Option<JsonObject> = None
}

/**
 * LSP Notification Message - JSON-RPC 2.0 Notification
 */
@jsonable
public struct LSPNotification {
    public var jsonrpc: String = "2.0"
    public var method: String
    public var params: Option<JsonObject> = None
}

/**
 * LSP Position in a text document
 */
@jsonable
public struct Position {
    public var line: Int64
    public var character: Int64
}

/**
 * LSP Range in a text document
 */
@jsonable
public struct Range {
    public var start: Position
    public var end: Position
}

/**
 * LSP Text Document Identifier
 */
@jsonable
public struct TextDocumentIdentifier {
    public var uri: String
}

/**
 * LSP Text Document Item for didOpen notification
 */
@jsonable
public struct TextDocumentItem {
    public var uri: String
    public var languageId: String
    public var version: Int64
    public var text: String
}

/**
 * LSP Initialize Parameters
 */
@jsonable
public struct InitializeParams {
    public var processId: Option<Int64> = None
    public var rootUri: Option<String> = None
    public var capabilities: ClientCapabilities
    public var clientInfo: Option<ClientInfo> = None
}

/**
 * LSP Client Capabilities
 */
@jsonable
public struct ClientCapabilities {
    public var textDocument: Option<TextDocumentClientCapabilities> = None
}

/**
 * LSP Text Document Client Capabilities
 */
@jsonable
public struct TextDocumentClientCapabilities {
    public var semanticTokens: Option<SemanticTokensClientCapabilities> = None
    public var hover: Option<HoverClientCapabilities> = None
    public var documentSymbol: Option<DocumentSymbolClientCapabilities> = None
}

/**
 * LSP Semantic Tokens Client Capabilities
 */
@jsonable
public struct SemanticTokensClientCapabilities {
    public var dynamicRegistration: Bool
    public var requests: Option<SemanticTokensClientCapabilitiesRequests> = None
}

/**
 * LSP Semantic Tokens Client Capabilities Requests
 */
@jsonable
public struct SemanticTokensClientCapabilitiesRequests {
    public var full: Option<SemanticTokensFullOptions> = None
}

/**
 * LSP Semantic Tokens Full Options
 */
@jsonable
public struct SemanticTokensFullOptions {
    public var delta: Bool
}

/**
 * LSP Hover Client Capabilities
 */
@jsonable
public struct HoverClientCapabilities {
    public var dynamicRegistration: Bool
    public var contentFormat: Option<Array<String>> = None
}

/**
 * LSP Document Symbol Client Capabilities
 */
@jsonable
public struct DocumentSymbolClientCapabilities {
    public var dynamicRegistration: Bool
    public var symbolKind: Option<DocumentSymbolClientCapabilitiesSymbolKind> = None
}

/**
 * LSP Document Symbol Client Capabilities Symbol Kind
 */
@jsonable
public struct DocumentSymbolClientCapabilitiesSymbolKind {
    public var valueSet: Option<Array<Int64>> = None
}

/**
 * LSP Client Info
 */
@jsonable
public struct ClientInfo {
    public var name: String = "cj-lsp"
    public var version: Option<String> = "0.1.0"
}

/**
 * LSP Initialize Result
 */
@jsonable
public struct InitializeResult {
    public var capabilities: ServerCapabilities
}

/**
 * LSP Server Capabilities
 */
@jsonable
public struct ServerCapabilities {
    public var semanticTokensProvider: SemanticTokensServerCapabilities
    public var hoverProvider: Bool = false
    public var documentSymbolProvider: Bool = false
}

/**
 * LSP Semantic Tokens Server Capabilities
 */
@jsonable
public struct SemanticTokensServerCapabilities {
    public var legend: SemanticTokensLegend
    public var full: SemanticTokensFullOptions
    public var range: Bool
}

/**
 * LSP Semantic Tokens Legend
 */
@jsonable
public struct SemanticTokensLegend {
    public var tokenTypes: Array<String>
    public var tokenModifiers: Array<String>
}

/**
 * LSP Semantic Tokens Parameters
 */
@jsonable
public struct SemanticTokensParams {
    public var textDocument: TextDocumentIdentifier
}

/**
 * LSP Semantic Tokens Result
 */
@jsonable
public struct SemanticTokensResult {
    public var data: Array<Int64>
}

/**
 * LSP Hover Parameters
 */
@jsonable
public struct HoverParams {
    public var textDocument: TextDocumentIdentifier
    public var position: Position
    public var workDoneToken: Option<JsonObject> = None
}

/**
 * LSP Hover Result
 */
@jsonable
public struct HoverResult {
    public var contents: LSPResult
    public var range: Option<Range> = None
}

/**
 * LSP Marked String for hover content
 */
@jsonable
public struct MarkedString {
    public var language: Option<String> = None
    public var value: String
}

/**
 * LSP Document Symbol Parameters
 */
@jsonable
public struct DocumentSymbolParams {
    public var textDocument: TextDocumentIdentifier
}

/**
 * LSP Document Symbol
 */
@jsonable
public struct DocumentSymbol {
    public var name: String
    public var detail: Option<String> = None
    public var kind: Int64
    public var range: Range
    public var selectionRange: Range
    public var children: Option<Array<DocumentSymbol>> = None
}

/**
 * LSP Document Symbol Result
 */
// Array<DocumentSymbol>

/**
 * Semantic Information Result for getSemanticInfo function
 */
@jsonable
public struct SemanticInfoResult {
    public var filePath: String
    public var line: Int64
    public var tokens: Array<SemanticTokenInfo>
    public var hoverInfos: Array<HoverInfo>
    public var symbols: Array<DocumentSymbol>
    public var timestamp: Int64
}

/**
 * Individual semantic token information
 */
@jsonable
public class SemanticTokenInfo {
    public var line: Int64
    public var character: Int64
    public var length: Int64
    public var tokenType: String
    public var tokenModifiers: Array<String>
    public var text: String
}

/**
 * Hover information for a specific position
 */
@jsonable
public struct HoverInfo {
    public var line: Int64
    public var character: Int64
    public var contents: String
    public var range: Option<Range> = None
    public let symbol: String
}