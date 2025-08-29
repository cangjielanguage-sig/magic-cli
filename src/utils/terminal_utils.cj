package cli.utils
import std.process.*
import std.fs.Path

public class TerminalUtils {
    public static func execute(command:String, path: Path): (Int64, Array<Byte>, Array<Byte>) {
        if (InfoUtils.os == "windows") {
            executeWithOutput("powershell", ["-Command", command], workingDirectory: path)
        } else {
            executeWithOutput("/bin/bash", ["-c", command], workingDirectory: path)
        }
    }
}
