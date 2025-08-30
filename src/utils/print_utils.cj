package cli.utils

import magic.core.agent.AgentResponse

import std.collection.{map, collectArray}
import std.time.DateTime
import std.process.executeWithOutput
import std.env.getVariable

/**
 * The working indicator is printed by another thread
 * We need a data structure to hold the thread future and stop the thread
 */
protected class WorkingIndicator {
    WorkingIndicator(
        private let future: Future<Unit>
    ) { }

    protected func stop(): Unit {
        future.cancel()
        future.get()
    }
}

protected class PrintUtils {
    static public func clearScreen() {
        let (exitCode, stdOutData, stdErrData) = if (InfoUtils.os == "windows") {
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

        print(
            "🚦 ${THEME_MUTED}Input '${THEME_YELLOW}/help${THEME_MUTED}' to check the manual and '${THEME_YELLOW}/exit${THEME_MUTED}' to exit the program.${RESET}\n\n",
            flush: true
        )
    }

    static public func printLogo() {
        printMagicCliLogo()
    }

    static public func printExitMessage() {
        println("\n👋 Goodbye ✨!\n".withColor(THEME_SECONDARY))
    }

    static let HELP_INFO = [
        ("help",         "Show this help message"),
        ("clear",        "Clear conversation history"),
        ("compact",      "Compact the conversation"),
        ("conversation", "Manage conversations"),
        ("mcp",          "Show loaded MCP tools"),
        ("memory",       "Show MAGIC.md content"),
        ("cmd",          "Manage custom commands"),
        ("init",         "Initialize MAGIC.md for project"),
        ("exit",         "Exit the program")
    ]

    static public func printHelpMessage() {
        let helpMessage = wrapBox(
            "Available Commands".withColor(THEME_PRIMARY),
            lines: HELP_INFO |>
                map { info =>
                    let cmd = "/${info[0]}".padEnd(15).withColor(THEME_YELLOW)
                    let separator = " ║ ".withColor(THEME_MUTED)
                    let message = "- ${info[1]}".withColor(THEME_MUTED)
                    " ${cmd}${separator}${message}"
                } |>
                collectArray,
            width: 60,
            centerTitle: true
        )
        println(helpMessage)
    }

    static public func printTool(name: String, message: String) {
        let toolMessage = wrapBox(
            " ✔  ".withColor(THEME_SUCCESS) + name.withColor(THEME_PRIMARY),
            content: message.withColor(THEME_INFO)
        )
        println(toolMessage)
    }

    static public func printAgentResponse(response: AgentResponse) {
        println(
            wrapBox("${InputUtils.buildPrompt("🔮")}${response.content}")
        )
    }

    static public func printTerminalResponse(output: String) {
        print(output + '\r')
    }

    static let INDICATORS = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    static public func printWorkingIndicator(message!: String = "Working"): WorkingIndicator {
        clearScreen(EntireLine)
        let future = spawn {
            var idx = 0
            while (!Thread.currentThread.hasPendingCancellation) {
                let spinner = INDICATORS[idx % INDICATORS.size]
                print("\r${spinner} ${message}...".withColor(THEME_MUTED), flush: true)
                sleep(Duration.millisecond * 100)
                idx = (idx + 1) % INDICATORS.size
            }
            clearScreen(EntireLine)
        }
        return WorkingIndicator(future)
    }

    static public func renderDiff(content: String): String {
        return String.join(
            content.split("\n") |>
                map { line =>
                    // Add background colors to diff lines
                    if (line.startsWith("+")) {
                        line.withBgColor(THEME_BG_SUCCESS)  // Green background for added lines
                    } else if (line.startsWith("-")) {
                        line.withBgColor(THEME_BG_ERROR)    // Red background for deleted lines
                    } else if (line.startsWith("@@")) {
                        line.withColor(THEME_MUTED)         // Muted color for hunk headers
                    } else {
                        line  // No color for context lines
                    }
                } |>
                collectArray,
            delimiter: "\n"
        )
    }
}