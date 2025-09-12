package cli.io

import std.regex.Regex
import std.collection.{ArrayList, collectArray}
import magic.log.LogUtils

// Box drawing characters for creating bordered text boxes
private const LEFT_TOP = "┌"              // Top-left corner
private const LEFT_BOTTOM = "└"           // Bottom-left corner
private const RIGHT_TOP = "┐"             // Top-right corner
private const RIGHT_BOTTOM = "┘"          // Bottom-right corner
private const HORIZONTAL_BORDER = "─"     // Horizontal line for top/bottom borders
private const VERTICAL_BORDER = "│"       // Vertical line for left/right borders
private const HORIZONTAL_SEPARATOR = "─"  // Horizontal line for separating sections
private const PAD = "\u{202F}"            // Narrow no-break space for padding (2-byte UTF-8)
/**
 * Pad a string to a specified width with padding characters
 * @param content The text content to pad
 * @param width The target width in display characters
 * @param center Whether to center the content (default: left-align)
 * @return The padded string
 */
func padString(content: String, width!: Int64, center!: Bool = false): String {
    let sizeToPad = max(0, width - displayWidthOf(content))
    if (center) {
        let leftToPad = sizeToPad / 2
        let rightToPad = sizeToPad - leftToPad
        return "${PAD * leftToPad}${content}${PAD * rightToPad}"
    } else {
        return "${content}${(PAD * sizeToPad)}"
    }
}

/**
 * Split a line into multiple sub-lines that fit within the specified width
 * Handles ANSI escape sequences properly by not counting them towards display width
 * @param line The input line to split
 * @param width Maximum display width for each sub-line
 * @return Array of sub-lines, each fitting within the width constraint
 */
private func splitLine(line: String, width: Int64): Array<String> {
    let resultSubLines = ArrayList<String>()

    var runeIndex = 0
    var currentSubLineBuilder = StringBuilder()
    var currentSubLineWidth = 0
    let lineRunes = line.toRuneArray()

    while (runeIndex < lineRunes.size) {
        let currentRune = lineRunes[runeIndex]

        // Handle ANSI escape sequences (don't count towards display width)
        if (currentRune == r'\u{1B}') { // ESC character starts ANSI sequence
            currentSubLineBuilder.append(currentRune)
            runeIndex += 1
            // Skip through the escape sequence until we hit a letter (sequence terminator)
            while (runeIndex < lineRunes.size && !lineRunes[runeIndex].isAsciiLetter()) {
                currentSubLineBuilder.append(lineRunes[runeIndex])
                runeIndex += 1
            }
            // Append the terminating letter if we found one
            if (runeIndex < lineRunes.size) {
                currentSubLineBuilder.append(lineRunes[runeIndex])
            }
        } else {
            let runeDisplayWidth = displayWidthOf(currentRune)

            // If adding this character would exceed width, start a new sub-line
            if (runeDisplayWidth + currentSubLineWidth > width) {
                resultSubLines.add(currentSubLineBuilder.toString())
                currentSubLineBuilder.reset()
                currentSubLineWidth = 0
            }

            currentSubLineBuilder.append(currentRune)
            currentSubLineWidth += runeDisplayWidth
        }
        runeIndex += 1
    }

    // Add the final sub-line if it has content
    let finalSubLineContent = currentSubLineBuilder.toString()
    if (!finalSubLineContent.isEmpty()) {
        resultSubLines.add(finalSubLineContent)
    }
    return resultSubLines.toArray()
}

/**
 * Create a bordered text box containing the given content
 * @param content The text content to display in the box
 * @param width The width of the box in display characters (default: 100)
 * @param boxColor The color of the box border (default: AnsiColor.BRIGHT_BLACK)
 * @param centerTitle Whether to center the title (default: false, not used in this overload)
 * @return The formatted box as a string with borders
 */
protected func wrapBox(content: String, width!: Int64 = 100, boxColor!: AnsiColor = AnsiColor.BRIGHT_BLACK,
    centerTitle!: Bool = false): String {
    return wrapBox("", content: content, width: width, boxColor: boxColor, centerTitle: centerTitle)
}

/**
 * Create a bordered text box with a title and content
 * @param title The title to display at the top of the box
 * @param content The text content to display in the box (will be split by newlines)
 * @param width The width of the box in display characters (default: 100)
 * @param boxColor The color of the box border (default: AnsiColor.BRIGHT_BLACK)
 * @param centerTitle Whether to center the title text (default: false)
 * @return The formatted box as a string with borders, title, and content
 */
