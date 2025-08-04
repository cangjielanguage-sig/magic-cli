package cli.core.tools

import std.io.*

public class ConfirmTool {
    public static func confirm(message: String): String {
        print(message)
        print("用户意见反馈 (press enter to continue / 提出修改意见): ")
        var response = readln()
        if (response.isEmpty()) {
            return "yes"
        } else {
            return response
        }
    }
}
