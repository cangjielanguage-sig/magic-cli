package cli.utils

import magic.log.LogUtils
import std.collection.{ArrayList, LinkedList}
import std.regex.Regex
import std.deriving.*
import std.fs.{File, Path, exists}

/**
 * Compute the display width of a rune
 */
func displayWidthOf(rune: Rune): Int64 {
    // Chinese and emoji runes occupy width 2 positions
    // Unicode range of Chinese characters (rough estimate)
    if (r'\u{4e00}' <= rune && rune <= r'\u{9fff}' || // Common Chinese
        r'\u{3000}' <= rune && rune <= r'\u{303f}' || // Chinese punctuation
        r'\u{ff00}' <= rune && rune <= r'\u{ffef}' || // Full-width symbols
            r'\u{3400}' <= rune && rune <= r'\u{4dbf}' || // Rare characters (Extension A)
        r'\u{1f300}' <= rune && rune <= r'\u{1faff}') { // Emoji
        return 2
    } else {
        return 1
    }
}

/**
 * Compute the display width of a string
 */
func displayWidthOf(str: String): Int64 {
    let regex = Regex("\u{1B}\\[\\d*[a-zA-Z]")
    let strWithoutAnsiEscape = regex.replaceAll(str, "")
    var width = 0
    for (rune in strWithoutAnsiEscape.toRuneArray()) {
        width += displayWidthOf(rune)
    }
    return width
}

/**
 * Compute the display width of a string
 */
func displayWidthOf(runeArray: Array<Rune>): Int64 {
    return displayWidthOf(String(runeArray))
}

@Derive[Equatable]
private enum DrawPhase {
    | First
    | Last
    | Mid
}

/**
 * Clear the line and redraw it
 */
private func redraw(prompt: String, content: String, cursorPos: Int64, phase!: DrawPhase) {
    redraw(prompt, content.toRuneArray(), cursorPos, phase: phase)
}

private func redraw(prompt: String, content: Array<Rune>, cursorPos: Int64, phase!: DrawPhase) {
    // If it has draw the boxed content,
    // move the cursor to the first line because the current line in at the second line
    if (phase != DrawPhase.First) {
        moveCursor(1, UP)
        clearRunes(LINE)
    }
    if (phase == DrawPhase.Last) {
        print(wrapBox("${prompt}${String(content)}"), flush: true)
        print("\n", flush: true)
        return
    }
    // Draw the box
    print(wrapBox(prompt), flush: true)
    // Move cursor from the third line to the second line
    moveCursor(1, UP)
    // Clear the second line
    clearRunes(LINE)
    // Construct the content and print it
    let strBuilder = StringBuilder()
    strBuilder.append(prompt)
    for (i in 0..content.size) {
        if (i == cursorPos) {
            strBuilder.append("\u{1B}[s")
        }
        strBuilder.append(content[i])
    }
    if (cursorPos == content.size) {
        strBuilder.append("\u{1B}[s")
    }
    print(wrapLineWithVerticalBorder(strBuilder.toString()), flush: true)
    // clear all bytes below
    moveCursor(1, DOWN)
    clearRunes(BEHIND)
    moveCursor(1, UP)
    // restore curosr
    restoreCursorPosition()
    // strBuilder.append(wrapLineWithVerticalBorder("${prompt}${String(content)}"))
    // // Compute the offset of the cursor to move
    // var offset = 0
    // for (i in cursorPos..content.size) {
    //     offset += displayWidthOf(content[i])
    // }
    // if (offset > 0) {
    //     // Move the cursor to the left
    //     strBuilder.append("\u{1b}[${offset}D")
    // }
    // print(strBuilder.toString(), flush: true)
}

