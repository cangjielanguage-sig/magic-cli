package cli.utils

import std.regex.Regex
import std.collection.ArrayList

private const LEFT_TOP = "╔"
private const LEFT_BOTTOM = "╚"
private const RIGHT_TOP = "╗"
private const RIGHT_BOTTOM = "╝"
private const HORIZONTAL_BORDER = "═"
private const HORIZONTAL_SEPARATOR = "─"
private const VERTICAL_BORDER = "║"

/*
 * Calculate the rune size except for the ANSI escape characters
 */
private func sizeOf(str: String): Int64 {
    let regex = Regex("\u{1B}\\[\\d*[a-zA-Z]")
    let strWithoutAnsiEscape = regex.replaceAll(str, "")
    return strWithoutAnsiEscape.toRuneArray().size
}

func padString(content: String, width!: Int64, center!: Bool = false): String {
    let sizeToPad = max(0, width - displayWidthOf(content))
    if (center) {
        let leftToPad = sizeToPad / 2
        let rightToPad = sizeToPad - leftToPad
        return "${' ' * leftToPad}${content}${' ' * rightToPad}"
    } else {
        // println("${content}: ${displaySizeOf(content)} + ${sizeToPad}")
        return "${content}${(' ' * sizeToPad)}"
    }
}

/**
 * Split the line as multiple sub-lines, each sub-line does not exceed the width
 */
private func splitLine(line: String, width: Int64): Array<String> {
    let subLines = ArrayList<String>()

    var idx = 0
    var currSubLine = StringBuilder()
    var currWidthOfSubLine = 0
    let runes = line.toRuneArray()
    while (idx < runes.size) {
        let rune = runes[idx]
        if (rune == r'\u{1B}') { // ANSI escape char \u{1B}[\d*\w, skip it
            while (!runes[idx].isAsciiLetter()) { // skip until
                currSubLine.append(runes[idx])
                idx += 1
            }
            currSubLine.append(runes[idx])
        } else {
            let widthOfRune = displayWidthOf(rune)
            if (widthOfRune + currWidthOfSubLine >= width) {
                subLines.add(currSubLine.toString())
                currSubLine.reset()
                currWidthOfSubLine = 0
            }
            currSubLine.append(rune)
            currWidthOfSubLine += widthOfRune
        }
        idx += 1
    }
    let lastSubLine = currSubLine.toString()
    if (!lastSubLine.isEmpty()) {
        subLines.add(lastSubLine)
    }
    return subLines.toArray()
}

protected func wrapBox(content: String, width!: Int64 = 100, boxColor!: String = BRIGHT_BLACK,
    centerTitle!: Bool = false): String {
    return wrapBox("", content: content, width: width, boxColor: boxColor, centerTitle: centerTitle)
}

protected func wrapBox(title: String, content!: String, width!: Int64 = 100, boxColor!: String = BRIGHT_BLACK,
    centerTitle!: Bool = false): String {
    let lines = content.split("\n")
    return wrapBox(title, lines: lines, width: width, boxColor: boxColor, centerTitle: centerTitle)
}

protected func wrapBox(title: String, lines!: Array<String>, width!: Int64 = 100, boxColor!: String = BRIGHT_BLACK,
    centerTitle!: Bool = false): String {
    let strBuilder = StringBuilder()
    // Add the top line
    strBuilder.append("${LEFT_TOP}${HORIZONTAL_BORDER * width}${RIGHT_TOP}\n".withColor(boxColor))
    // Add the title
    if (!title.isEmpty()) {
        strBuilder.append(
            "${VERTICAL_BORDER.withColor(boxColor)}${padString(title, width: width, center: centerTitle)}${VERTICAL_BORDER.withColor(boxColor)}\n")
        strBuilder.append("${VERTICAL_BORDER}${HORIZONTAL_SEPARATOR * width}${VERTICAL_BORDER}\n".withColor(boxColor))
    }
    // Add content lines if necessary
    if (!lines.isEmpty()) {
        for (line in lines) {
            // Split the line as multiple lines if it's too long
            for (subLine in splitLine(line, width)) {
                strBuilder.append("${wrapLineWithVerticalBorder(subLine, width: width, boxColor: boxColor)}\n")
            }
        }
    }
    // Add the bottom line
    strBuilder.append("${LEFT_BOTTOM}${HORIZONTAL_BORDER * width}${RIGHT_BOTTOM}".withColor(boxColor))
    return strBuilder.toString()
}

protected func wrapLineWithVerticalBorder(line: String, width!: Int64 = 100, boxColor!: String = BRIGHT_BLACK): String {
    let border = VERTICAL_BORDER.withColor(boxColor)
    return "${border}${padString(line, width: width)}${border}"
}

protected func wrapShowList(showArray: Array<String>, selectIdx: Int64, prefix!: String = String.empty): String {
    let lstSb = StringBuilder('\n')
    if (showArray.size == 0) {
        return ""
    }
    let maxExtend = 8
    let rangeEnd = min(max(selectIdx + 1, maxExtend), showArray.size)
    let rangeStart = max(0, rangeEnd - maxExtend)
    if (rangeStart > 0) {
        lstSb.append("\n▲")
    }
    for (i in rangeStart..rangeEnd) {
        let showItem = showArray[i]
        lstSb.append("\n")
        if (i == selectIdx) {
            let indexOp = showItem.indexOf(prefix)
            if (let Some(index) <- indexOp) {
                lstSb.append(
                    "${BRIGHT_BLUE}${BOLD}${prefix}${BRIGHT_BLACK}${showItem[(index + prefix.toRuneArray().size)..showItem.size]}${RESET}")
            } else {
                lstSb.append("${BRIGHT_BLUE}${BOLD}${showItem}${RESET}")
            }
        } else {
            lstSb.append("${BRIGHT_BLACK}${showItem}${RESET}")
        }
    }
    if (showArray.size > maxExtend) {
        lstSb.append("\n▼(${selectIdx + 1}/${showArray.size})")
    }
    return lstSb.toString()
}
