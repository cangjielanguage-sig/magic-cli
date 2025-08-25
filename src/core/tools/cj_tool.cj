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

import cli.utils.*

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
public class CJTool{
    public CJTool(
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
        parameters: { query: "Development requirements or documentation content to query", nums_docs_to_retrive: "Expected number of documents to retrieve" }
    ]
    public func retrieveCangjieDocuments(query: String, nums_docs_to_retrive: Int64): String {
        let message = query
        PrintUtils.printTool("Retrieve Cangjie Documents", message)

        let url = "http://119.3.125.66:5384/retrieve"
        let header = HashMap<String, String>([
            ("Content-Type", "application/json")
        ])
        let requestMap = HashMap<String, JsonValue>()
        requestMap.add("query",JsonString(query))
        requestMap.add("nums_docs_to_retrive",nums_docs_to_retrive.toJsonValue())
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
        description: "Initialize a new Cangjie module in the specified directory.",
        parameters: { path: "Path to the Cangjie module, must be an absolute path" }
    ]
    public func cjpmInitModule(path: String): String {
        PrintUtils.printTool("CJPM Init Module", path)

        try {
            let cmd = "cjpm"
            let args: Array<String> = ["init"]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Project initialization successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Compile a single Cangjie file in the specified directory, generating an executable file main",
        parameters: { path: "Directory path corresponding to the Cangjie file, must be an absolute path", name: "Name of the Cangjie file to compile, e.g., test.cj" }
    ]
    public func cjCompiler(path: String, name: String): String {
        PrintUtils.printTool("CJ Compiler", path + "/" + name)

        try {
            let cmd = "cjc"
            var args: Array<String> = [name]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Compilation successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Compile the Cangjie module at the specified path. Option to choose incremental compilation for faster speed.",
        parameters: { incremental: "If true, perform incremental compilation; otherwise, perform regular full compilation.", path: "Path to the Cangjie module, must be an absolute path" }
    ]
    public func cjpmBuildModule(incremental: Bool, path: String): String {
        PrintUtils.printTool("CJPM Build Module", path)

        try {
            let cmd = "cjpm"
            var args: Array<String> = ["build"]
            if (incremental == true) {
                args = ["build", "-i"]
            }

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Compilation successful."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Compile and run an executable artifact with the specified name.",
        parameters: { name: "Name of the executable artifact to run.", path: "Path to the Cangjie module, must be an absolute path" }
    ]
    public func cjpmRun(name: String, path: String): String {
        PrintUtils.printTool("CJPM Run", path + "  --name " + name)

        try {
            let cmd = "cjpm"
            let args: Array<String> = ["run", "--name", name]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Program execution completed."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
    }

    @tool[
        description: "Clean the target directory, removing all previously built artifacts.",
        parameters: {  path: "Path to the Cangjie module, must be an absolute path" }
    ]
    public func cjpmCleanTarget(path: String): String {
        PrintUtils.printTool("CJPM Clean Target", path)

        try {
            let cmd = "cjpm"
            let args: Array<String> = ["clean"]

            eprintln("Executing command: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "Cleanup completed."
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "Error: " + errorString
            }
        } catch (e: ProcessException) {
            return "Process execution error: ${e}"
        } catch (e: Exception) {
            return "Unknown error occurred: ${e}"
        }
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
}