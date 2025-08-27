package cli.utils

import std.collection.*

// Magic CLI logo implementation in Cangjie

// Initialize color mappings with ANSI escape codes
private let COLORS = HashMap([
    ("reset", "\u{1b}[0m"),
    ("purple", "\u{1b}[95m"),
    ("light_purple", "\u{1b}[38;5;141m"),
    ("dark_purple", "\u{1b}[38;5;53m"),
    ("violet", "\u{1b}[38;5;99m"),
    ("lavender", "\u{1b}[38;5;183m"),
    ("plum", "\u{1b}[38;5;96m"),
    ("indigo", "\u{1b}[38;5;54m"),
    ("orchid", "\u{1b}[38;5;170m"),
    ("magenta", "\u{1b}[38;5;201m"),
    ("pink_purple", "\u{1b}[38;5;213m"),
    ("royal_purple", "\u{1b}[38;5;57m"),
    ("amethyst", "\u{1b}[38;5;135m"),
    ("periwinkle", "\u{1b}[38;5;147m"),
    ("lilac", "\u{1b}[38;5;182m"),
    ("mauve", "\u{1b}[38;5;139m"),
    ("white", "\u{1b}[97m"),
    ("gray", "\u{1b}[90m")
])

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
private func apply3dEffect(pattern: Array<String>, colorName: String): Array<String> {
    let color = COLORS[colorName]
    let reset = COLORS["reset"]
    let gray = COLORS["gray"]
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
                newLine = newLine + color + solidBlock + reset
            } else if (char == r' ') {
                // Check if we need shadow effect
                if (i < pattern.size - 1 && j < runes.size - 1) {
                    let nextLineRunes = pattern[i + 1].toRuneArray()
                    if (j + 1 < nextLineRunes.size && nextLineRunes[j + 1] == r'█') {
                        // Add gradient shadow effect
                        newLine = newLine + gray + mediumBlock + reset
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
        "pink_purple", "orchid", "amethyst", "violet",
        "periwinkle", "lilac", "lavender", "mauve"
    ]

    // Get 3D patterns for each character with gradient effect
    let charPatterns = ArrayList<Array<String>>()
    var letterIndex = 0

    for (char in text.runes()) {
        if (PATTERNS.contains(char)) {
            let colorName = if (char != r' ') {
                let color = colorsCycle[letterIndex]
                letterIndex = letterIndex + 1
                color
            } else {
                "white"  // Space color
            }
            let pattern3d = apply3dEffect(PATTERNS[char], colorName)
            charPatterns.add(pattern3d)
        }
    }

    // Print elegant header with purple theme
    let headerLine = "━" * 100
    let purple = COLORS["purple"]
    let lightPurple = COLORS["light_purple"]
    let lavender = COLORS["lavender"]
    let indigo = COLORS["indigo"]
    let violet = COLORS["violet"]
    let reset = COLORS["reset"]

    println("\n${purple}${headerLine}${reset}")
    println("${' ' * 40}✨ ${lavender}MAGIC CLI${lightPurple} ✨${reset}")
    println("${purple}${headerLine}${reset}\n")

    // Print each row of the logo
    for (row in 0..7) {
        var line = ""
        for (pattern in charPatterns) {
            line = line + pattern[row] + "  "  // Add spacing between characters
        }
        println("  ${line}")
    }

    // Print elegant footer with purple theme
    println("\n${purple}${headerLine}${reset}")
    println("${' ' * 28} 🌟 ${lightPurple}Welcome to the Magic Experience!${lavender} 🌟${reset}")
    println("${' ' * 33} ${violet}✨ Powered by Cangjie Magic ✨${reset}")
    println("${purple}${headerLine}${reset}\n")
}