private func redrawAt(prompt: String, content: Array<Rune>, cursorPos: Int64, selectIdx: Int64, files: Array<String>,
    phase!: DrawPhase) {
    // If it has draw the boxed content,
    // move the cursor to the first line because the current line in at the second line
    if (phase != DrawPhase.First) {
        moveCursor(1, UP)
        clearRunes(LINE)
    }
    if (phase == DrawPhase.Last) {
        print(wrapBox("${prompt}${String(content)}"), flush: true)
        print("\n", flush: true)
        return
    }
    // Draw the box
    print(wrapBox(prompt), flush: true)
    // Move cursor from the third line to the second line
    moveCursor(1, UP)
    // Clear the second line
    clearRunes(LINE)
    // Construct the content and print it
    let strBuilder = StringBuilder()
    strBuilder.append(prompt)
    for (i in 0..content.size) {
        strBuilder.append(content[i])
    }
    var cursorSavePos = displayWidthOf(prompt) + displayWidthOf(content[0..cursorPos]) + 2

    let wrappedLine = wrapLineWithVerticalBorder(strBuilder.toString())
    print(wrappedLine, flush: true)
    // clear all bytes below
    moveCursor(1, DOWN)
    clearRunes(BEHIND)
    moveCursor(1, UP)

    let extendLine = wrapFileList(files, selectIdx, prefix:String(content).replace("@", ""))
    if (extendLine != String.empty) {
        let colomShift = extendLine.lines().count() - 1
        print(extendLine, flush: true)
        moveCursor(colomShift, UP)
    }
    moveCursor(col:cursorSavePos)
}

private func readlineImplNormal(rune: Rune, prompt: String, history: ArrayList<String>, cursorBox: Box<Int64>,
    buf: LinkedList<Rune>): Option<String> {
    var cursor = cursorBox.value
    var idx = history.size
    match (rune) {
        case r'\r' | r'\n' => // Enter
            let line = String(buf)
            if (line.size > 0) {
                history.add(line)
            }
            redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.Last)
            return Some(line)
        case r'\u{7F}' | r'\b' => // Delete or Backspace
             if (buf.size > 0) {
                if (let Some(rune) <- buf.removeLast()) {
                    let width = displayWidthOf(rune)
                    print("\b \b" * width, flush: true)
                    cursor -= 1
                }
                if (buf.size == 0) {
                    moveCursor(1, UP)
                    moveCursor(col:0)
                    clearRunes(BEHIND)
                    redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.First)
                    cursorBox.value = cursor
                    return None
                }
            }
        case r'\t' => // TAB
            return None
        case r'\u{2191}' => // Up ↑
            if (idx > 0) {
                idx -= 1
                buf.clear()
                for (rr in history[idx].toRuneArray()) {
                    buf.addLast(rr)
                }
                cursor = buf.size
            }
        case r'\u{2193}' => // Down ↓
            if (idx + 1 < history.size) {
                idx += 1
                buf.clear()
                for (rr in history[idx].toRuneArray()) {
                    buf.addLast(rr)
                }
                cursor = buf.size
            } else if (idx + 1 == history.size) {
                idx = history.size
                buf.clear()
                cursor = buf.size
            }
        case r'\u{2190}' => // Left ←
            cursor = max(0, cursor - 1)
        case r'\u{2192}' => // Right →
            cursor = min(buf.size, cursor + 1)
        case _ =>
            // Add the current rune to the input buffer
            if (cursor == buf.size) {
                buf.addLast(rune)
            } else {
                let node = buf.nodeAt(cursor).getOrThrow()
                buf.addBefore(node, rune)
            }
            cursor += 1
    }
    cursorBox.value = cursor
    redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.Mid)
    return None
}

