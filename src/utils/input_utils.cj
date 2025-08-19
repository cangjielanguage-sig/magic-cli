package cli.utils

import std.time.DateTime

protected enum Confirmation {
    | Approve
    | Deny(String)
}

protected class InputUtils {
    static public func buildPrompt(role: String): String {
        let time = DateTime.now().format("HH:mm:ss").withColor(THEME_INFO)
        let prefix = " 🕒 ".withColor(THEME_MUTED) + time + " |".withColor(THEME_MUTED)
        let roleInfo = role.padEnd(5).withColor(THEME_SUCCESS)
        let postfix = ">".withColor(THEME_PRIMARY)
        return "${prefix} ${roleInfo} ${postfix} "
    }

    private static let READLINE = Readline()

    static public func getUserInput(prompt!: String = "User", withBox!: Bool = true): String {
        READLINE.readline(buildPrompt(prompt), withBox: withBox) ?? "exit"
    }

    static public func confirm(name: String, message: String): Confirmation {
        // If user deny the confirmation, we let her/him input one more message
        if (InputUtils.confirmImpl(name, message)) {
            PrintUtils.printTool(name, message)
            println("🔮 Agent:  ✔  ".withColor(THEME_SUCCESS) + name.withColor(THEME_PRIMARY))
            return Confirmation.Approve
        } else {
            print("✖ Cancelled.\n".withColor(THEME_SECONDARY), flush: true)
            let input = InputUtils.getUserInput(prompt: "User Adjustment")
            return Confirmation.Deny(input)
        }
    }

    @When[os == "Windows"]
    static private func confirmImpl(name: String, message: String): Confirmation {
        let confirmMessage = wrapBox(
            "   ?  ".withColor(THEME_WARNING) + name.withColor(THEME_PRIMARY),
            content: message
        )
        println(confirmMessage)

        var selected: Int64 = 0

        while (true) {
            let selectMessage = if (selected == 0) {
                "\r${THEME_SUCCESS}${BOLD}  ► Yes${RESET}${THEME_MUTED}      No${RESET}"
            } else {
                "\r${THEME_MUTED}    Yes${RESET}${THEME_ERROR}${BOLD}    ► No${RESET}"
            }
            print(selectMessage)
            var c = getchar()
            if (c == 13) {
                if (selected == 0) {
                    println("")
                    return true
                } else {
                    return false
                }
            } else if (c == 0) {
                c = getchar()
                if (c == 75) {
                    selected = 0
                } else if (c == 77) {
                    selected = 1
                }
            }
        }
        throw UnsupportedException("Unreachable")
    }

    @When[os != "Windows"]
    static private func confirmImpl(name: String, message: String): Bool {
        let confirmMessage = wrapBox(
            " ?  ".withColor(THEME_WARNING) + name.withColor(THEME_PRIMARY),
            content: message
        )
        println(confirmMessage)

        let ch = InputUtils.getUserInput(
            prompt: "(Enter to confirm, any other key to cancel): ".withColor(THEME_PRIMARY),
            withBox: false
        )
        return ch.isEmpty()
    }
}