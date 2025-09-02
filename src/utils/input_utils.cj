package cli.utils

import cli.core.config.CliConfig
import std.time.DateTime
import cli.context.*
import magic.log.LogUtils
protected enum Confirmation {
    | Approve
    | Deny(String)
}

protected class InputUtils {
    public static func buildPrompt(prompt: String): String {
        return " ${prompt} > ".withColor(THEME_MUTED)
    }

    private static let READLINE = Readline(CliConfig.readlineFile)

    public static func getUserInput(withBox!: Bool = true, mode!: CliMode = AGENTIC): String {
        match (mode) {
            case AGENTIC =>
                READLINE.readline(buildPrompt('🍭'), withBox: withBox) ?? "exit"
            case TERMINAL =>
                READLINE.readline(buildPrompt('💻'), withBox: withBox) ?? "exit"
            case CHATTING => checkEsc()
            case _ => checkEnter() // CONFIRM MODE

        }
    }

    private static func checkEsc(): String {
        ByteChecker.checkEsc() ?? ""
    }

    private static func checkEnter(): String {
        let context = getContext()
        let thread = Thread.currentThread
        if (thread.id != context.workingThread) {
            return ""
        }
        ByteChecker.checkEnter(infinite:true) ?? ""
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
        let context = getContext()
        try {
            context.changeMode(CONFIRM)
            PrintUtils.printUserConfirm()
            let input = getUserInput(mode: CONFIRM)
            // Clear the confirmation prompt line
            moveCursor(1, Direction.UP)
            clearScreen(ClearMode.EntireLine)
            return input == '\n'
        } finally {
            context.changeMode(CHATTING)
        }

    }
}
