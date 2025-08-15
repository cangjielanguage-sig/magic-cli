package cli.utils

import std.time.DateTime

protected class InputUtils {
    static public func buildPrompt(role: String): String {
        let time = DateTime.now().format("HH:mm:ss").withColor(THEME_INFO)
        let prefix = " 🕒 ".withColor(THEME_MUTED) + time + " |".withColor(THEME_MUTED)
        let roleInfo = role.padEnd(5).withColor(THEME_SUCCESS)
        let postfix = ">".withColor(THEME_PRIMARY)
        return "${prefix} ${roleInfo} ${postfix} "
    }

    private static let READLINE = Readline()

    static public func getUserInput(): String {
        READLINE.readline(buildPrompt("User")) ?? "exit"
    }

    @When[os == "Windows"]
    static public func confirm(name: String, message: String): Bool {
        let confirmMessage = wrapBox(
            "   ?  ".withColor(THEME_WARNING) + name.withColor(THEME_PRIMARY),
            content: message
        )
        println(confirmMessage)

        var selected: Int64 = 0

        while (true) {
            let selectMessage = if (selected == 0) {
                "\r" + THEME_SUCCESS + BOLD + "  ► Yes" + RESET + THEME_MUTED + "      No" + RESET
            } else {
                "\r" + THEME_MUTED + "    Yes" + RESET + THEME_ERROR + BOLD + "    ► No" + RESET
            }

            print(selectMessage)

            var c = getchar()

            if (c == 13) {
                if (selected == 0) {
                    println("")
                    PrintUtils.printTool(name, message)
                    return true
                } else {
                    let cancelMessage = THEME_SECONDARY + "\nCancelled.\n" + RESET
                    print(cancelMessage)
                    print(buildPrompt("User Opinion"))
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

        return false
    }

    @When[os != "Windows"]
    static public func confirm(name: String, message: String): Bool {
        let confirmMessage = wrapBox(
            "   ?  ".withColor(THEME_WARNING) + name.withColor(THEME_PRIMARY),
            content: message
        )
        println(confirmMessage)

        print("(Enter to confirm, any other key to cancel): ".withColor(THEME_PRIMARY))
        let c = readln()

        if (c.isEmpty()) {
            PrintUtils.printTool(name, message)
            return true
        } else {
            print("Cancelled.\n".withColor(THEME_SECONDARY))
            print(buildPrompt("User Opinion"))
            return false
        }
    }
}