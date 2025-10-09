package cli.core.tools

import magic.dsl.*
import magic.prelude.*
import magic.jsonable.*
import magic.config.Config

import cli.core.tools.cj_utils.*
import cli.core.config.CliConfig
import cli.io.PrintUtils
import cli.utils.*

import std.collection.*
import stdx.encoding.json.*
import std.fs.*

protected const CANGJIE_DOC_RETRIEVE_TOOL_NAME = "retrieveCangjieDocuments"

@toolset
public class CangjieToolset {
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
        description: "An tool specialized in the Cangjie programming language, capable of retrieving Cangjie language documentation based on user queries. ",
        parameters: {
            query: "Input user query: Topics to focus documentation on (e.g., 'hooks', 'routing')"
        }
    ]
    public func retrieveCangjieDocuments(query: String): String {
        PrintUtils.printTool("Retrieve Cangjie Documents via Context7", "query: ${query}")
        let agent = CangjieContext7Agent()
        return agent.chat(query)
    }

    // @tool[
    //     description: "Retrieve Cangjie programming language development documentation with AI-powered semantic search and summarization",
    //     parameters: {
    //         query: "Development requirements or documentation content to query",
    //         numToRetrieve: "Expected number of documents to retrieve. If omitted, default value 5."
    //     }
    // ]
    // public func retrieveCangjieDocuments(query: String, numToRetrieve: Option<Int64>): String {
    //     PrintUtils.printTool("Retrieve Cangjie Documents", query)
    //     return retrieveCangjieDocumentsInternal(query, numToRetrieve)
    // }

    @tool[
        description: "Initialize a new Cangjie project in the specified directory.",
        parameters: {
            path: "Path to the Cangjie module, must be an absolute path. If omitted, the current working directory will be used to initialized.",
            projectType: "Type of the Cangjie project to initialize. If omitted, default value 'executable' will be used. Valid values are 'executable', 'static' for static library or 'dynamic' for dynamic library."
        }
    ]
    public func initCangjieProject(path: Option<String>, projectType: Option<String>): String {
        let projectDir = path.map { p => Path(p) } ?? CliConfig.cwd
        // Since Cangjie project name must be of camel case, we convert directory name to camel case
        let packageName = CangjieToolset.toCamelCase(projectDir.fileName)
        let args: Array<String> = ["init", "--name", packageName, "--type", projectType ?? "executable"]

        PrintUtils.printTool("cjpm init", projectDir.toString())
        let result = cjpmRun(args, projectDir)
        return "${result}\n\nThe root package name of the new project is: ${packageName}"
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
        return cjpmBuild(projectDir)
    }

    // @tool[
    //     description: "Compile and run an executable artifact with the specified name.",
    //     parameters: {
    //         path: "Path to the Cangjie project, must be an absolute path. If omitted, the current working directory will be used.",
    //         name: "Name of the executable artifact to run. If omitted, the default `main.exe` will be run."
    //     }
    // ]
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
