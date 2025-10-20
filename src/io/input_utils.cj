package cli.io

import cli.core.config.CliConfig

import magic.log.LogUtils
import magic.core.tool.ToolException

import std.collection.{map, enumerate, collectArray}
import std.time.DateTime
import std.sync.AtomicBool
import std.deriving.Derive

@Derive[ToString, Equatable]
protected enum Confirmation {
    | Approve
    | Deny
}

protected class InputUtils {
    // Global flag to coordinate between ESC checker and user input
    private static var isRequestingUserInput: AtomicBool = AtomicBool(false)

    public static func enterRawMode(): Unit {
        RawInputUtils.rawEnter()
    }

    public static func exitRawMode(): Unit {
        RawInputUtils.rawExit()
    }

    public static func buildPrompt(prompt: String): String {
        return " ${prompt} > ".withColor(Theme.MUTED)
    }

    private static let READLINE = Readline(CliConfig.readlineFile)

    public static func getUserInput(prompt!: Option<String> = None, withBox!: Bool = true): String {
        // Signal that we're requesting user input
        isRequestingUserInput.store(true)
        try {
            return READLINE.readline(prompt ?? buildPrompt("🔮"), withBox: withBox) ?? "exit"
        } finally {
            // Clear the flag when done
            isRequestingUserInput.store(false)
        }
    }

    public static func isRequestingInput(): Bool {
        return isRequestingUserInput.load()
    }

    /**
     * Check if user pressed ESC key
     */
    public static func checkEsc(): Bool {
        let VK_ESCAPE: Byte = 0x1B
        if (RawInputUtils.checkReadByte([VK_ESCAPE], infinite: false)) {
            return true
        } else {
            return false
        }
    }

    public static func confirm(title: String, content: String, footer!: Option<String> = None): Confirmation {
        PrintUtils.printTool(title, content, needConfirm: !CliConfig.auto)
        if (let Some(footer) <- footer) {
            PrintUtils.printLine(footer)
            PrintUtils.printLine("")
        }
        if (CliConfig.auto) {
            return Confirmation.Approve
        }
        // Signal that we're requesting user input
        isRequestingUserInput.store(true)
        try {
            let options = [
                "Yes, proceed",
                "Yes, allow all edits during this session",
                "No, stop",
                "Wait, input guidelines"
            ]
            match (getOptions(options)) {
                case Some(index) =>
                    if (index == 0) {
                        PrintUtils.printApproval()
                        return Confirmation.Approve
                    } else if (index == 1) {
                        PrintUtils.printApproval()
                        CliConfig.auto = true
                        return Confirmation.Approve
                    } else if (index == 2) {
                        PrintUtils.printCancellation()
                        return Confirmation.Deny
                    } else {
                        let input = getUserInput(prompt: "> ")
                        throw ToolException("User denied the tool to run with guidelines: \"${input}\".\nNOTE You must follow her/his guidelines to execute. Remember that obeying user guidelines is the most important.")
                    }
                case None => // User pressed ESC to cancel
                    PrintUtils.printCancellation()
                    return Confirmation.Deny
            }
        } finally {
            // Clear the flag when done
            isRequestingUserInput.store(false)
        }
    }

    /**
     * Allow user to select an option from a list using arrow keys
     * @param options Array of options to display
     * @param prompt Optional prompt message
     * @return Index of the selected option (0-based)
     */
    public static func getOptions(options: Array<String>, prompt!: Option<String> = None): Option<Int64> {
        if (options.isEmpty()) {
            return None
        }
        var selectedIndex = 0
        var isFirstRender = true
        // The clean auxiliary function
        let clearOptionsFn = { =>
            // prompt + #options
            let linesToClear = if (prompt.isSome()) { 1 + options.size } else { options.size }
            // Move cursor up to clear previous display
            moveCursor(linesToClear, direction: Direction.Up)
            clearScreen(mode: ClearMode.AfterCursorScreen)
        }
        while (true) {
            // Clear previous render
            if (!isFirstRender) {
                clearOptionsFn()
            }
            // Construct the options to display
            let select = selectedIndex // var variables cannot be captured by lambda
            let optionsToDisplay = options |> enumerate |> map { tuple =>
                let itemIndex = tuple[0]
                let item = tuple[1]
                if (itemIndex == select) {
                    // Highlight the selected item
                    return "◉ ${AnsiColor.BRIGHT_BLUE}${AnsiColor.BOLD}${item}${AnsiColor.RESET}"
                } else {
                    // Normal display for unselected items
                    return "○ ${AnsiColor.BRIGHT_BLACK}${item}${AnsiColor.RESET}"
                }
            } |> collectArray
            // Display prompt and options
            if (let Some(line) <- prompt) {
                PrintUtils.printLine(line.withColor(Theme.MUTED))
            }
            PrintUtils.printLine(String.join(optionsToDisplay, delimiter: "\n"))

            // Read keyboard input
            let rune = RawInputUtils.getRune()
            if (rune.isNone()) {
                return None // EOF or error
            }
            match (rune.getOrThrow()) {
                case r'\r' | r'\n' => // Enter key
                    break
                case r'\u{2191}' | r'k' => // Up ↑
                    if (selectedIndex > 0) {
                        selectedIndex -= 1
                    } else {
                        selectedIndex = options.size - 1 // Wrap to last
                    }
                case r'\u{2193}' | r'j' => // Down ↓
                    if (selectedIndex < options.size - 1) {
                        selectedIndex += 1
                    } else {
                        selectedIndex = 0 // Wrap to first
                    }
                case r'\u{1B}' => // ESC
                    selectedIndex = -1
                    break
                case _ => () // Ignore other keys
            }

            isFirstRender = false
        }
        // Clear the display before returning
        clearOptionsFn()
        if (selectedIndex == -1) {
            return None
        }
        return selectedIndex
    }
}