private func readlineImplAt(rune: Rune, prompt: String, history: ArrayList<String>, cursorBox: Box<Int64>,
    selectIdxBox: Box<Int64>, buf: LinkedList<Rune>): Option<String> {
    var cursor = cursorBox.value
    var idx = history.size
    var selectIdx = selectIdxBox.value
    var fileArr = listFiles("", prefix: String(buf).replace("@", ""))
    match (rune) {
        case r'\r' | r'\n' => // Enter
            let line = String(buf)
            if (line.size > 0) {
                history.add(line)
            }
            moveCursor(1, UP)
            moveCursor(col:0)
            clearRunes(BEHIND)
            redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.Last)
            return Some(line)
        case r'\u{7F}' | r'\b' => // Delete or Backspace
            if (buf.size > 0) {
                if (let Some(rune) <- buf.removeLast()) {
                    let width = displayWidthOf(rune)
                    print("\b \b" * width, flush: true)
                    cursor -= 1
                    selectIdx = 0
                }
                if (buf.size == 0) {
                    moveCursor(1, UP)
                    moveCursor(col:0)
                    clearRunes(BEHIND)
                    redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.First)
                    cursorBox.value = cursor
                    selectIdxBox.value = 0
                    return None
                }
            }
        case r'\t' => //TAB
            let fstr = '@${fileArr[selectIdx]}'
            buf.clear()
            for (rr in fstr.toRuneArray()) {
                buf.addLast(rr)
            }
            selectIdx = 0
            cursor = buf.size
        case r'\u{2191}' => // Up ↑
            var tempIdx = selectIdx - 1
            selectIdx = if (tempIdx < 0) {
                fileArr.size - 1
            } else {
                tempIdx
            }
        case r'\u{2193}' => // Down ↓
            if (fileArr.size == 0) {
                selectIdx = 0
            } else {
                selectIdx = (selectIdx + 1) % fileArr.size
            }
        case r'\u{2190}' => // Left ←
            cursor = max(0, cursor - 1)
        case r'\u{2192}' => // Right →
            cursor = min(buf.size, cursor + 1)
        case _ =>
            // Add the current rune to the input buffer
            if (cursor == buf.size) {
                buf.addLast(rune)
            } else {
                let node = buf.nodeAt(cursor).getOrThrow()
                buf.addBefore(node, rune)
            }
            cursor += 1
    }
    cursorBox.value = cursor
    selectIdxBox.value = selectIdx
    fileArr = listFiles("", prefix: String(buf).replace("@", ""))
    redrawAt(prompt, buf.toArray(), cursor, selectIdx, fileArr, phase: DrawPhase.Mid)
    return None
}

private func readlineImpl(prompt: String, history: ArrayList<String>): Option<String> {
    var buf = LinkedList<Rune>()
    let cursor = Box<Int64>(0)
    let selectIdx = Box<Int64>(0)
    redraw(prompt, buf.toArray(), cursor.value, phase: DrawPhase.First)

    while (true) {
        let rune = if (let Some(r) <- RawInputUtils.rawGetRune()) {
            r
        } else {
            return None // EOF
        }
        let firstRune = buf.first.getOrDefault({=> rune})

        let lnOp = if (firstRune == r'@') {
            readlineImplAt(rune, prompt, history, cursor, selectIdx, buf)
        } else {
            readlineImplNormal(rune, prompt, history, cursor, buf)
        }
        if (let Some(ln) <- lnOp) {
            return ln
        }
    }
    return None
}

public class Readline {
    private let history: ArrayList<String>
    private let historyFile: Option<Path>

    public init() {
        this.history = ArrayList<String>()
        this.historyFile = None
    }

    public init(path: Path) {
        this.history = ArrayList<String>()
        this.historyFile = path
        this.loadHistoryFile(path)
    }

    private func loadHistoryFile(path: Path): Unit {
        if (!exists(path)) {
            return
        }
        try {
            let content = String.fromUtf8(File.readFrom(path))
            for (line in content.split("\n")) {
                if (!line.isEmpty()) {
                    this.history.add(line)
                }
            }
        } catch (e: Exception) {
            LogUtils.error("Failed to read readline history file")
        }
    }

    private func appendHistoryFile(line: String): Unit {
        if (line.isEmpty()) {
            return
        }
        if (let Some(path) <- this.historyFile) {
            File.appendTo(path, "${line}\n".toArray())
        }
    }

    public func readline(prompt: String): Option<String> {
        try {
            RawInputUtils.rawEnter()
            if (let Some(line) <- readlineImpl(prompt, this.history)) {
                this.appendHistoryFile(line)
                return line
            }
            return None
        } finally {
            RawInputUtils.rawExit()
        }
    }

    public func readLineBlock(prompt: String): Option<String> {
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
