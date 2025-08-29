package cli.utils

import cli.core.config.CliConfig
import std.time.DateTime

protected enum Confirmation {
    | Approve
    | Deny(String)
}

protected class InputUtils {
    public static func buildPrompt(role: String): String {
        let time = DateTime.now().format("HH:mm:ss").withColor(THEME_INFO)
        let prefix = " 🕒 ".withColor(THEME_MUTED) + time + " |".withColor(THEME_MUTED)
        let roleInfo = role.padEnd(5).withColor(THEME_SUCCESS)
        let postfix = "> ".withColor(THEME_PRIMARY)
        return "${prefix} ${roleInfo} ${postfix}"
    }

    private static let READLINE = Readline(CliConfig.readlineFile)

    public static func getUserInput(prompt!: String = "User", withBox!: Bool = true): String {
        READLINE.readline(buildPrompt(prompt), withBox: withBox) ?? "exit"
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
        let input = READLINE.readline(
            "(Enter to confirm, any other key to cancel): ".withColor(THEME_PRIMARY),
            withBox: false
        ) ?? ""
        // Clear the confirmation prompt line
        moveCursor(1, Direction.UP)
        clearScreen(ClearMode.EntireLine)
        return input.isEmpty()
    }
}
