package cli.io

import magic.core.agent.{AsyncAgentResponse, AgentResponse}

import cli.core.plan.{ Plan, Task }
import cli.core.config.CliConfig

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

    private func printTask(task: Task, indentLevel!: Int64 = 0, indent!: Int64 = 2): Unit {
        let descriptionCombo = task.description
        var line: String = ""
        if (task.completed) {
            line = " " * indentLevel * indent + "${'╰─'.withColor(Theme.MUTED)} ${descriptionCombo.withColor(Theme.SUCCESS).withColor(AnsiColor.STRIKE_THROUGH)}"
        } else {
            line = " " * indentLevel * indent + "${'╰─'.withColor(AnsiColor.BRIGHT_BLACK)} ${descriptionCombo.withColor(AnsiColor.BOLD)}"
        }
        printLine(line)
        for (subtask in task.subtasks) {
            printTask(subtask, indentLevel: indentLevel + 1, indent: indent)
        }
    }

    public func printPlan(plan: Plan): Unit {
        PrintUtils.printLine("✨ Plan")
        for (task in plan.topLevelTasks) {
            printTask(task)
        }
    }

    public func printTool(name: String, shortMessage: String, longMessage: String, needConfirm!: Bool = false): Unit {
        let mark = if (needConfirm) {
            " ? ".withColor(Theme.WARNING)
        } else {
            " ✔ ".withColor(Theme.SUCCESS)
        }
        let title = "${mark} ${name.withColor(Theme.PRIMARY).withColor(AnsiColor.BOLD)} ${shortMessage}"
        let boxContent = if (longMessage.isEmpty()) {
            wrapBox(title, content: "")
        } else {
            wrapBox(title, content: longMessage.withColor(Theme.INFO)
            )
        }
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

    public func printToolFailure(toolInfo: String, failure!: String = "Failed ..."): Unit {
        if (currentIndent == 0) {
            printLine("○ ${toolInfo}".withColor(Theme.MUTED))
            printLine("└─ ✖ ${failure}".withColor(Theme.MUTED))
        } else {
            printLine("${' ' * (currentIndent - 2)}○ ${toolInfo}".withColor(Theme.MUTED))
            printLine("${' ' * (currentIndent - 2)}└─ ✖ ${failure}".withColor(Theme.MUTED))
        }
    }

    public func printToolResult(result: String): Unit {
        let boxContent = wrapBox(result, withBorder: false)
        for (line in boxContent.split("\n")) {
            printLine("  ${line}".withColor(Theme.current.muted), withIndent: true)
        }
        printLine("")
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
            "└─ 🔧 Approved to run...\n".withColor(Theme.MUTED),
            withIndent: true
        )
    }

    public func printCancellation(): Unit {
        printLine("└─ ✖ Cancelled...\n".withColor(Theme.MUTED), withIndent: true)
    }

    public func printInterrupt(): Unit {
        printLine(" ❗ Interrupted ...\n", withIndent: true)
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
