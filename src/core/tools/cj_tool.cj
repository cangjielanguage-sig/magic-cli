package cli.core.tools

import std.env.*
import stdx.net.http.*
import std.collection.ArrayList
import stdx.encoding.json.*
import std.io.*
import std.process.*

class ApiClient {
    public static func post(url: String, jsonBody: JsonValue): String {
        let client = ClientBuilder().build()
        try {
            let bodyString = jsonBody.toJsonString()

            let request = HttpRequestBuilder()
                            .method("POST")
                            .url(url)
                            .header("Content-Type", "application/json")
                            .body(bodyString)
                            .build()

            let response = client.send(request)

            if (response.status != 200) {
                let errorBody = StringReader(response.body).readToEnd()
                return "请求失败，状态码：${response.status}, 响应: ${errorBody}"
            }

            return StringReader(response.body).readToEnd()
        } catch (e: Exception) {
            return "请求异常：${e.message}"
        } finally {
            client.close()
        }
    }
}

class CJTool{
    public static func repair_code(query: String, code: String): String {
        let url = "http://119.3.125.66:5384/code_repair"
        let requestMap = HashMap<String, JsonValue>()
        requestMap.add("query",JsonString(query))
        requestMap.add("response", JsonString("```cangjie\n ${code} \n```"))
        let request = JsonObject(requestMap)
        let responseData = JsonValue.fromStr(extractLastSseData(ApiClient.post(url, request)))
        return responseData.toJsonString()
    }

    public static func retrieve_documents(query: String, nums_docs_to_retrive: Int64): String {
        let url = "http://119.3.125.66:5384/retrieve"
        let requestMap = HashMap<String, JsonValue>()
        requestMap.add("query",JsonString(query))
        requestMap.add("nums_docs_to_retrive",nums_docs_to_retrive.toJsonValue())
        let request = JsonObject(requestMap)
        let responseData = JsonValue.fromStr(ApiClient.post(url, request))
        return responseData.toJsonString()
    }

    public static func cjpm_init_module(): String {
        try {
            let cmd = "cjpm"
            let args: Array<String> = ["init"]

            eprintln("正在执行命令: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

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

    public static func cjpm_build_module(incremental: Bool): String {
        try {
            let cmd = "cjpm"
            var args: Array<String> = ["build"]
            if (incremental == true) {
                args = ["build", "-i"]
            }

            eprintln("正在执行命令: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

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

    public static func cjpm_run(name: String): String {
        try {
            let cmd = "cjpm"
            let args: Array<String> = ["run", "--name", name]

            eprintln("正在执行命令: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

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

    public static func cjpm_clean_target(): String {
        try {
            let cmd = "cjpm"
            let args: Array<String> = ["clean"]

            eprintln("正在执行命令: ${cmd} ${args}")
            let (exitCode, stdOutData, stdErrData) = executeWithOutput(cmd, args)

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

    func extractLastSseData(stream: String): String {
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