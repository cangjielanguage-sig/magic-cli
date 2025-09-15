package cli.io

import std.collection.*

// Magic CLI logo implementation in Cangjie

// Initialize block characters
private let BLOCKS = HashMap([
    ("solid", "█"),
    ("dark", "▓"),
    ("medium", "▒"),
    ("light", "░"),
    ("empty", " "),
    ("sparkle", "✨"),
    ("diamond", "◆"),
    ("star", "★")
])

// Initialize character patterns
private let PATTERNS = HashMap([
    (r'M', [
        "██      ██",
        "███    ███",
        "████  ████",
        "██  ██  ██",
        "██      ██",
        "██      ██",
        "██      ██"
    ]),
    (r'A', [
        "    ██    ",
        "   ████   ",
        "  ██  ██  ",
        " ██    ██ ",
        " ████████ ",
        " ██    ██ ",
        " ██    ██ "
    ]),
    (r'G', [
        "  ██████  ",
        " ██    ██ ",
        " ██       ",
        " ██   ███ ",
        " ██    ██ ",
        " ██    ██ ",
        "  ██████  "
    ]),
    (r'I', [
        " ████████ ",
        "    ██    ",
        "    ██    ",
        "    ██    ",
        "    ██    ",
        "    ██    ",
        " ████████ "
    ]),
    (r'C', [
        "  ██████  ",
        " ██    ██ ",
        " ██       ",
        " ██       ",
        " ██       ",
        " ██    ██ ",
        "  ██████  "
    ]),
    (r'L', [
        " ██       ",
        " ██       ",
        " ██       ",
        " ██       ",
        " ██       ",
        " ██    ██ ",
        " ████████ "
    ]),
    (r' ', [
        "   ",
        "   ",
        "   ",
        "   ",
        "   ",
        "   ",
        "   "
    ])
])

// Apply 3D effect by adding shadow and depth
private func apply3dEffect(pattern: Array<String>, color: AnsiColor): Array<String> {
    let reset = AnsiColor.RESET
    let gray = AnsiColor.BRIGHT_BLACK
    let solidBlock = BLOCKS["solid"]
    let mediumBlock = BLOCKS["medium"]

    let result = ArrayList<String>()

    for (i in 0..pattern.size) {
        let line = pattern[i]
        var newLine = ""
        let runes = line.toRuneArray()

        for (j in 0..runes.size) {
            let char = runes[j]
            if (char == r'█') {
                // Main block with color
                newLine = newLine + solidBlock.withColor(color)
            } else if (char == r' ') {
                // Check if we need shadow effect
                if (i < pattern.size - 1 && j < runes.size - 1) {
                    let nextLineRunes = pattern[i + 1].toRuneArray()
                    if (j + 1 < nextLineRunes.size && nextLineRunes[j + 1] == r'█') {
                        // Add gradient shadow effect
                        newLine = newLine + mediumBlock.withColor(gray)
                    } else {
                        newLine = newLine + " "
                    }
                } else {
                    newLine = newLine + " "
                }
            } else {
                newLine = newLine + char.toString()
            }
        }
        result.add(newLine)
    }

    return result.toArray()
}

// Print the complete MAGIC CLI logo
public func printMagicCliLogo() {
    let text = "MAGIC CLI"
    // Stunning rainbow-purple gradient for maximum beauty
    let colorsCycle = [
        AnsiColor.PINK_PURPLE, AnsiColor.ORCHID, AnsiColor.AMETHYST, AnsiColor.VIOLET,
        AnsiColor.PERIWINKLE, AnsiColor.LILAC, AnsiColor.LAVENDER, AnsiColor.MAUVE
    ]

    // Get 3D patterns for each character with gradient effect
    let charPatterns = ArrayList<Array<String>>()
    var letterIndex = 0

    for (char in text.runes()) {
        if (PATTERNS.contains(char)) {
            let color = if (char != r' ') {
                let color = colorsCycle[letterIndex]
                letterIndex = letterIndex + 1
                color
            } else {
                AnsiColor.WHITE  // Space color
            }
            let pattern3d = apply3dEffect(PATTERNS[char], color)
            charPatterns.add(pattern3d)
        }
    }

    // Print elegant header with purple theme
    let headerLine = "━" * 100

    PrintUtils.printLine("\n${AnsiColor.PURPLE}${headerLine}${AnsiColor.RESET}")
    PrintUtils.printLine("${' ' * 40}✨ ${AnsiColor.LAVENDER}MAGIC CLI${AnsiColor.LIGHT_PURPLE} ✨${AnsiColor.RESET}")
    PrintUtils.printLine("${AnsiColor.PURPLE}${headerLine}${AnsiColor.RESET}\n")

    // Print each row of the logo
    for (row in 0..7) {
        var line = ""
        for (pattern in charPatterns) {
            line = line + pattern[row] + "  "  // Add spacing between characters
        }
        PrintUtils.printLine("  ${line}")
    }

    // Print elegant footer with purple theme
    PrintUtils.printLine("\n${headerLine.withColor(AnsiColor.PURPLE)}")
    PrintUtils.printLine("${' ' * 28} 🌟 ${AnsiColor.LIGHT_PURPLE}Welcome to the Magic Experience!${AnsiColor.LAVENDER} 🌟${AnsiColor.RESET}")
    PrintUtils.printLine("${' ' * 33} ${AnsiColor.VIOLET}✨ Powered by Cangjie Magic ✨${AnsiColor.RESET}")
    PrintUtils.printLine("${AnsiColor.PURPLE}${headerLine}${AnsiColor.RESET}\n")
}