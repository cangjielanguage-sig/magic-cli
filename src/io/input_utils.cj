package cli.io

import cli.core.config.CliConfig

import magic.log.LogUtils

import std.time.DateTime
import std.sync.AtomicBool

protected enum Confirmation {
    | Approve
    | Deny(String)
}

protected class InputUtils {
    // Global flag to coordinate between ESC checker and user input
    private static var isRequestingUserInput: AtomicBool = AtomicBool(false)

    public static func buildPrompt(prompt: String): String {
        return " ${prompt} > ".withColor(THEME_MUTED)
    }

    private static let READLINE = Readline(CliConfig.readlineFile)

    public static func getUserInput(prompt!: Option<String> = None, withBox!: Bool = true): String {
        // Signal that we're requesting user input
        isRequestingUserInput.store(true)
        try {
            return READLINE.readline(prompt ?? buildPrompt('🍭'), withBox: withBox) ?? "exit"
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
        try {
            RawInputUtils.rawEnter()
            if (RawInputUtils.checkReadByte([VK_ESCAPE], infinite: false)) {
                return true
            } else {
                return false
            }
        } finally {
            RawInputUtils.rawExit()
        }
    }

    public static func confirm(title: String, content: String): Confirmation {
        PrintUtils.printTool(title, content, needConfirm: !CliConfig.auto)
        if (CliConfig.auto) {
            return Confirmation.Approve
        }
        // If user deny the confirmation, we let her/him input one more message
        if (InputUtils.getConfirmation()) {
            PrintUtils.printApproval()
            return Confirmation.Approve
        } else {
            PrintUtils.printCancellation()
            return Confirmation.Deny("Cancel current operation")
        }
    }

    private static func getConfirmation(): Bool {
        PrintUtils.printUserConfirm()
        let input = getUserInput(prompt: "", withBox: false)
        // Clear the confirmation prompt line
        moveCursor(1, direction: Direction.Up)
        clearScreen(mode: ClearMode.EntireLine)
        return input.isEmpty() || input == '\n'
    }
}
