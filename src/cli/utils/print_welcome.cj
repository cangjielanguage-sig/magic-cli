package cli.cli.utils

import std.io.*
import std.time.*

public func printWelcome() {
    let currentTime = DateTime.now()
    let formattedTime = currentTime.format("yyyy-MM-dd HH:mm:ss")

    let welcomeMessage = THEME_SUCCESS + "Welcome to Magic CLI!\n" 
        + THEME_INFO + "当前时间：" + formattedTime + "\n" 
        + THEME_MUTED + "输入 '" + THEME_YELLOW + "help" + THEME_MUTED + "' 查看可用命令，输入 '" + THEME_YELLOW + "exit" + THEME_MUTED + "' 退出程序。\n\n" + RESET

    print(welcomeMessage)
}