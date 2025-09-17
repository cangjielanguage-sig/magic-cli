package cli.utils

import std.env.*
import stdx.net.http.*
import std.collection.*
import stdx.encoding.json.*
import std.io.*
import std.process.*
import std.fs.*
import std.time.*

import magic.config.Config
import magic.log.LogUtils

protected class ApiClient {
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
        let outReader = StringReader<InputStream>(subProcess.stdOutPipe)
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