package cli.io

import magic.core.agent.{AsyncAgentResponse, AgentResponse}

import cli.utils.InfoUtils
import cli.core.config.CliConfig
import cli.core.tools.fs_utils.writeFileBasic

import std.collection.{map, enumerate, collectArray}
import std.time.DateTime
import std.process.executeWithOutput
import std.env.getVariable
import std.fs.OpenMode


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

private let printInfoSavingFilename = "print_info.txt"

protected class PrintUtils {
    static var CURRENT_INDENT = 0

    static public func beginSubAgent(): Unit {
        CURRENT_INDENT += 4
    }

    static public func endSubAgent(): Unit {
        CURRENT_INDENT -= 4
    }

    //---------------------------------------------------
    // Two fundamental print methods
    static public func printLine(line: String): Unit {
        // do not print anything if detached, but saving the print info to a file 
        if (!CliConfig.detach) {
            println(line)
        } else {
            let printInfoSavingPath = CliConfig.printInfoSavingDir.join(printInfoSavingFilename)
            writeFileBasic(printInfoSavingPath, line + '\n', mode: OpenMode.Append)
        }
    }

    static public func printString(str: String): Unit {
        // do not print anything if detached, but saving the print info to a file 
        if (!CliConfig.detach) {
            print(str, flush: true)
        } else {
            let printInfoSavingPath = CliConfig.printInfoSavingDir.join(printInfoSavingFilename)
            writeFileBasic(printInfoSavingPath, str, mode: OpenMode.Append)
        }
    }
    //---------------------------------------------------

    static public func clearScreen(): Unit {
        moveCursor(row: 0, col: 0)
        clearScreen(mode: AfterCursorScreen)
    }

    static public func printWelcome() {
        // Clear the screen first
        printLogo()
        let currentTime = DateTime.now()
        let formattedTime = currentTime.format("yyyy-MM-dd HH:mm:ss")

        PrintUtils.printLine(
            "🚦 ${THEME_MUTED}Input '${THEME_YELLOW}/help${THEME_MUTED}' to check the manual and '${THEME_YELLOW}/exit${THEME_MUTED}' to exit the program.${RESET}\n"
        )
    }

    static public func printLogo() {
        printMagicCliLogo()
    }

    static public func printExitMessage() {
        PrintUtils.printLine("\n👋 Goodbye ✨!\n".withColor(THEME_SECONDARY))
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
        PrintUtils.printLine(helpMessage)
    }

    //----------------------------------------------------------------------------------
    // The following print methods are called by tools
    //----------------------------------------------------------------------------------

    static public func printInterrupt() {
        PrintUtils.printLine(" ❗ Interrupted ...", withIndent: true)
    }

    static public func printUserConfirm() {
        PrintUtils.printLine(
            "(Enter to confirm, any other key to cancel): ".withColor(THEME_PRIMARY),
            withIndent: true
        )
    }

    static public func printApproval(): Unit {
        PrintUtils.printLine(
            "└─ 🔧 Approved to run...".withColor(THEME_MUTED),
            withIndent: true
        )
    }

    static public func printCancellation(): Unit {
        PrintUtils.printLine("└─ ✖ Cancelled...".withColor(THEME_MUTED), withIndent: true)
    }

    static public func printTool(name: String, message: String, needConfirm!: Bool = false) {
        // Whether to confirm decides the mark
        let mark = if (needConfirm) {
            " ? ".withColor(THEME_WARNING)
        } else {
            " ✔ ".withColor(THEME_SUCCESS)
        }
        let boxContent = wrapBox(
            mark + name.withColor(THEME_PRIMARY),
            content: message.withColor(THEME_INFO)
        )
        if (CURRENT_INDENT == 0) {
            PrintUtils.printLine(boxContent)
        } else {
            for ((idx, line) in enumerate(boxContent.split("\n"))) {

                let prefix = if (idx == 1) {
                    "${' ' * (CURRENT_INDENT - 2)}○ "
                } else {
                    " " * CURRENT_INDENT
                }
                PrintUtils.printLine("${prefix}${line}")
            }
        }
    }

    //----------------------------------------------------------------------------------

    static public func printAgentResponse(response: AgentResponse) {
        PrintUtils.printLine(
            wrapBox("${InputUtils.buildPrompt("🔮")}${response.content}")
        )
    }

    static public func printAgentResponse(response: AsyncAgentResponse) {
        PrintUtils.printLine(
            wrapBox("${InputUtils.buildPrompt("🔮")}${response.content}")
        )
    }

    static public func printShellResult(output: String) {
        printLine(output)
    }

    static let INDICATORS = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    static public func printWorkingIndicator(message!: String = "Working"): WorkingIndicator {
        let future = spawn {
            var idx = 0
            while (!Thread.currentThread.hasPendingCancellation) {
                let spinner = INDICATORS[idx % INDICATORS.size]
                clearScreen(mode: ClearMode.EntireLine)
                PrintUtils.printString(
                    "${spinner} ${message}...".withColor(THEME_MUTED), withIndent: true
                )
                sleep(Duration.millisecond * 100)
                idx = (idx + 1) % INDICATORS.size
            }
            clearScreen(mode: ClearMode.EntireLine)
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