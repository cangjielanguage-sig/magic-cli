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
        r'\u{3400}' <= rune && rune <= r'\u{4dbf}' ||  // Rare characters (Extension A)
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
        print("\u{1b}[1A", flush: true)
        print("\r\u{1B}[K", flush: true)
    }
    if (phase == DrawPhase.Last) {
        print(wrapBox("${prompt}${String(content)}"), flush: true)
        print("\n", flush: true)
        return
    }
    // Draw the box
    print(wrapBox(prompt), flush: true)
    // Move cursor from the third line to the second line
    print("\u{1b}[1A", flush: true)
    // Clear the second line
    print("\r\u{1B}[K", flush: true)
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
    print("\u{1B}[u", flush: true)

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

@When[os != "Windows"]
private func readlineImpl(prompt: String,
                          history: ArrayList<String>): Option<String> {
    var buf = LinkedList<Rune>()
    var cursor = 0
    var idx = history.size

    redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.First)

    while (true) {
        let rune = if (let Some(r) <- RawInputUtils.rawGetRune()) {
            r
        } else {
            return None // EOF
        }
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
                    }
                    cursor -= 1
                }
                continue
            case r'\u{2191}' =>  // Up ↑
                if (idx > 0) {
                    idx -= 1
                    buf = LinkedList(history[idx].toRuneArray())
                    cursor = buf.size
                }
            case r'\u{2193}' =>  // Down ↓
                if (idx + 1 < history.size) {
                    idx += 1
                    buf = LinkedList(history[idx].toRuneArray())
                    cursor = buf.size
                } else if (idx + 1 == history.size) {
                    idx = history.size
                    buf = LinkedList<Rune>()
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
        redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.Mid)
    }
    return None
}

@When[os != "Windows"]
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

    public func readline(prompt: String, withBox!: Bool): Option<String> {
        if (withBox) {
            return readline(prompt)
        } else {
            print(prompt, flush: true)
            return readln()
        }
    }
}

