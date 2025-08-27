package cli.utils

import magic.log.LogUtils
import std.collection.{ArrayList, LinkedList}
import std.regex.Regex
import std.deriving.*
import std.fs.{File, Path, exists}
import cli.core.config.CliConfig

class Command {
    public Command(let trigger: Rune, let cmd: String, let visual: Bool) {
    }
    prop pure: String {
        get() {
            if (visual) {
                this.cmd.replace(trigger.toString(), "")
            } else {
                this.cmd
            }
        }
    }
    prop full: String {
        get() {
            this.cmd
        }
    }
}
/**
 * combine buf and rune and get lat command starts with Trigger
 */
func detectTrigger(buf: Collection<Rune>, rune: Rune, trigger: Rune, prefixOnly!: Bool = false): Bool {
    if (rune == r' ') {
        LogUtils.info("EMPTY RUNE!!!!")
        return false
    }
    if (prefixOnly) {
        return (buf.toArray().get(0) ?? rune) == trigger
    }
    // not prefix only
    if (rune == trigger) {
        return true
    }
    let arr = buf.toArray()
    if (let Some(index) <- arr.lastIndexOf(trigger)) {
        return !String(arr[index..arr.size]).contains(' ')
    } else {
        return false
    }
}

private func getCommand(buf: Collection<Rune>, rune: Rune, trigger: Rune, prefixOnly!: Bool = false,
    visual!: Bool = false): Option<Command> {
    if (rune == trigger && !prefixOnly) {
        return Command(trigger, trigger.toString(), visual)
    }

    let arr: Array<Rune>
    if (CONTROL_RUNES.contains(rune) || rune == r'\0') {
        arr = buf.toArray()
    } else {
        let runeLst = ArrayList<Rune>(buf)
        runeLst.add(rune)
        arr = runeLst.toArray()
    }

    if (prefixOnly) {
        return Command(trigger, String(arr), visual)
    }

    if (let Some(index) <- arr.lastIndexOf(trigger)) {
        return Command(trigger, String(arr[index..arr.size]), visual)
    }
    return None
}

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
        clearScreen(EntireLine)
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
    clearScreen(EntireLine)
    // Construct the content and print it
    let strBuilder = StringBuilder()
    strBuilder.append(prompt)
    for (i in 0..content.size) {
        strBuilder.append(content[i])
    }
    var cursorSavePos = displayWidthOf(prompt) + displayWidthOf(content[0..cursorPos]) + 2
    print(wrapLineWithVerticalBorder(strBuilder.toString()), flush: true)
    // clear all bytes below
    moveCursor(1, DOWN)
    clearScreen(AfterCursorScreen)
    // restore curosr
    moveCursor(1, UP)
    moveCursor(col: cursorSavePos)
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

private func redrawCmd(prompt: String, content: Array<Rune>, cmd: Command, cursorPos: Int64, selectIdx: Int64,
    showLst: Array<String>, phase!: DrawPhase) {
    // If it has draw the boxed content,
    // move the cursor to the first line because the current line in at the second line
    if (phase != DrawPhase.First) {
        moveCursor(1, UP)
        clearScreen(EntireLine)
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
    clearScreen(EntireLine)
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
    clearScreen(AfterCursorScreen)
    moveCursor(1, UP)

    let extendLine = wrapShowList(showLst, selectIdx)
    if (extendLine != String.empty) {
        let colomShift = extendLine.lines().count() - 1
        print(extendLine, flush: true)
        moveCursor(colomShift, UP)
    }
    moveCursor(col: cursorSavePos)
}

private func readlineImplNormal(runeBox: Box<?Rune>, prompt: String, history: ArrayList<String>, cursorBox: Box<Int64>,
    buf: LinkedList<Rune>): Option<String> {
    let rune = runeBox.value.getOrThrow()
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
                    cursorBox.value = cursor
                    runeBox.value = r'\0'
                    redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.Mid)
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
        case r'\0' => //SPECIAL MEANS DO NOTHING EXCEPT SHOW
            runeBox.value = None
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
    runeBox.value = None
    redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.Mid)
    return None
}

