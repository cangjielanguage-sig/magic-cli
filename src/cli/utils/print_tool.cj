package cli.cli.utils


public func printTool(name: String, message: String) {
    let toolMessage = THEME_MUTED + "╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗\n"
        + THEME_SUCCESS + "   ✔  " + THEME_PRIMARY + name + "   " + THEME_INFO + message + "\n"
        + THEME_MUTED + "╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝\n" + RESET
    println(toolMessage)
}