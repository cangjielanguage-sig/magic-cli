package cli.io

import magic.core.agent.{AsyncAgentResponse, AgentResponse}

import cli.core.config.CliConfig

protected class PrintUtils {
    // Printer instances - lazy initialization
    private static var _colorfulPrinter: Option<ColorfulPrinter> = None
    private static var _markdownPrinter: Option<MarkdownPrinter> = None

    // Get the appropriate printer based on the current mode
    private static func getPrinter(): Printer {
        if (CliConfig.nonInteractive) {
            // Use MarkdownPrinter for non-interactive mode (--prompt option)
            if (let Some(printer) <- _markdownPrinter) {
                return printer
            } else {
                let printer = MarkdownPrinter()
                _markdownPrinter = Some(printer)
                return printer
            }
        } else {
            // Use ColorfulPrinter for interactive mode
            if (let Some(printer) <- _colorfulPrinter) {
                return printer
            } else {
                let printer = ColorfulPrinter()
                _colorfulPrinter = Some(printer)
                return printer
            }
        }
    }

    // Reset printer instances when mode changes
    static public func resetPrinters(): Unit {
        _colorfulPrinter = None
        _markdownPrinter = None
    }

    //--------------------------------------------------------
    // Sub-agent indentation management
    static public func resetSubAgent(): Unit {
        getPrinter().resetSubAgent()
    }

    static public func beginSubAgent(): Unit {
        getPrinter().beginSubAgent()
    }

    static public func endSubAgent(): Unit {
        getPrinter().endSubAgent()
    }

    //---------------------------------------------------
    // Two fundamental print methods
    static public func printLine(line: String, withIndent!: Bool = false): Unit {
        getPrinter().printLine(line, withIndent: withIndent)
    }

    static public func printString(str: String, withIndent!: Bool = false): Unit {
        getPrinter().printString(str, withIndent: withIndent)
    }
    //---------------------------------------------------

    static public func clearScreen(): Unit {
        // Only clear screen in interactive mode
        if (!CliConfig.nonInteractive) {
            moveCursor(row: 0, col: 0)
            clearScreen(mode: AfterCursorScreen)
        }
    }

    static public func printWelcome() {
        getPrinter().printWelcome()
    }

    static public func printLogo() {
        getPrinter().printLogo()
    }

    static public func printExitMessage() {
        getPrinter().printExitMessage()
    }

    //----------------------------------------------------------------------------------
    // The following print methods are called by tools
    //----------------------------------------------------------------------------------

    static public func printInterrupt() {
        getPrinter().printInterrupt()
    }

    static public func printUserConfirm() {
        getPrinter().printUserConfirm()
    }

    static public func printApproval(): Unit {
        getPrinter().printApproval()
    }

    static public func printCancellation(): Unit {
        getPrinter().printCancellation()
    }

    static public func printTool(name: String, message: String, needConfirm!: Bool = false) {
        getPrinter().printTool(name, message, needConfirm: needConfirm)
    }

    static public func printToolFailure(toolInfo: String, failureInfo!: String = "Failed ...") {
        getPrinter().printToolFailure(toolInfo, failureInfo: failureInfo)
    }

    static public func printToolResult(result: String, maxLength!: Int64 = 200): Unit {
        let runes = result.toRuneArray()
        let truncated = if (runes.size > maxLength) {
            let truncatedRunes = runes[0..maxLength]
            "${String(truncatedRunes)}\n... [truncated ${runes.size - maxLength} chars]"
        } else {
            result
        }
        getPrinter().printToolResult(truncated)
    }

    //----------------------------------------------------------------------------------

    static public func printAgentResponse(response: AgentResponse) {
        getPrinter().printAgentResponse(response)
    }

    static public func printAgentResponse(response: AsyncAgentResponse) {
        getPrinter().printAgentResponse(response)
    }

    static public func printShellResult(output: String) {
        getPrinter().printShellResult(output)
    }

    static public func printStatusIndicator(message!: String = "Working"): StatusIndicator {
        // Status indicator only makes sense in interactive mode
        if (!CliConfig.nonInteractive) {
            let indicator = StatusIndicator(message)
            indicator.start()
            return indicator
        } else {
            // Return a dummy indicator for non-interactive mode
            return StatusIndicator(message)
        }
    }

    static public func renderDiff(content: String): String {
        return getPrinter().renderDiff(content)
    }
}