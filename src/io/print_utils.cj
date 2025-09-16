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
    //--------------------------------------------------------
    // When we enter a sub-agent, we need to indent the output
    static var CURRENT_INDENT = 0

    static public func beginSubAgent(): Unit {
        CURRENT_INDENT += 4
    }

    static public func endSubAgent(): Unit {
        CURRENT_INDENT -= 4
    }

    //---------------------------------------------------
    // Two fundamental print methods
    static public func printLine(line: String, withIndent!: Bool = false): Unit {
        // do not print anything if noninteractive, but saving the print info to a file 
        if (!CliConfig.noninteractive) {
            if (withIndent && CURRENT_INDENT > 0) {
                print(" " * CURRENT_INDENT)
            }
            println(line)
        } else {
            let printInfoSavingPath = CliConfig.printInfoSavingDir.join(printInfoSavingFilename)
            if (withIndent && CURRENT_INDENT > 0) {
                writeFileBasic(printInfoSavingPath, " " * CURRENT_INDENT, mode: OpenMode.Append)
            }
            writeFileBasic(printInfoSavingPath, line + '\n', mode: OpenMode.Append)
        }
    }

    static public func printString(str: String, withIndent!: Bool = false): Unit {
        // do not print anything if noninteractive, but saving the print info to a file 
        if (!CliConfig.noninteractive) {
            if (withIndent && CURRENT_INDENT > 0) {
                print(" " * CURRENT_INDENT)
            }
            print(str, flush: true)
        } else {
            let printInfoSavingPath = CliConfig.printInfoSavingDir.join(printInfoSavingFilename)
            if (withIndent && CURRENT_INDENT > 0) {
                writeFileBasic(printInfoSavingPath, " " * CURRENT_INDENT, mode: OpenMode.Append)
            }
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
            "🚦 ${Theme.MUTED}Input '${AnsiColor.YELLOW}/help${Theme.MUTED}' to check the manual and '${AnsiColor.YELLOW}/exit${Theme.MUTED}' to exit the program.${AnsiColor.RESET}\n"
        )
    }

    static public func printLogo() {
        printMagicCliLogo()
    }

    static public func printExitMessage() {
        PrintUtils.printLine("\n👋 Goodbye ✨!\n".withColor(Theme.SECONDARY))
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
            "Available Commands".withColor(Theme.PRIMARY),
            lines: HELP_INFO |>
                map { info =>
                    let cmd = "/${info[0]}".padEnd(15).withColor(AnsiColor.YELLOW)
                    let separator = " ║ ".withColor(Theme.MUTED)
                    let message = "- ${info[1]}".withColor(Theme.MUTED)
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
            "(Enter to confirm, any other key to cancel): ".withColor(Theme.PRIMARY),
            withIndent: true
        )
    }

    static public func printApproval(): Unit {
        PrintUtils.printLine(
            "└─ 🔧 Approved to run...".withColor(Theme.MUTED),
            withIndent: true
        )
    }

    static public func printCancellation(): Unit {
        PrintUtils.printLine("└─ ✖ Cancelled...".withColor(Theme.MUTED), withIndent: true)
    }

    static public func printTool(name: String, message: String, needConfirm!: Bool = false) {
        // Whether to confirm decides the mark
        let mark = if (needConfirm) {
            " ? ".withColor(Theme.WARNING)
        } else {
            " ✔ ".withColor(Theme.SUCCESS)
        }
        let boxContent = wrapBox(
            mark + name.withColor(Theme.PRIMARY),
            content: message.withColor(Theme.INFO)
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

            // Print message once (with space for spinner)
            PrintUtils.printString(
                "  ${message}...".withColor(Theme.MUTED), withIndent: true
            )

            while (!Thread.currentThread.hasPendingCancellation) {
                let spinner = INDICATORS[idx % INDICATORS.size]

                // Overwrite just the first character (spinner position)
                PrintUtils.printString("\r")
                if (CURRENT_INDENT > 0) {
                    PrintUtils.printString(" " * CURRENT_INDENT)
                }
                PrintUtils.printString("${spinner}".withColor(Theme.MUTED))

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
                        line.withBgColor(Theme.BG_SUCCESS)  // Green background for added lines
                    } else if (line.startsWith("-")) {
                        line.withBgColor(Theme.BG_ERROR)    // Red background for deleted lines
                    } else if (line.startsWith("@@")) {
                        line.withColor(Theme.MUTED)         // Muted color for hunk headers
                    } else {
                        line  // No color for context lines
                    }
                } |>
                collectArray,
            delimiter: "\n"
        )
    }
}