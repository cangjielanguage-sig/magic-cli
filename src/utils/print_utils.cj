package cli.utils

import magic.core.agent.AgentResponse

import std.collection.{map, collectArray}
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
                "🚦 ${THEME_MUTED}Input '${THEME_YELLOW}/help${THEME_MUTED}' to check the manual and '${THEME_YELLOW}/exit${THEME_MUTED}' to exit the program.${RESET}\n\n"
            ],
            delimiter: "\n"
        )
        print(welcomeMessage)
    }

    static public func printLogo() {
        printMagicCliLogo()
    }

    static public func printExitMessage() {
        println("\nExiting the CLI. Goodbye!\n".withColor(THEME_SECONDARY))
    }

    static let HELP_INFO = [
        ("help",    "Show this help message"),
        ("clear",   "Clear the screen"),
        ("compact", "Compact the conversation"),
        ("mcp",     "Show loaded MCP tools"),
        ("exit",    "Exit the program")
    ]

    static public func printHelpMessage() {
        let helpMessage = wrapBox(
            "Available Commands".withColor(THEME_PRIMARY),
            lines: HELP_INFO |>
                map { info =>
                    let cmd = "/${info[0]}".padEnd(10).withColor(THEME_YELLOW)
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
            wrapBox("${InputUtils.buildPrompt("🔮 Agent")}${response.content}")
        )
    }
}