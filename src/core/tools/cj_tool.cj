package cli.core.tools

import std.env.*
import stdx.net.http.*
import std.collection.*
import stdx.encoding.json.*
import std.io.*
import std.process.*
import std.fs.*

@When[cjc_version >= "1.0.0"]
public import std.fs.{exists, removeIfExists,remove, canonicalize, rename}
@When[cjc_version >= "1.0.0"]
public import std.io.readToEnd

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.jsonable.*
import magic.log.LogUtils

class ApiClient {
    static public func post(url: String,
                               header: HashMap<String, String>,
                               body: JsonObject,
                               verify!: Bool = false): Option<String> {
        return send("POST", url, header, body, verify: verify)
    }

    static private func parseOutput(output: String): (String, String) {
        // Split the last line (status code) from the rest (response body)
        let lines = output.trimAscii().split("\n")
        let response = String.join(lines[0..(lines.size-1)], delimiter: "\n") // All lines except last
        let status = lines[lines.size-1].trimAscii()  // Last line is the status code
        return (response, status)
    }

    static private func send(method: String,
                               url: String,
                               header: HashMap<String, String>,
                               body: Option<JsonObject>,
                               verify!: Bool): Option<String> {
        logHttpInfo(method, url, header, body, async: false)
        let args = prepareCurlArgs(method, url, header, body, verify)
        let subProcess = newProcess("curl", args)
        let outReader = StringReader<InputStream>(subProcess.stdOut)
        let out = outReader.readToEnd()
        subProcess.wait(timeout: Duration.minute * 1)
        if (body.isSome() && !Config.saveModelRequest) {
            let tempPath = args[args.size-1].removePrefix("@")
            removeIfExists(tempPath)
        }
        let (resp, status) = parseOutput(out)
        LogUtils.debug("Raw http response: ${out}")
        if (status != "200" && status != "202") {
            let msg = "Http status: ${status}.\nHttp response: ${resp}"
            LogUtils.error("curl ${url} with data: ${(body ?? JsonObject()).toJsonString()} failed")
            LogUtils.error(msg)
            throw HttpException(msg)
        } else {
            return resp
        }
    }
    private static func saveTempFile(tempDir: String, content: String): Path {
        if (!exists(tempDir)) {
            Directory.create(tempDir, recursive: true)
        }
        let tempFile = File.createTemp(tempDir)
        let writer = StringWriter(tempFile)
        writer.write(content)
        writer.flush()
        tempFile.close()
        return tempFile.info.path
    }

    private static func prepareCurlArgs(method: String, url: String, header: HashMap<String, String>, body: Option<JsonObject>, verify: Bool): Array<String> {
        let args = ArrayList<String>()
        args.add("-X")
        args.add(method)
        args.add("--write-out")  // Defines a custom output format
        args.add("\n%{http_code}")
        args.add("--no-buffer")  // Disable output buffering
        args.add("--silent")     // Disables curl's default progress
        args.add("--show-error") // Show error messages (but keeps other output silent)
        args.add("--location")
        args.add("${url}")
        args.add("--noproxy")
        args.add("localhost,127.0.0.1")
        for ((k, v) in header) {
            args.add("--header")
            args.add("${k}: ${v}")
        }
        if (!verify) {
            args.add("--insecure")
        }
        if (let Some(b) <- body) {
            args.add("--data")
            let tempPath = saveTempFile(Config.modelRequestDir, b.toJsonString())
            args.add("@${tempPath}")
        }
        return args.toArray()
    }

    static func logHttpInfo(method: String, url: String, header: HashMap<String, String>, body: Option<JsonObject>, async!: Bool = false) {
        let action = if (async) {
            "async http ${method}"
        } else {
            "http ${method}"
        }
        LogUtils.debug("${action}: ${url}")
        for ((k,v) in header) {
            LogUtils.debug("header: ${k} - ${v}")
        }
        if (let Some(b) <- body) {
            LogUtils.debug("body: ${b.toString()}")
        }
    }

    protected static func newProcess(name: String, args: Array<String>, env!: Array<(String, String)> = [], redirectErr!: Bool = true): SubProcess {
        let allEnv = HashMap(getVariables())
        allEnv.add(all: env)
        if (redirectErr) {
            return launch(
                name, args,
                environment: allEnv,
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe
            )
        } else {
            return launch(
                name, args,
                environment: allEnv,
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe
            )
        }
    }
}

