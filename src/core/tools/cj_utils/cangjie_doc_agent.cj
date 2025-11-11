package cli.core.tools.cj_utils

import magic.dsl.*
import magic.prelude.*
import magic.config.Config

import cli.core.model.CliModelManager
import cli.utils.InfoUtils
import cli.io.{PrintUtils, WithColor, AnsiColor}

private let CANGJIE_CONTEXT7_PROMPT = """
You are an intelligent assistant for the Cangjie programming language. You have access to two tools:

- `queryCangjie(query: str)`: Use this tool to search general Cangjie language documentation (e.g., syntax, core features, standard library).
- `queryCangjieStdExtension(query: str)`: Use this tool **only** to search documentation for packages in the `stdx` (Cangjie Standard Library Extension).

The `stdx` extension includes the following packages:
- `aspectCJ`: Aspect-oriented programming (AOP) capabilities.
- `compress.zlib`: Compression and decompression.
- `crypto.crypto`: Secure encryption.
- `crypto.digest`: Message digest algorithms.
- `crypto.keys`: Asymmetric encryption and signing.
- `crypto.x509`: Digital certificate handling.
- `encoding.base64`: Base64 encoding/decoding.
- `encoding.hex`: Hex encoding/decoding.
- `encoding.json`: JSON processing (String, JsonValue, DataModel conversion).
- `encoding.json.stream`: JSON stream serialization/deserialization.
- `encoding.url`: URL parsing, encoding/decoding, and path resolution.
- `fuzz.fuzz`: Coverage-guided fuzz testing engine.
- `log`: Logging functionality.
- `logger`: Text and JSON log printing.
- `net.http`: HTTP/1.1, HTTP/2, and WebSocket client/server implementation.
- `net.tls`: Secure TLS communication (server creation, handshake, encrypted data transfer).
- `serialization.serialization`: Serialization and deserialization.
- `unittest.data`: Unit testing extensions.

**Decision Rule:**
If the user's query explicitly mentions or is clearly related to **any** of the packages listed above (e.g., "How to use JSON in Cangjie?", "TLS server example", "base64 encoding"), call `queryCangjieStdExtension` with the query.

For all other queries about the Cangjie language (e.g., "How to define a function?", "What is the syntax for loops?", "General concurrency model"), call `queryCangjie`.

Do not call both tools. Choose the most appropriate one based on the content of the query.

Output: Summarize the query and the findings based solely on the retrieved content, without any personal speculation or interpretation. Cangjie is a new programming language, and any assumption you make will lead to incorrect results. This is VERY IMPORTANT!
Based on the original query, extract ONLY the most relevant information from the extracted documents.
Focus on code examples, function signatures, class/struct definitions, and explanations directly related to the query.
Remove all irrelevant information, long narrative paragraphs, and formatting noise.
The output must be concise and directly usable for code generation.
"""

@agent[
    description: "An tool specialized in the Cangjie programming language, capable of retrieving Cangjie language documentation based on user queries. Input user query: Topics to focus documentation on (e.g., 'hooks', 'routing').",
    model: CliModelManager.fastModel ?? CliModelManager.model,
    executor: "react"
]
protected class CangjieDocAgent {
    private static func startContext7(): MCPClient {
        HttpMCPClient("https://mcp.context7.com/mcp", headers: [
            (
                "CONTEXT7_API_KEY",
                Config.env["CONTEXT7_API_KEY"].getOrThrow({ =>
                    PrintUtils.printLine("CONTEXT7_API_KEY is not set. Please set the environment variable to use Cangjie documentation retrieval.".withColor(AnsiColor.color256(136)))
                    AgentCancelException(reason: "CONTEXT7_API_KEY is not set")
                })
            )
        ])
    }

    private let client = CangjieDocAgent.startContext7()
    @prompt(
        "${CANGJIE_CONTEXT7_PROMPT}"
    )

    @tool[
        description: "Queries the official Cangjie language documentation for general language features, syntax, and core standard library information.",
        parameters: {
            query: "Topic to focus documentation on (e.g., 'hooks', 'routing')."
        }
        // terminal: true
    ]
    func queryCangjie(query: String): String {
        let docs = client.callTool("get-library-docs", [
            ("context7CompatibleLibraryID", "/websites/cangjie-lang_cn-1.0.0"),
            ("topic", query),
            ("tokens", 2000)
        ])
        return docs.content
    }

    @tool[
        description: "Queries the Cangjie stdx (Standard Library Extension) documentation for specific extended packages such as JSON, TLS, logging, compression, and cryptography. Use this only when the query involves one of the stdx packages.",
        parameters: {
            query: "Topic to focus documentation on (e.g., 'hooks', 'routing')."
        }
        // terminal: true
    ]
    func queryCangjieStdExtension(query: String): String {
        let docs = client.callTool("get-library-docs", [
            ("context7CompatibleLibraryID", "/dyingchinese/cangjie-stdx"),
            ("topic", query),
            ("tokens", 2000)
        ])
        return docs.content
    }

    // @tool[
    //     description: "Queries the OpenHarmony development documentation for application development, system APIs, framework features, and platform-specific capabilities.",
    //     parameters: {
    //         query: "Topic to focus documentation on (e.g., 'ArkUI', 'ArkTS', 'application lifecycle')."
    //     },
    //     terminal: true
    // ]
    // func queryOpenHarmony(query: String): String {
    //     let docs = client.callTool("get-library-docs", [
    //         ("context7CompatibleLibraryID", "/openharmony/docs"),
    //         ("topic", query),
    //         ("tokens", 3000)
    //     ])
    //     return docs.content
    // }
}