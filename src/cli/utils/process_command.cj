package cli.cli.utils

public func processCommand(command: String): Bool { // 返回值表示是否返回main loop
    if (command == "exit") {
        let message = THEME_SECONDARY + "\nExiting the CLI. Goodbye!\n\n" + RESET
        println(message)
        return true
    } else if (command == "help") {
        let helpMessage = THEME_MUTED + "╔══════════════════════════════════════════════════╗\n"
            + "║               " + THEME_PRIMARY + "Available Commands" + THEME_MUTED + "                 ║\n"
            + "╠══════════════════════════════════════════════════╣\n"
            + "║  " + THEME_YELLOW + "help              " + THEME_INFO + "- Show this help message" + THEME_MUTED + "      ║\n"
            + "║  " + THEME_YELLOW + "clear             " + THEME_INFO + "- Clear the screen" + THEME_MUTED + "            ║\n"
            + "║  " + THEME_YELLOW + "exit              " + THEME_INFO + "- Exit the CLI" + THEME_MUTED + "                ║\n"
            + "╚══════════════════════════════════════════════════╝\n" + RESET
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