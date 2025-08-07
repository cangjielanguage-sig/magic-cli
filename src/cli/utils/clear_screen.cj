package cli.cli.utils

import std.process.*
import std.env.*

public func clearScreen() {
    let osName = getVariable("OS") ?? "Unknown"
    let isWindows = osName.toAsciiLower().contains("windows")
            
    let (exitCode, stdOutData, stdErrData) = if (isWindows) {
        executeWithOutput("powershell", ["-Command", "clear"])
    } else {
        executeWithOutput("/bin/bash", ["-c", "clear"])
    }
}