protected func wrapBox(title: String, content!: String, width!: Int64 = 100, boxColor!: AnsiColor = AnsiColor.BRIGHT_BLACK,
    centerTitle!: Bool = false): String {
    let lines = content.split("\n")
    return wrapBox(title, lines: lines, width: width, boxColor: boxColor, centerTitle: centerTitle)
}

/**
 * Create a bordered text box with title and content lines (main implementation)
 * This is the core function that actually builds the box structure with:
 * - Top border with corner characters
 * - Optional title section with horizontal separator
 * - Content lines wrapped with vertical borders
 * - Bottom border with corner characters
 *
 * @param title The title to display at the top of the box
 * @param lines Array of content lines to display in the box
 * @param width The width of the box in display characters (default: 100)
 * @param boxColor The color of the box border (default: AnsiColor.BRIGHT_BLACK)
 * @param centerTitle Whether to center the title text (default: false)
 * @return The complete formatted box as a string
 */
protected func wrapBox(title: String, lines!: Array<String>, width!: Int64 = 100, boxColor!: AnsiColor = AnsiColor.BRIGHT_BLACK,
    centerTitle!: Bool = false): String {
    let strBuilder = StringBuilder()
    // Add the top border line with corner characters
    strBuilder.append("${LEFT_TOP}${HORIZONTAL_BORDER * width}${RIGHT_TOP}".withColor(boxColor))
    strBuilder.append("\n")
    // Add the title section if title is provided
    if (!title.isEmpty()) {
        strBuilder.append(
            "${VERTICAL_BORDER.withColor(boxColor)}${padString(title, width: width, center: centerTitle)}${VERTICAL_BORDER.withColor(boxColor)}\n")
        strBuilder.append("${VERTICAL_BORDER}${HORIZONTAL_SEPARATOR * width}${VERTICAL_BORDER}".withColor(boxColor))
        strBuilder.append('\n')
    }
    // Add content lines with vertical borders
    if (!lines.isEmpty()) {
        for (line in lines) {
            strBuilder.append("${wrapLineWithVerticalBorder(line, width: width, boxColor: boxColor)}")
            strBuilder.append('\n')
        }
    }
    // Add the bottom border line with corner characters
    strBuilder.append("${LEFT_BOTTOM}${HORIZONTAL_BORDER * width}${RIGHT_BOTTOM}".withColor(boxColor))
    return strBuilder.toString()
}

/**
 * Wrap a single line of text with vertical borders on both sides
 * If the line is too long for the specified width, it will be split into multiple sub-lines
 * Each sub-line is padded to the full width and wrapped with vertical borders
 *
 * @param line The input line of text to wrap
 * @param width The target width for the box content (default: 100)
 * @param boxColor The color of the vertical border characters (default: AnsiColor.BRIGHT_BLACK)
 * @return The line(s) wrapped with vertical borders, joined by newlines if split
 */
protected func wrapLineWithVerticalBorder(line: String, width!: Int64 = 100, boxColor!: AnsiColor = AnsiColor.BRIGHT_BLACK): String {
    let border = VERTICAL_BORDER.withColor(boxColor)
    // If line is empty, fill with spaces
    if (line.isEmpty()) {
        return "${border}${' ' * width}${border}"
    }
    let subLines: ArrayList<String> = ArrayList()
    // Split the line into multiple sub-lines if it exceeds the width
    for (subLine in splitLine(line, width)) {
        subLines.add("${border}${padString(subLine, width: width)}${border}")
    }
    return String.join(subLines.toArray(), delimiter: '\n')
}

/**
 * Create a scrollable selection list display for completion options
 * Shows up to 8 items at a time with visual indicators for scrolling
 * The selected item is highlighted in bright blue and bold
 *
 * @param showArray Array of items to display in the list
 * @param selectIdx Index of the currently selected item (0-based)
 * @return Formatted string with the visible portion of the list, with scroll indicators
 */
