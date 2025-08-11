package cli.cli.utils

import std.time.*
import std.io.*
import std.unittest.common.*

public func printPrompt(role: String) {
    let currentTime = DateTime.now()
    let formattedTime = currentTime.format("HH:mm:ss")
    let prompt = THEME_MUTED + "[ 🕒 " + THEME_INFO + formattedTime + THEME_MUTED + " ] " + THEME_SUCCESS + role.padEnd(5) + THEME_PRIMARY + " > " + RESET
    print(prompt)
}