package cli.io

import magic.core.agent.{AsyncAgentResponse, AgentResponse}
import cli.core.config.CliConfig
import std.fs.OpenMode
import std.collection.{ArrayList, enumerate, map, collectArray}
import std.time.DateTime

/**
 * MarkdownPrinter - Generates clean markdown format for file output
 * Removes ANSI colors and converts box decorations to markdown formatting
 * This printer is enabled when non-interactive mode is enabled
 */
protected class MarkdownPrinter <: Printer {
    /**
     * Non-interactive mode does not support sub-agent indentation
     */
    public func resetSubAgent(): Unit { }
    public func beginSubAgent(): Unit { }
    public func endSubAgent(): Unit { }

    public func printLine(line: String, withIndent!: Bool = false): Unit {
        let cleanLine = removeAnsiEscape(line)
        println(cleanLine)
    }

    public func printString(str: String, withIndent!: Bool = false): Unit {
        let cleanStr = removeAnsiEscape(str)
        print(cleanStr, flush: true)
    }

    public func printTool(name: String, message: String, needConfirm!: Bool = false): Unit {
        let cleanName = removeAnsiEscape(name)
        let cleanMessage = removeAnsiEscape(message)

        let markdownContent = "## Tool: ${cleanName}\n\n${cleanMessage}\n"
        printLine(markdownContent)
    }

    public func printToolFailure(toolInfo: String, failureInfo!: String = "Failed ..."): Unit {
        let cleanToolInfo = removeAnsiEscape(toolInfo)
        let cleanFailureInfo = removeAnsiEscape(failureInfo)

        printLine(cleanToolInfo)
        printLine("- ${cleanFailureInfo}")
    }

    public func printToolResult(result: String): Unit {
        let cleanResult = removeAnsiEscape(result)
        printLine("## Tool Result\n")
        printLine(cleanResult)
        printLine("")
    }

    public func printAgentResponse(response: AgentResponse): Unit {
        printLine("---\n")
        printLine("## Agent Response\n")
        printLine(response.content)
        printLine("")
    }

    public func printAgentResponse(response: AsyncAgentResponse): Unit {
        printLine("---\n")
        printLine("## Agent Response\n")
        printLine(response.content)
        printLine("")
    }

    public func printShellResult(output: String): Unit {
        printLine("```bash")
        printLine(output)
        printLine("```")
    }

    public func printApproval(): Unit {
        throw UnsupportedException("Approval is not supported in markdown printer")
    }

    public func printCancellation(): Unit {
        throw UnsupportedException("Cancellation is not supported in markdown printer")
    }

    public func printInterrupt(): Unit {
        throw UnsupportedException("Interrupt is not supported in markdown printer")
    }

    public func printUserConfirm(): Unit {
        throw UnsupportedException("User confirm is not supported in markdown printer")
    }

    public func printWelcome(): Unit {
        throw UnsupportedException("Welcome is not supported in markdown printer")
    }

    public func printLogo(): Unit {
        throw UnsupportedException("Logo is not supported in markdown printer")
    }

    public func printExitMessage(): Unit {
        throw UnsupportedException("Exit message is not supported in markdown printer")
    }

    public func renderDiff(content: String): String {
        let lines = content.split("\n")
        let result = ArrayList<String>()

        for (line in lines) {
            if (line.startsWith("+")) {
                result.add("+${removeAnsiEscape(line[1..])}")  // Keep + prefix for markdown diff
            } else if (line.startsWith("-")) {
                result.add("-${removeAnsiEscape(line[1..])}")  // Keep - prefix for markdown diff
            } else if (line.startsWith("@@")) {
                result.add(removeAnsiEscape(line))  // Remove colors but keep format
            } else {
                result.add(" ${removeAnsiEscape(line)}")  // Add space for context lines
            }
        }

        return String.join(result.toArray(), delimiter: "\n")
    }
}