protected func wrapOptionList(options: Array<String>, selectedIndex: Int64): String {
    if (options.size == 0) {
        return ""
    }
    let listBuilder = StringBuilder()
    let maxVisibleItems = 8  // Maximum number of items to show at once
    let visibleRangeEnd = min(max(selectedIndex + 1, maxVisibleItems), options.size)
    let visibleRangeStart = max(0, visibleRangeEnd - maxVisibleItems)

    // Show up arrow if there are items above the visible range
    if (visibleRangeStart > 0) {
        listBuilder.append("\n▲")
    }

    // Show the visible range of items
    for (itemIndex in visibleRangeStart..visibleRangeEnd) {
        let currentItem = options[itemIndex]
        listBuilder.append("\n")
        if (itemIndex == selectedIndex) {
            // Highlight the selected item
            listBuilder.append("${AnsiColor.BRIGHT_BLUE}${AnsiColor.BOLD}${currentItem}${AnsiColor.RESET}")
        } else {
            // Normal display for unselected items
            listBuilder.append("${AnsiColor.BRIGHT_BLACK}${currentItem}${AnsiColor.RESET}")
        }
    }

    // Show down arrow and position indicator if there are more items
    if (options.size > maxVisibleItems) {
        listBuilder.append("\n▼(${selectedIndex + 1}/${options.size})")
    }
    return listBuilder.toString()
}

/**
 * Calculate the cursor position within a wrapped and bordered text box
 * This is a critical function for readline_2 that determines where to position
 * the terminal cursor based on the logical cursor position in the input text
 *
 * The function handles:
 * - Converting logical cursor position to visual position within wrapped lines
 * - Accounting for box borders and padding characters
 * - Handling ANSI escape sequences that don't contribute to display width
 * - Adjusting for prefix text (like prompts)
 *
 * @param wrappedContent The complete formatted box content with borders
 * @param cursorPos The logical cursor position in the original text (0-based)
 * @param prefix Optional prefix text like prompt (default: empty)
 * @param width The width of the box content area (default: 100)
 * @param boxColor The color of the box borders (default: BRIGHT_BLACK)
 * @return Tuple of (row, column) representing the visual cursor position
 */
protected func calculateCursorPos(wrappedContent: String, cursorPos: Int64, prefix!: String = String.empty,
    width!: Int64 = 100, boxColor!: AnsiColor = AnsiColor.BRIGHT_BLACK): (Int64, Int64) {
    let realCursorPos = cursorPos + runeSizeOf(prefix)
    let widthList = ArrayList<Int64>()
    var lines = collectArray(wrappedContent.lines())
    var cursorLeft = realCursorPos

    // Remove the top and bottom border lines, keep only content lines
    lines = lines[1..(lines.size - 1)]
    var cursorWidth = 0

    // Process each content line to find cursor position
    for (i in 0..lines.size) {
        let line = lines[i]
            .removePrefix(VERTICAL_BORDER.withColor(boxColor))  // Remove left border
            .removeSuffix(VERTICAL_BORDER.withColor(boxColor))  // Remove right border
            .replace(PAD, '')  // Remove padding characters
        let lineRunes = removeAnsiEscape(line).toRuneArray()  // Remove ANSI sequences for width calculation
        let lineWidth = displayWidthOf(lineRunes)
        widthList.add(lineWidth)
        let cursorRunes = min(cursorLeft, lineRunes.size)

        // Check if cursor is within this line
        if (cursorLeft - cursorRunes <= 0) {
            cursorWidth += displayWidthOf(lineRunes[0..cursorRunes])
            break
        }
        cursorLeft -= cursorRunes
        cursorWidth += lineWidth
    }

    // Find the row and column coordinates
    let (row, col) = findCoordinates(widthList, cursorWidth)
    // Adjust for the left border width plus one space
    return (row, col + displayWidthOf(VERTICAL_BORDER.withColor(boxColor)) + 1)
}

/**
 * Helper function to find row and column coordinates from a list of line widths
 * Given a target position (cumulative character count), finds which line it belongs to
 * and the position within that line
 *
 * @param widthList List of display widths for each line
 * @param target The target cumulative character position to locate
 * @return Tuple of (row, column) where the target position is located
 */
private func findCoordinates(widthList: ArrayList<Int64>, target: Int64): (Int64, Int64) {
    if (target < 0) {
        return (0, 0)
    }
    var total = 0
    for (i in 0..widthList.size) {
        let lineWidth = widthList[i]
        if (total + lineWidth >= target) {
            return (i, target - total)
        }
        total += lineWidth
    }
    // Handle case where target exceeds total width (e.g., during backspace operations)
    return (widthList.size, target - total)
}