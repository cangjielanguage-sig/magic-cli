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
                READLINE.readline(buildPrompt('🧠'), withBox: withBox) ?? "exit"
            case TERMINAL => 
                READLINE.readline(buildPrompt('💻'), withBox: withBox) ?? "exit"
            case CHATTING => 
                if (AsciiListener.listenEsc()) {
                    '\u{1B}'
                } else {
                    ""
                }
            case _ => // CONFIRM MODE
                let context = getContext()
                let thread = Thread.currentThread
                if (thread.id != context.workingThread) {
                    return ""
                }
                if (AsciiListener.listenEnter(infinite:true)) {
                    '\n'
                } else {
                    ""
                }
        }
    }

    public static func confirm(title: String, content: String): Confirmation {
        // Print the confirm message
        let mark = if (CliConfig.auto) {
            "✔ ".withColor(THEME_SUCCESS)
        } else {
            "? ".withColor(THEME_WARNING)
        }
        println(
            wrapBox(
                mark + title.withColor(THEME_PRIMARY),
                content: content
            )
        )
        if (CliConfig.auto) {
            return Confirmation.Approve
        }
        // If user deny the confirmation, we let her/him input one more message
        if (InputUtils.getConfirmation()) {
            println("└─ 🔧 Approved to run...".withColor(THEME_MUTED))
            return Confirmation.Approve
        } else {
            print("└─ ✖ Cancelled...\n".withColor(THEME_MUTED), flush: true)
            let input = InputUtils.getUserInput()
            return Confirmation.Deny(input)
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
