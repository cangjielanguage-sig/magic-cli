package cli.utils

@When[os == "Windows"]
public class Readline {
    public func readline(prompt: String): Option<String> {
        print(prompt, flush: true)
        return readln()
    }
}

