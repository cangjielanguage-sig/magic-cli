package cli.core.tools

import cli.utils.*

import std.io.*

public class ConfirmTool {
    public static func confirm(name: String, message: String): (Bool, String) {
        let confirmation = InputUtils.confirm(name, message)
        if (!confirmation) {
            let input = readln()
            return (false, input)
        }
        return (true, "")
    }
}
