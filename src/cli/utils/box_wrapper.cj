package cli.cli.utils

import std.regex.Regex
import std.collection.ArrayList

private const LEFT_TOP  = "╔"
private const LEFT_BOTTOM = "╚"
private const RIGHT_TOP  = "╗"
private const RIGHT_BOTTOM = "╝"
private const HORIZONTAL_BORDER = "═"
private const HORIZONTAL_SEPARATOR = "─"
private const VERTICAL_BORDER = "║"

/*
 * Calculate the rune size except for the ANSI escape characters
 */
private func sizeOf(str: String): Int64 {
    let regex = Regex("\u{1B}\\[\\d+m")
    let strWithoutAnsiEscape = regex.replaceAll(str, "")
    return strWithoutAnsiEscape.toRuneArray().size
}

private func isChineseRune(rune: Rune): Bool {
    // Check for common Chinese + punctuation/symbols
    return r'\u{4e00}' <= rune && rune <= r'\u{9fff}' || // Common Chinese
           r'\u{3000}' <= rune && rune <= r'\u{303f}' || // Chinese punctuation
           r'\u{ff00}' <= rune && rune <= r'\u{ffef}' || // Full-width symbols
           r'\u{3400}' <= rune && rune <= r'\u{4dbf}'    // Rare characters (Extension A)
           // Add more ranges if needed
}

private func displaySizeOf(str: String): Int64 {
    let regex = Regex("\u{1B}\\[\\d+m")
    let strWithoutAnsiEscape = regex.replaceAll(str, "")
    var width = 0
    for (rune in strWithoutAnsiEscape.toRuneArray()) {
        // Unicode range of Chinese characters (rough estimate)
        if (isChineseRune(rune)) {
            // Chinese runes occupy width 2 positions
            width += 2
        } else {
            width += 1
        }
    }
    return width
}

private func padString(content: String, width: Int64, center!: Bool = false): String {
    let sizeToPad = width - displaySizeOf(content)
    if (center) {
        let leftToPad = sizeToPad / 2
        let rightToPad = sizeToPad - leftToPad
        return "${' ' * leftToPad}${content}${' ' * rightToPad}"
    } else {
        // println("${content}: ${displaySizeOf(content)} + ${sizeToPad}")
        return "${content}${(' ' * sizeToPad)}"
    }
}

private func splitLine(line: String, width: Int64): Array<String> {
    let runes = line.toRuneArray()
    let result = ArrayList<String>()
    for (pos in 0..runes.size: width) {
        let end = min(pos + width, runes.size)
        result.add(String(runes[pos..end]))
    }
    return result.toArray()
}

protected func wrapBox(title: String,
                       content!: String = "",
                       width!: Int64 = 100,
                       boxColor!: String = BRIGHT_BLACK,
                       centerTitle!: Bool = false): String {

    let lines = content.split("\n")
    return wrapBox(title, lines: lines, width: width, boxColor: boxColor, centerTitle: centerTitle)
}

protected func wrapBox(title: String,
                       lines!: Array<String>,
                       width!: Int64 = 100,
                       boxColor!: String = BRIGHT_BLACK,
                       centerTitle!: Bool = false): String {
    let strBuilder = StringBuilder()
    // Add the top line
    strBuilder.append("${LEFT_TOP}${HORIZONTAL_BORDER * width}${RIGHT_TOP}\n".withColor(boxColor))
    // Add the title
    strBuilder.append(
        "${VERTICAL_BORDER.withColor(boxColor)}${padString(title, width, center: centerTitle)}${VERTICAL_BORDER.withColor(boxColor)}\n"
    )
    // Add content lines if necessary
    if (!lines.isEmpty()) {
        strBuilder.append(
            "${VERTICAL_BORDER}${HORIZONTAL_SEPARATOR * width}${VERTICAL_BORDER}\n".withColor(boxColor)
        )
        for (line in lines) {
            // Split the line as multiple lines if it's too long
            let border = VERTICAL_BORDER.withColor(boxColor)
            for (subLine in splitLine(line, width)) {
                strBuilder.append(
                    "${border}${padString(subLine, width)}${border}\n")
            }
        }
    }
    // Add the bottom line
    strBuilder.append(
        "${LEFT_BOTTOM}${HORIZONTAL_BORDER * width}${RIGHT_BOTTOM}".withColor(boxColor)
    )
    return strBuilder.toString()
}