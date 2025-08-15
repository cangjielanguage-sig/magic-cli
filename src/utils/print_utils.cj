package cli.utils

import std.time.DateTime
import std.process.executeWithOutput
import std.env.getVariable

protected class PrintUtils {
    static public func clearScreen() {
        let osName = getVariable("OS") ?? "Unknown"
        let isWindows = osName.toAsciiLower().contains("windows")

        let (exitCode, stdOutData, stdErrData) = if (isWindows) {
            executeWithOutput("powershell", ["-Command", "clear"])
        } else {
            executeWithOutput("/bin/bash", ["-c", "clear"])
        }
    }

    static public func printWelcome() {
        clearScreen()
        printLogo()
        let currentTime = DateTime.now()
        let formattedTime = currentTime.format("yyyy-MM-dd HH:mm:ss")

        let welcomeMessage = String.join(
            [
                "Welcome to Magic CLI!".withColor(THEME_SUCCESS),
                "当前时间：${formattedTime}".withColor(THEME_INFO),
                "${THEME_MUTED}输入 '${THEME_YELLOW}help${THEME_MUTED}' 查看可用命令，输入 '${THEME_YELLOW}exit${THEME_MUTED}' 退出程序。${RESET}\n"
            ],
            delimiter: "\n"
        )
        print(welcomeMessage)
    }

    static public func printLogo() {
        let banner = Banner()
        banner.printBanner()
    }

    static public func printExitMessage() {
        println("\nExiting the CLI. Goodbye!\n".withColor(THEME_SECONDARY))
    }

    static public func printHelpMessage() {
        let helpMessage = wrapBox(
            "Available Commands".withColor(THEME_PRIMARY),
            lines: [
                "${' help'.padEnd(10).withColor(THEME_YELLOW)}${' ║ - Show this help message'.withColor(THEME_MUTED)}",
                "${' clear'.padEnd(10).withColor(THEME_YELLOW)}${' ║ - Clear the screen'.withColor(THEME_MUTED)}",
                "${' exit'.padEnd(10).withColor(THEME_YELLOW)}${' ║ - Exit the CLI'.withColor(THEME_MUTED)}"
            ],
            width: 60,
            centerTitle: true
        )
        println(helpMessage)
    }

    static public func printTool(name: String, message: String) {
        let toolMessage = wrapBox(
            "   ✔  ".withColor(THEME_SUCCESS) + name.withColor(THEME_PRIMARY),
            content:  message.withColor(THEME_INFO)
        )
        println(toolMessage)
    }
}