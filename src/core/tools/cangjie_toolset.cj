package cli.core.tools

import std.env.*
import std.collection.*
import stdx.encoding.json.*
import std.io.*
import std.process.*
import std.fs.*

import magic.dsl.*
import magic.prelude.*
import magic.jsonable.*

import cli.core.config.CliConfig
import cli.utils.*
import cli.core.tools.cjpm_utils.*

@agent[
    executor: "naive"
]
private class DocSummaryAssistant {
    @prompt("""
        You are an expert programming assistant.
        Your task is to distill technical documentation for another AI agent that will write Cangjie code.
        Based on the user's original query, extract ONLY the most relevant information from the provided documents.
        Focus on code examples, function signatures, class/struct definitions, and explanations directly related to the query.
        Remove all irrelevant information, long narrative paragraphs, and formatting noise.
        The output must be concise and directly usable for code generation.
    """)
}

@toolset
public class CangjieToolset {
    public CangjieToolset(
        private let model: ChatModel
    ) { }

    // @tool[
    //     description: "Repair or optimize generated Cangjie code based on original requirements",
    //     parameters: { query: "Original code generation requirements", code: "Code that needs to be repaired or optimized" }
    // ]
    public func repairCangjieCode(query: String, code: String): String {
        let message = query
        PrintUtils.printTool("Repair Cangjie Code", message)

        let url = "http://119.3.125.66:5384/code_repair"
        let header = HashMap<String, String>([
            ("Content-Type", "application/json")
        ])

        let requestMap = HashMap<String, JsonValue>()
        let codeBlock = "```cangjie \n${code}\n```"
        requestMap.add("query", JsonString(query))
        requestMap.add("response", JsonString(codeBlock))
        let requestBody = JsonObject(requestMap)

        let rawResponseOpt = ApiClient.post(url, header, requestBody)
        if (let Some(rawResponse) <- rawResponseOpt) {
            if (rawResponse.isEmpty()) {
                return "Server returned empty response, code repair failed, please retry"
            }
            let extractedData = extractLastSseData(rawResponse)
            if (extractedData.isEmpty()) {
                return "No code blocks detected in the code to be repaired"
            }
            try {
                let responseData = JsonValue.fromStr(extractedData)
                return responseData.toJsonString()
            } catch (e: Exception) {
                return "JSON parsing failed: ${e.message}. Server raw response: ${extractedData}"
            }
        } else {
                return "Request failed, no server response received"
        }
    }

    @tool[
        description: "Retrieve Cangjie programming language development documentation with AI-powered semantic search and summarization",
        parameters: {
            query: "Development requirements or documentation content to query",
            numToRetrieve: "Expected number of documents to retrieve. If omitted, default value 5."
        }
    ]
    public func retrieveCangjieDocuments(query: String, numToRetrieve: Option<Int64>): String {
        let message = query
        PrintUtils.printTool("Retrieve Cangjie Documents", message)

        let url = "http://119.3.125.66:5384/retrieve"
        let header = HashMap<String, String>([
            ("Content-Type", "application/json")
        ])
        let requestMap = HashMap<String, JsonValue>()
        requestMap.add("query",JsonString(query))
        requestMap.add("nums_docs_to_retrive", (numToRetrieve ?? 5).toJsonValue())
        let requestBody = JsonObject(requestMap)
        let rawResponseOpt = ApiClient.post(url, header, requestBody)
        let rawResponse = match (rawResponseOpt) {
            case Some(resp) => resp
            case None => return "Request failed, no server response received"
        }
        let responseData: JsonValue
        try {
            responseData = JsonValue.fromStr(rawResponse)
        } catch (e: Exception) {
            return "JSON parsing failed: ${e.message}. Server raw response: ${rawResponse}"
        }
        let resultJson = match (responseData) {
            case jsonObj: JsonObject =>
                filterChunks(jsonObj).toJsonString()
            case _ =>
                responseData.toJsonString()
        }
        let docSummaryAssistant = DocSummaryAssistant()
        docSummaryAssistant.model = this.model
        let promptForSummarizer = """
            Original User Query: "${query}"

            --- Retrieved Documents ---
            ${resultJson}
            --- End of Documents ---
        """
        let summary = docSummaryAssistant.chat(promptForSummarizer)
        return summary
    }