private func readlineImplCmdLst(runeBox: Box<?Rune>, prompt: String, history: ArrayList<String>, cursorBox: Box<Int64>,
    selectIdxBox: Box<Int64>, buf: LinkedList<Rune>): Option<String> {
    let rune = runeBox.value.getOrThrow()
    var cursor = cursorBox.value
    var idx = history.size
    var selectIdx = selectIdxBox.value
    var cmd = getCommand(buf, rune, r'/', prefixOnly: true).getOrThrow()
    var cmdArr = listCmds(prefix: cmd.pure)
    match (rune) {
        case r'\r' | r'\n' => // Enter
            let line = String(buf)
            if (line.size > 0) {
                history.add(line)
            }
            if (cmdArr.size == 0) {
                moveCursor(1, UP)
                moveCursor(col: 0)
                clearScreen(AfterCursorScreen)
                moveCursor(1, DOWN)
                redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.Last)
                return Some(line)
            } else {
                let cmdStr = '${cmdArr[selectIdx]}'
                let line = String(buf).removeSuffix(cmd.full) + cmdStr
                buf.clear()
                for (rr in line.toRuneArray()) {
                    buf.addLast(rr)
                }
                selectIdx = 0
                cursor = buf.size
                cmdArr = listCmds(prefix: cmdStr)
                cmd = Command(r'/', cmdStr, false)
            }
        case r'\u{7F}' | r'\b' => // Delete or Backspace
            if (buf.size > 0) {
                if (let Some(rune) <- buf.removeLast()) {
                    let width = displayWidthOf(rune)
                    print("\b \b" * width, flush: true)
                    cursor -= 1
                    selectIdx = 0
                }
                if (let Some(command) <- getCommand(buf, rune, r'/', prefixOnly: true)) {
                    cmd = command
                    cmdArr = listCmds(prefix: cmd.full)
                } else {
                    moveCursor(1, UP)
                    moveCursor(col: 0)
                    clearScreen(AfterCursorScreen)
                    redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.First)
                    cursorBox.value = cursor
                    selectIdxBox.value = 0
                    runeBox.value = r'\0'
                    return None
                }
            }
        case r'\t' => //TAB
            if (cmdArr.size > 0) {
                let cmdStr = '${cmdArr[selectIdx]}'
                let line = String(buf).removeSuffix(cmd.full) + cmdStr
                buf.clear()
                for (rr in line.toRuneArray()) {
                    buf.addLast(rr)
                }
                selectIdx = 0
                cursor = buf.size
                cmdArr = listCmds(prefix: cmdStr)
                cmd = Command(r'/', cmdStr, false)
            }
        case r'\u{2191}' => // Up ↑
            var tempIdx = selectIdx - 1
            selectIdx = if (tempIdx < 0) {
                cmdArr.size - 1
            } else {
                tempIdx
            }
        case r'\u{2193}' => // Down ↓
            if (cmdArr.size == 0) {
                selectIdx = 0
            } else {
                selectIdx = (selectIdx + 1) % cmdArr.size
            }
        case r'\u{2190}' => // Left ←
            cursor = max(0, cursor - 1)
        case r'\u{2192}' => // Right →
            cursor = min(buf.size, cursor + 1)
        case r'\0' => //SPECIAL MEANS DO NOTHING EXCEPT SHOW
            runeBox.value = None
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
    runeBox.value = None
    redrawCmd(prompt, buf.toArray(), cmd, cursor, selectIdx, cmdArr, phase: DrawPhase.Mid)
    return None
}

private func readlineImplAt(runeBox: Box<?Rune>, prompt: String, history: ArrayList<String>, cursorBox: Box<Int64>,
    selectIdxBox: Box<Int64>, buf: LinkedList<Rune>): Option<String> {
    let rune = runeBox.value.getOrThrow()
    var cursor = cursorBox.value
    var idx = history.size
    var selectIdx = selectIdxBox.value
    var cmd = getCommand(buf, rune, r'@', visual: true).getOrThrow()
    var fileArr = listFiles(prefix: cmd.pure)
    match (rune) {
        case r'\r' | r'\n' => // Enter
            let line = String(buf)
            if (line.size > 0) {
                history.add(line)
            }
            if (fileArr.size == 0) {
                moveCursor(1, UP)
                moveCursor(col: 0)
                clearScreen(AfterCursorScreen)
                moveCursor(1, DOWN)
                redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.Last)
                return Some(line)
            } else {
                let fstr = '@${fileArr[selectIdx]}'
                let line = String(buf).removeSuffix(cmd.full) + fstr
                buf.clear()
                for (rr in line.toRuneArray()) {
                    buf.addLast(rr)
                }
                selectIdx = 0
                cursor = buf.size
                fileArr = listFiles(prefix: fstr.replace("@", ""))
                cmd = Command(r'@', fstr, true)
            }
        case r'\u{7F}' | r'\b' => // Delete or Backspace
            if (buf.size > 0) {
                if (let Some(rune) <- buf.removeLast()) {
                    let width = displayWidthOf(rune)
                    print("\b \b" * width, flush: true)
                    cursor -= 1
                    selectIdx = 0
                }
                if (let Some(command) <- getCommand(buf, rune, r'@', visual: true)) {
                    cmd = command
                    fileArr = listFiles(prefix: cmd.pure)
                } else {
                    moveCursor(1, UP)
                    moveCursor(col: 0)
                    clearScreen(AfterCursorScreen)
                    redraw(prompt, buf.toArray(), cursor, phase: DrawPhase.First)
                    cursorBox.value = cursor
                    selectIdxBox.value = 0
                    runeBox.value = r'\0'
                    return None
                }
            }
        case r'\t' => //TAB
            if (fileArr.size > 0) {
                let fstr = '@${fileArr[selectIdx]}'
                let line = String(buf).removeSuffix(cmd.full) + fstr
                buf.clear()
                for (rr in line.toRuneArray()) {
                    buf.addLast(rr)
                }
                selectIdx = 0
                cursor = buf.size
                fileArr = listFiles(prefix: fstr.replace("@", ""))
                cmd = Command(r'@', fstr, true)
            }
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
        case r'\0' => //SPECIAL MEANS DO NOTHING EXCEPT SHOW
            runeBox.value = None
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
    runeBox.value = None
    redrawCmd(prompt, buf.toArray(), cmd, cursor, selectIdx, fileArr, phase: DrawPhase.Mid)
    return None
}

private func readlineImpl(prompt: String, history: ArrayList<String>): Option<String> {
    var buf = LinkedList<Rune>()
    let cursor = Box<Int64>(0)
    let selectIdx = Box<Int64>(0)
    let runeBox = Box<Option<Rune>>(None)
    redraw(prompt, buf.toArray(), cursor.value, phase: DrawPhase.First)

    while (true) {
        let rune = if (let Some(r) <- runeBox.value) {
            r
        } else if (let Some(r) <- RawInputUtils.rawGetRune()) {
            r
        } else {
            return None // EOF
        }
        runeBox.value = rune
        let lnOp = if (detectTrigger(buf, rune, r'@')) {
            readlineImplAt(runeBox, prompt, history, cursor, selectIdx, buf)
        } else if (detectTrigger(buf, rune, r'/', prefixOnly: true)) {
            readlineImplCmdLst(runeBox, prompt, history, cursor, selectIdx, buf)
        } else {
            readlineImplNormal(runeBox, prompt, history, cursor, buf)
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
