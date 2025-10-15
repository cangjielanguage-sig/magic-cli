package cli.io

import magic.core.agent.{AsyncAgentResponse, AgentResponse}

import cli.core.config.CliConfig
import cli.core.tools.fs_utils.writeFileBasic

import std.collection.{map, enumerate, collectArray}
import std.time.DateTime
import std.fs.OpenMode

private let printInfoSavingFilename = "print_info.txt"

protected class PrintUtils {
    //--------------------------------------------------------
    // When we enter a sub-agent, we need to indent the output
    static var CURRENT_INDENT = 0

    static public func resetSubAgent(): Unit {
        CURRENT_INDENT = 0
    }

    static public func beginSubAgent(): Unit {
        CURRENT_INDENT += 4
    }

    static public func endSubAgent(): Unit {
        CURRENT_INDENT -= 4
        if (CURRENT_INDENT < 0) {
            CURRENT_INDENT = 0
        }
    }

    //---------------------------------------------------
    // Two fundamental print methods
    static public func printLine(line: String, withIndent!: Bool = false): Unit {
        // do not print anything if non-interactive, but saving the print info to a file
        if (!CliConfig.nonInteractive) {
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
        // do not print anything if nonInteractive, but saving the print info to a file
        if (!CliConfig.nonInteractive) {
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
            mark + name.withColor(Theme.PRIMARY).withColor(AnsiColor.BOLD),
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

    static public func printToolFailure(toolInfo: String, failureInfo!: String = "Failed ...") {
        if (CURRENT_INDENT == 0) {
            PrintUtils.printLine("○ ${toolInfo}".withColor(Theme.MUTED))
            PrintUtils.printLine("└─ ✖ ${failureInfo}".withColor(Theme.MUTED))
        } else {
            PrintUtils.printLine("${' ' * (CURRENT_INDENT - 2)}○ ${toolInfo}".withColor(Theme.MUTED))
            PrintUtils.printLine("${' ' * (CURRENT_INDENT - 2)}└─ ✖ ${failureInfo}".withColor(Theme.MUTED))
        }
    }

    //----------------------------------------------------------------------------------

    static public func printAgentResponse(response: AgentResponse) {
        PrintUtils.printLine("")
        PrintUtils.printLine(
            wrapBox(renderMarkdown(response.content), withBorder: false)
        )
        PrintUtils.printLine("")
    }

    static public func printAgentResponse(response: AsyncAgentResponse) {
        PrintUtils.printLine("")
        PrintUtils.printLine(
            wrapBox(renderMarkdown(response.content), withBorder: false)
        )
        PrintUtils.printLine("")
    }

    static public func printShellResult(output: String) {
        printLine(output)
    }

    static public func printStatusIndicator(message!: String = "Working"): StatusIndicator {
        let indicator = StatusIndicator(message)
        indicator.start()
        return indicator
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