    private func filterChunks(jsonObj: JsonObject): JsonObject {
        let filteredChunks = ArrayList<JsonValue>()

        if (let Some(docsValue) <- jsonObj.get("docs")) {
            let chunksArrays = docsValue as JsonArray

            if (let Some(chunksArray) <- chunksArrays) {
                for (i in 0..chunksArray.size()) {
                    let chunk = chunksArray[i]
                    match (chunk) {
                        case jsonStr: JsonString =>
                            if (jsonStr.getValue().contains("```cangjie")) {
                                filteredChunks.add(chunk)
                            }
                        case _ =>
                            ()
                    }
                }
            }
        }

        let resultMap = HashMap<String, JsonValue>()
        resultMap.add("docs", JsonArray(filteredChunks))
        return JsonObject(resultMap)
    }

    @tool[
        description: "Initialize a new Cangjie project in the specified directory.",
        parameters: { path: "Path to the Cangjie module, must be an absolute path. If omitted, the current working directory will be used to initialized." }
    ]
    public func initCangjieProject(path: Option<String>): String {
        let projectDir = path.map { p => Path(p) } ?? CliConfig.cwd
        // Since Cangjie project name must be of camel case, we convert directory name to camel case
        let packageName = CangjieToolset.toCamelCase(projectDir.fileName)
        let args: Array<String> = ["init", "--name", packageName]

        PrintUtils.printTool("cjpm init", projectDir.toString())
        return cjpmRun(args, projectDir)
    }

    @tool[
        description: "Compile a single Cangjie file in the specified directory, generating an executable file main",
        parameters: {
            path: "Path to the Cangjie file to be compile, must be an absolute path"
        }
    ]
    public func compileCangjieFile(path: String): String {
        let filePath = Path(path)

        PrintUtils.printTool("cjc compile", path)
        return cjcRun([filePath.fileName], filePath.parent)
    }

    @tool[
        description: "Compile the Cangjie module at the specified path. Option to choose incremental compilation for faster speed.",
        parameters: {
            path: "Path to the Cangjie module, must be an absolute path. If omitted, the current working directory will be used."
        }
    ]
    public func buildCangjieProject(path: Option<String>): String {
        let projectDir = path.map { p => Path(p) } ?? CliConfig.cwd

        PrintUtils.printTool("cjpm build", projectDir.toString())
        return cjpmRun(["build", "-i"], projectDir)
    }

    @tool[
        description: "Compile and run an executable artifact with the specified name.",
        parameters: {
            path: "Path to the Cangjie project, must be an absolute path. If omitted, the current working directory will be used.",
            name: "Name of the executable artifact to run. If omitted, the default `main.exe` will be run."
        }
    ]
    public func runCangjieProject(path: Option<String>, name: Option<String>): String {
        let projectDir = path.map { p => Path(p) } ?? CliConfig.cwd
        let execName = name ?? "main"

        let args: Array<String> = ["run", "--name", execName]
        PrintUtils.printTool("cjpm run", projectDir.toString() + "  --name ${execName}")
        return cjpmRun(args, projectDir)
    }

    @tool[
        description: "Clean the target directory, removing all previously built artifacts.",
        parameters: {
            path: "Path to the Cangjie project, must be an absolute path. If omitted, the current working directory will be used."
        }
    ]
    public func cleanCangjieProject(path: Option<String>): String {
        let projectDir = path.map { p => Path(p) } ?? CliConfig.cwd
        PrintUtils.printTool("cjpm clean", projectDir.toString())
        return cjpmRun(["clean"], projectDir)
    }

    static func extractLastSseData(stream: String): String {
        let lines = stream.split('\n')
        var lastJsonData = ""

        for (line in lines) {
            if (line.startsWith("data: ")) {
                lastJsonData = line[6..]
            }
        }
        return lastJsonData
    }

    private static func toCamelCase(dirName: String): String {
        let normalized = dirName.replace("-", " ").replace("_", " ")
        let words = normalized.split(' ')
        let result = StringBuilder()

        for (i in 0..words.size) {
            let word = words[i].trimAscii()
            if (!word.isEmpty()) {
                if (result.size == 0) { // The first word
                    result.append(word.toAsciiLower())
                } else { // other words
                    result.append(word.toAsciiTitle())
                }
            }
        }
        return result.toString()
    }
}