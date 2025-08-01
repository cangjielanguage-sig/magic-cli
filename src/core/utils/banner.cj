package cli.core.utils

import std.console.*

struct AnsiColor {
    public AnsiColor(let code: String) {}

    public static func rgb(r: Int64, g: Int64, b: Int64): AnsiColor {
        return AnsiColor("\u{1b}[38;2;${r};${g};${b}m")
    }

    public static prop reset: String {
        get() {
            "\u{1b}[0m"
        }
    }
}

public class Banner {
    public func printBanner() {
        let c = [
            "  █████▒  ",
            " ██▒▒▒██  ",
            " █▒▒      ",
            " █▒▒      ",
            " █▒▒      ",
            " ██▒▒▒██  ",
            "  █████▒  "
        ]
        
        let a = [
            "   ████   ",
            "  ██▒▒██  ",
            " ██▒▒▒▒██ ",
            " ████████ ",
            " ██▒▒▒▒██ ",
            " ██▒▒▒▒██ ",
            " ██▒▒▒▒██ "
        ]

        let n = [
            " ██▒▒▒▒██ ",
            " ███▒▒▒██ ",
            " ██▒█▒▒██ ",
            " ██▒▒█▒██ ",
            " ██▒▒▒███ ",
            " ██▒▒▒███ ",
            " ██▒▒▒▒██ "
        ]

        let g = [
            "  █████▒  ",
            " ██▒▒▒██  ",
            " █▒▒      ",
            " █▒▒ ████ ",
            " █▒▒ ▒▒██ ",
            " ██▒▒▒██  ",
            "  █████▒  "
        ]

        let j = [
            "      ███ ",
            "      ███ ",
            "      ███ ",
            "      ███ ",
            "      ███ ",
            " ██▒▒ ███ ",
            "  █████▒  "
        ]
        
        let i = [
            " ███████  ",
            " ▒▒███▒▒  ",
            " ▒▒███▒▒  ",
            " ▒▒███▒▒  ",
            " ▒▒███▒▒  ",
            " ▒▒███▒▒  ",
            " ███████  "
        ]

        let e = [
            " ███████  ",
            " ██▒▒▒▒▒  ",
            " ██▒▒▒▒▒  ",
            " ███████  ",
            " ██▒▒▒▒▒  ",
            " ██▒▒▒▒▒  ",
            " ███████  "
        ]

        let l = [
            " ██▒▒▒▒▒  ",
            " ██▒▒▒▒▒  ",
            " ██▒▒▒▒▒  ",
            " ██▒▒▒▒▒  ",
            " ██▒▒▒▒▒  ",
            " ██▒▒▒▒▒  ",
            " ███████  "
        ]

        let separator = [
            "    ",
            "    ",
            "    ",
            "    ",
            "    ",
            "    ",
            "    "
        ]
        
        let cangjieCliArt = [c, a, n, g, j, i, e, separator, c, l, i]
        
        let colors = [
            AnsiColor.rgb(110, 80, 200),
            AnsiColor.rgb(135, 80, 190),
            AnsiColor.rgb(160, 80, 175),
            AnsiColor.rgb(190, 85, 150),
            AnsiColor.rgb(220, 90, 130),
            AnsiColor.rgb(240, 110, 110),
            AnsiColor.rgb(255, 130, 90),
            AnsiColor.rgb(200, 200, 200),
            AnsiColor.rgb(255, 150, 80),
            AnsiColor.rgb(255, 170, 80),
            AnsiColor.rgb(255, 190, 80)
        ]

        let height = c.size
        
        for (lineIndex in 0..=height - 1) {
            for (charIndex in 0..=cangjieCliArt.size - 1) {
                let letterArt = cangjieCliArt[charIndex]
                let color = colors[charIndex]
                Console.stdOut.write("${color.code}${letterArt[lineIndex]}")
            }
            Console.stdOut.writeln(AnsiColor.reset)
        }
        
        Console.stdOut.flush()
    }
}