@agent[
    model: "ark:ep-20250208101010-dx2ph", 
    description: "一个根据用户查询，提炼和总结仓颉编程语言技术文档的AI助手。",
    executor: "naive"
]
public class DocSummaryAssistant {
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
    @tool[
        description: "根据原始需求对已生成的仓颉代码进行修复或优化",
        parameters: { query: "原始的代码生成需求", code: "需要修复或优化的代码" }
    ]
    public func repairCangjieCode(query: String, code: String): String {
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
                return "服务器返回为空,代码修复失败,请重试"
            }
            let extractedData = extractLastSseData(rawResponse)
            if (extractedData.isEmpty()) {
                return "待修复代码中没有检测到代码块"
            }
            try {
                let responseData = JsonValue.fromStr(extractedData)
                return responseData.toJsonString()
            } catch (e: Exception) {
                return "JSON解析失败: ${e.message}. 服务器原始响应: ${extractedData}"
            }
        } else {
                return "请求失败，未收到服务器响应"
        }
    }

    @tool[
        description: "获取仓颉（Cangjie）语言的开发文档",
        parameters: { query: "需要查询的开发需求或文档内容", nums_docs_to_retrive: "期望返回的文档数量" }
    ]
    public static func retrieveCangjieDocuments(query: String, nums_docs_to_retrive: Int64): String {
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
            case None => return "请求失败，未收到服务器响应"
        }
        let responseData: JsonValue
        try {
            responseData = JsonValue.fromStr(rawResponse)
        } catch (e: Exception) {
            return "JSON解析失败: ${e.message}. 服务器原始响应: ${rawResponse}"
        }
        let resultJson = match (responseData) {
            case jsonObj: JsonObject =>
                filterChunks(jsonObj).toJsonString()
            case _ =>
                responseData.toJsonString()
        }
        let docSummaryAssistant = DocSummaryAssistant()
        let promptForSummarizer = """
            Original User Query: "${query}"

            --- Retrieved Documents ---
            ${resultJson}
            --- End of Documents ---
        """
        let summary = docSummaryAssistant.chat(promptForSummarizer)
        return summary
    }

     private static func filterChunks(jsonObj: JsonObject): JsonObject {
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
        description: "在指定目录下初始化一个新的仓颉模块。",
        parameters: { path: "仓颉模块的路径，必须是绝对路径" }
    ]
    public func cjpmInitModule(path: String): String {
        try {
            let cmd = "cjpm"
            let args: Array<String> = ["init"]

            eprintln("正在执行命令: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "项目初始化成功。"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "错误: " + errorString
            }
        } catch (e: ProcessException) {
            return "进程执行错误: ${e}"
        } catch (e: Exception) {
            return "发生未知错误: ${e}"
        }
    }

    @tool[
        description: "在指定目录下编译单个Cangjie文件，生成可执行文件main",
        parameters: { path: "Cangjie文件对应目录路径，必须是绝对路径", name: "要编译的Cangjie文件名，例如test.cj" }
    ]
    public func cjCompiler(path: String, name: String): String {
        try {
            let cmd = "cjc"
            var args: Array<String> = [name]

            eprintln("正在执行命令: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "编译成功。"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "错误: " + errorString
            }
        } catch (e: ProcessException) {
            return "进程执行错误: ${e}"
        } catch (e: Exception) {
            return "发生未知错误: ${e}"
        }
    }

    @tool[
        description: "编译指定路径的Cangjie模块。可选择是否进行增量编译以加快速度。",
        parameters: { incremental: "如果为 true，则进行增量编译，否则进行常规全量编译。", path: "仓颉模块的路径，必须是绝对路径" }
    ]
    public func cjpmBuildModule(incremental: Bool, path: String): String {
        try {
            let cmd = "cjpm"
            var args: Array<String> = ["build"]
            if (incremental == true) {
                args = ["build", "-i"]
            }

            eprintln("正在执行命令: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "编译成功。"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "错误: " + errorString
            }
        } catch (e: ProcessException) {
            return "进程执行错误: ${e}"
        } catch (e: Exception) {
            return "发生未知错误: ${e}"
        }
    }

    @tool[
        description: "编译并运行一个指定名称的可执行产物。",
        parameters: { name: "要运行的可执行产物的名称。", path: "仓颉模块的路径，必须是绝对路径" }
    ]
    public func cjpmRun(name: String, path: String): String {
        try {
            let cmd = "cjpm"
            let args: Array<String> = ["run", "--name", name]

            eprintln("正在执行命令: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "程序执行完毕。"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "错误: " + errorString
            }
        } catch (e: ProcessException) {
            return "进程执行错误: ${e}"
        } catch (e: Exception) {
            return "发生未知错误: ${e}"
        }
    }

    @tool[
        description: "清理目标目录，删除所有之前构建生成的产物。",
        parameters: {  path: "仓颉模块的路径，必须是绝对路径" }
    ]
    public func cjpmCleanTarget(path: String): String {
        try {
            let cmd = "cjpm"
            let args: Array<String> = ["clean"]

            eprintln("正在执行命令: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args, workingDirectory: Path(path))

            if (exitCode == 0) {
                let outputString = String.fromUtf8(stdOutData)
                if (outputString.trimAscii().size == 0) {
                    return "清理完成。"
                } else {
                    return outputString
                }
            } else {
                let errorString = String.fromUtf8(stdErrData)
                return "错误: " + errorString
            }
        } catch (e: ProcessException) {
            return "进程执行错误: ${e}"
        } catch (e: Exception) {
            return "发生未知错误: ${e}"
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