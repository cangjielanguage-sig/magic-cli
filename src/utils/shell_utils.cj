package cli.utils

import std.process.*
import std.fs.Path
import std.collection.ArrayList

public class TerminalUtils {
    @When[ohos == "false"]
    public static func execute(command: Array<String>, workDir!: ?Path = None): (Int64, Array<Byte>, Array<Byte>) {
        let cmdArgs = ArrayList<String>()
        if (InfoUtils.os == "windows") {
            cmdArgs.add("-Command")
            cmdArgs.add(all: command)
            executeWithOutput("powershell", cmdArgs.toArray(), workingDirectory: workDir)
        } else {
            cmdArgs.add("-c")
            cmdArgs.add(all: command)
            executeWithOutput("/bin/bash", cmdArgs.toArray(), workingDirectory: workDir)
        }
    }

    @When[ohos == "true"]
    public static func execute(command: Array<String>, workDir!: ?Path = None): (Int64, Array<Byte>, Array<Byte>) {
        let cmdArgs = ArrayList<String>()
        cmdArgs.add("-c")
        cmdArgs.add(all: command)
        executeWithOutput("sh", cmdArgs.toArray(), workingDirectory: workDir)
    }
}
