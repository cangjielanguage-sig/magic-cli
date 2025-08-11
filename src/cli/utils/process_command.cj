package cli.cli.utils

public func processCommand(command: String): Bool { // 返回值表示是否返回main loop
    if (command == "exit") {
        let message = THEME_SECONDARY + "\nExiting the CLI. Goodbye!\n\n" + RESET
        println(message)
        return true
    } else if (command == "help") {
        let helpMessage = wrapBox(
            "Available Commands".withColor(THEME_PRIMARY),
            lines: [
                "${' help'.padEnd(10).withColor(THEME_YELLOW)}${' ║ - Show this help message'.withColor(THEME_MUTED)}",
                "${' clear'.padEnd(10).withColor(THEME_YELLOW)}${' ║ - Clear the screen'.withColor(THEME_MUTED)}",
                "${' exit'.padEnd(10).withColor(THEME_YELLOW)}${' ║ - Exit the CLI'.withColor(THEME_MUTED)}"
            ],
            width: 60,
            centerTitle: true
        )
        println(helpMessage)
        return false
    } else if (command == "clear") {
        clearScreen()
        printLogo()
        return false
    } else {
        return true
    }
}