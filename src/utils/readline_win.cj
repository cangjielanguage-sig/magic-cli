package cli.utils

import std.fs.Path

@When[os == "Windows"]
public class Readline {
    public init() { }

    public init(path: Path) { }

    public func readline(prompt: String): Option<String> {
        print(prompt, flush: true)
        return readln()
    }

    public func readline(prompt: String, withBox!: Bool): Option<String> {
        if (withBox) {
            return readline(prompt)
        } else {
            print(prompt, flush: true)
            return readln()
        }
    }
}

