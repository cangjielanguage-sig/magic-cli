package cli.cli.utils


public func printTool(name: String, message: String) {
    let toolMessage = wrapBox(
        "   ✔  ".withColor(THEME_SUCCESS) + name.withColor(THEME_PRIMARY),
        content:  message.withColor(THEME_INFO)
    )
    println(toolMessage)
}