package cli.utils

import std.process.*
import std.fs.Path
import std.collection.ArrayList
import std.time.*
import std.sync.*

// Timeout exception for shell command execution
public class ShellTimeoutException <: Exception {
    public init(message: String) {
        super(message)
    }
}

public class ShellUtils {
    @When[ohos == "false"]
    public static func execute(command: Array<String>, workDir!: ?Path = None): (Int64, Array<Byte>, Array<Byte>) {
        let cmdArgs = ArrayList<String>()
        if (InfoUtils.os == "windows") {
            cmdArgs.add("/c")
            cmdArgs.add(all: command)
            executeWithOutput("cmd", cmdArgs.toArray(), workingDirectory: workDir)
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

    @When[ohos == "false"]
    public static func executeWithTimeout(
        command: Array<String>,
        workDir!: ?Path = None,
        timeoutSeconds!: Int64 = 180
    ): (Int64, Array<Byte>, Array<Byte>) {
        let completed = AtomicBool(false)
        let timedOut = AtomicBool(false)

        // Execute command in separate thread
        let executionFuture: Future<(Int64, Array<Byte>, Array<Byte>)> = spawn {
            let cmdArgs = ArrayList<String>()
            if (InfoUtils.os == "windows") {
                cmdArgs.add("/c")
                cmdArgs.add(all: command)
                let result = executeWithOutput("cmd", cmdArgs.toArray(), workingDirectory: workDir)
                completed.store(true)
                return result
            } else {
                cmdArgs.add("-c")
                cmdArgs.add(all: command)
                let result = executeWithOutput("/bin/bash", cmdArgs.toArray(), workingDirectory: workDir)
                completed.store(true)
                return result
            }
        }

        // Monitor timeout in main thread
        let startTime = DateTime.now()
        while (!completed.load()) {
            let elapsed = DateTime.now() - startTime
            if (elapsed.toSeconds() > timeoutSeconds) {
                timedOut.store(true)
                executionFuture.cancel()  // Cancel the execution thread
                throw ShellTimeoutException("Command execution timeout after ${timeoutSeconds} seconds")
            }
            sleep(100 * Duration.millisecond)  // Check every 100ms
        }

        return executionFuture.get()
    }

    @When[ohos == "true"]
    public static func executeWithTimeout(
        command: Array<String>,
        workDir!: ?Path = None,
        timeoutSeconds!: Int64 = 300
    ): (Int64, Array<Byte>, Array<Byte>) {
        let completed = AtomicBool(false)
        let timedOut = AtomicBool(false)

        let executionFuture: Future<(Int64, Array<Byte>, Array<Byte>)> = spawn {
            let cmdArgs = ArrayList<String>()
            cmdArgs.add("-c")
            cmdArgs.add(all: command)
            let result = executeWithOutput("sh", cmdArgs.toArray(), workingDirectory: workDir)
            completed.store(true)
            return result
        }

        let startTime = DateTime.now()
        while (!completed.load()) {
            let elapsed = DateTime.now() - startTime
            if (elapsed.toSeconds() > timeoutSeconds) {
                timedOut.store(true)
                executionFuture.cancel()
                throw ShellTimeoutException("Command execution timeout after ${timeoutSeconds} seconds")
            }
            sleep(100 * Duration.millisecond)
        }

        return executionFuture.get()
    }
}
