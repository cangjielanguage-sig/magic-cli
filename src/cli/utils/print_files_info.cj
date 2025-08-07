package cli.cli.utils

import std.io.*
import std.fs.*
import std.collection.*

public func printFilesInfo(filesMatched: ArrayList<String>, path: String) {
    var filesMessage = "\n" + THEME_INFO + BOLD + "📁 目录: " + THEME_WARNING + path + RESET + "\n"
    for (file in filesMatched) {
        filesMessage += THEME_YELLOW + file + "\n" + RESET
    }
    print(filesMessage)
}