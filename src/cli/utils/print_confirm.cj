package cli.cli.utils

@When[os == "Windows"]
public func printConfirm(name: String, message: String): Bool {
    let confirmMessage = THEME_MUTED + "╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗\n"
        + THEME_WARNING + "   ?  " + THEME_PRIMARY + name + "\n" + THEME_INFO + message + "\n"
        + THEME_MUTED + "╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝\n" + RESET
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
                printTool(name, message)
                return true
            } else {
                let cancelMessage = THEME_SECONDARY + "\nOperation cancelled.\n" + RESET
                print(cancelMessage)
                printPrompt("User Opinion")
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
public func printConfirm(name: String, message: String): Bool {
    let confirmMessage = THEME_MUTED + "╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗\n"
        + THEME_WARNING + "   ?  " + THEME_PRIMARY + name + "\n" + THEME_INFO + message + "\n"
        + THEME_MUTED + "╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝\n" + RESET
    println(confirmMessage)

    let promptMessage = THEME_PRIMARY + "(enter to confirm, any other key to cancel): " + RESET
    print(promptMessage)

    let c = readln()

    if (c.isEmpty()) {
        printTool(name, message)
        return true
    } else {
        let cancelMessage = THEME_SECONDARY + "Operation cancelled.\n" + RESET
        print(cancelMessage)
        printPrompt("User Opinion")
        return false
    }
}