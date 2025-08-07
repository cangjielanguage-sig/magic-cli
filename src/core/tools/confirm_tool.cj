package cli.core.tools

import std.io.*

import cli.cli.utils.*

public class ConfirmTool {
    public static func confirm(name: String, message: String): (Bool, String) {
        let confirmation = printConfirm(name, message)
        if (!confirmation) {
            let input = readln()
            return (false, input)
        }
        return (true, "")
    }
}
