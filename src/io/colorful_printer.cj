package cli.io

import magic.core.agent.{AsyncAgentResponse, AgentResponse}
import cli.core.config.CliConfig
import cli.core.tools.fs_utils.writeFileBasic
import std.fs.OpenMode
import std.collection.{ArrayList, enumerate, map, collectArray}
import std.time.DateTime

/**
 * ColorfulPrinter - Maintains current console output behavior with colors and box decorations
 */
protected class ColorfulPrinter <: Printer {
    private var currentIndent: Int64 = 0

    public func resetSubAgent(): Unit {
        currentIndent = 0
    }

    public func beginSubAgent(): Unit {
        currentIndent += 4
    }

    public func endSubAgent(): Unit {
        currentIndent -= 4
        if (currentIndent < 0) {
            currentIndent = 0
        }
    }

    public func printLine(line: String, withIndent!: Bool = false): Unit {
        if (withIndent && currentIndent > 0) {
            print(" " * currentIndent)
        }
        println(line)
    }

    public func printString(str: String, withIndent!: Bool = false): Unit {
        if (withIndent && currentIndent > 0) {
            print(" " * currentIndent)
        }
        print(str, flush: true)
    }

    public func printTool(name: String, message: String, needConfirm!: Bool = false): Unit {
        let mark = if (needConfirm) {
            " ? ".withColor(Theme.WARNING)
        } else {
            " ✔ ".withColor(Theme.SUCCESS)
        }
        let boxContent = wrapBox(
            mark + name.withColor(Theme.PRIMARY).withColor(AnsiColor.BOLD),
            content: message.withColor(Theme.INFO)
        )
        if (currentIndent == 0) {
            printLine(boxContent)
        } else {
            for ((idx, line) in enumerate(boxContent.split("\n"))) {
                let prefix = if (idx == 1) {
                    "${' ' * (currentIndent - 2)}○ "
                } else {
                    " " * currentIndent
                }
                printLine("${prefix}${line}")
            }
        }
    }

    public func printToolFailure(toolInfo: String, failureInfo!: String = "Failed ..."): Unit {
        if (currentIndent == 0) {
            printLine("○ ${toolInfo}".withColor(Theme.MUTED))
            printLine("└─ ✖ ${failureInfo}".withColor(Theme.MUTED))
        } else {
            printLine("${' ' * (currentIndent - 2)}○ ${toolInfo}".withColor(Theme.MUTED))
            printLine("${' ' * (currentIndent - 2)}└─ ✖ ${failureInfo}".withColor(Theme.MUTED))
        }
    }

    public func printAgentResponse(response: AgentResponse): Unit {
        printLine("")
        printLine(wrapBox(renderMarkdown(response.content), withBorder: false))
        printLine("")
    }

    public func printAgentResponse(response: AsyncAgentResponse): Unit {
        printLine("")
        printLine(wrapBox(renderMarkdown(response.content), withBorder: false))
        printLine("")
    }

    public func printShellResult(output: String): Unit {
        printLine(output)
    }

    public func printApproval(): Unit {
        printLine(
            "└─ 🔧 Approved to run...".withColor(Theme.MUTED),
            withIndent: true
        )
    }

    public func printCancellation(): Unit {
        printLine("└─ ✖ Cancelled...".withColor(Theme.MUTED), withIndent: true)
    }

    public func printInterrupt(): Unit {
        printLine(" ❗ Interrupted ...", withIndent: true)
    }

    public func printUserConfirm(): Unit {
        printLine(
            "(Enter to confirm, any other key to cancel): ".withColor(Theme.PRIMARY),
            withIndent: true
        )
    }

    public func printWelcome(): Unit {
        printLogo()
        let currentTime = DateTime.now()
        let formattedTime = currentTime.format("yyyy-MM-dd HH:mm:ss")

        printLine(
            "🚦 ${Theme.MUTED}Input '${AnsiColor.YELLOW}/help${Theme.MUTED}' to check the manual and '${AnsiColor.YELLOW}/exit${Theme.MUTED}' to exit the program.${AnsiColor.RESET}\n"
        )
    }

    public func printLogo(): Unit {
        printMagicCliLogo()
    }

    public func printExitMessage(): Unit {
        printLine("\n👋 Goodbye ✨!\n".withColor(Theme.SECONDARY))
    }

    public func renderDiff(content: String): String {
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
