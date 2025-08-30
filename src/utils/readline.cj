package cli.utils

import magic.log.LogUtils
import std.collection.{ArrayList, LinkedList}
import std.regex.Regex
import std.deriving.*
import std.fs.{File, Path, exists}
import cli.core.config.CliConfig

@Derive[Equatable]
private enum DrawPhase {
    | First
    | Last
    | Mid
}

private class Page {
    public Page(let prefix: String, let content: String, let cursor: Int64) {}
}

private class UnderList {
    public UnderList(let selectIdx: Int64, let showList: Array<String>) {}
}

private class Draw {
    public Draw(let page: Page, let underList: UnderList) {}
}
/**
 * Clear the line and redraw it
 */
private func redraw(curDraw: Draw, preDraw: Draw, phase!: DrawPhase) {
    let pPage = preDraw.page
    let pWrapped = wrapBox("${pPage.prefix}${pPage.content}")
    let (pRow, _) = calculateCursorPos(pWrapped, pPage.cursor, prefix: pPage.prefix)
    // If it has draw the boxed content,
    // move the cursor to the first line because the current line in at the second line
    if (phase != DrawPhase.First) {
        moveCursor(pRow + 1, UP)
        moveCursor(col: 0)
        clearScreen(AfterCursorScreen)
    }

    let page = curDraw.page
    let wrapped = wrapBox("${page.prefix}${page.content}")
    let totalLines = wrapped.lines().count()
    let (cRow, cCol) = calculateCursorPos(wrapped, page.cursor, prefix: page.prefix)
    print(wrapped, flush: true)
    if (phase == DrawPhase.Last) {
        print("\n", flush: true)
        return
    }

    let extendLine = wrapShowList(curDraw.underList.showList, curDraw.underList.selectIdx)
    if (extendLine != String.empty) {
        let colomShift = extendLine.lines().count() - 1
        print(extendLine, flush: true)
        moveCursor(colomShift, UP)
    }

    moveCursor(totalLines - cRow - 2, UP)
    moveCursor(col: cCol)
}

private func readlineImpl(buf: LinkedList<Rune>, rune: Rune, prompt: String, history: ArrayList<String>,
    cursorBox: Box<Int64>, selectIdxBox: Box<Int64>): Option<String> {
    var cursor = cursorBox.value
    var idx = history.size
    var selectIdx = selectIdxBox.value
    var command = detectCommand(buf, rune)
    var showList = listCmdsStr(command)
    let orgDraw = Draw(Page(prompt, String(buf), cursor), UnderList(selectIdx, showList))
    match (rune) {
        case r'\r' | r'\n' => // Enter
            let line = String(buf)
            if (line.size > 0) {
                history.add(line)
            }
            if (let Some(cmd) <- command && showList.size > 0) {
                let showItem = cmd.toFull(showList[selectIdx])
                let line = String(buf).removeSuffix(cmd.full) + showItem
                buf.clear()
                for (rr in line.toRuneArray()) {
                    buf.addLast(rr)
                }
                selectIdx = 0
                cursor = buf.size
                command = Command(showItem, cmd.option)
                showList = listCmdsStr(command)
            } else {
                redraw(orgDraw, orgDraw, phase: DrawPhase.Last)
                return Some(line)
            }
        case r'\u{7F}' | r'\b' => // Delete or Backspace
            if (buf.size > 0) {
                if (let Some(rune) <- buf.removeLast()) {
                    let width = displayWidthOf([rune])
                    print("\b \b" * width, flush: true)
                    cursor -= 1
                    selectIdx = 0
                }
                if (let Some(cmd) <- detectCommand(buf, None)) {
                    showList = listCmdsStr(cmd)
                }
            }
        case r'\t' => // TAB
            if (let Some(cmd) <- command && showList.size > 0) {
                let showItem = cmd.toFull(showList[selectIdx])
                let line = String(buf).removeSuffix(cmd.full) + showItem
                buf.clear()
                for (rr in line.toRuneArray()) {
                    buf.addLast(rr)
                }
                selectIdx = 0
                cursor = buf.size
                command = Command(showItem, cmd.option)
                showList = listCmdsStr(command)
            } else { // DO NOTHING
                return None
            }
        case r'\u{2191}' => // Up ↑
            if (let Some(cmd) <- command) {
                var tempIdx = selectIdx - 1
                selectIdx = if (tempIdx < 0) {
                    showList.size - 1
                } else {
                    tempIdx
                }
            } else {
                if (idx > 0) {
                    idx -= 1
                    buf.clear()
                    for (rr in history[idx].toRuneArray()) {
                        buf.addLast(rr)
                    }
                    cursor = buf.size
                }
            }
        case r'\u{2193}' => // Down ↓
            if (let Some(cmd) <- command) {
                if (showList.size == 0) {
                    selectIdx = 0
                } else {
                    selectIdx = (selectIdx + 1) % showList.size
                }
            } else {
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
            }
        case r'\u{2190}' => // Left ←
            cursor = max(0, cursor - 1)
        case r'\u{2192}' => // Right →
            cursor = min(buf.size, cursor + 1)
        case r'\u{1B}' => // ESC
            return None // TODO - Do Something
        case r'!' =>
            if (let Some(cmd) <- command) { // MODE CHANGE COMMAND
                moveCursor(1, UP)
                moveCursor(col: 0)
                clearScreen(AfterCursorScreen)
                return Some('!')
            } else {
                // Add the current rune to the input buffer
                if (cursor == buf.size) {
                    buf.addLast(rune)
                } else {
                    let node = buf.nodeAt(cursor).getOrThrow()
                    buf.addBefore(node, rune)
                }
                cursor += 1
            }
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
    let curDraw = Draw(Page(prompt, String(buf), cursor), UnderList(selectIdx, showList))
    redraw(curDraw, orgDraw, phase: DrawPhase.Mid)
    cursorBox.value = cursor
    selectIdxBox.value = selectIdx
    return None
}

private func readlineImpl(prompt: String, history: ArrayList<String>): Option<String> {
    var buf = LinkedList<Rune>()
    let cursor = Box<Int64>(0)
    let selectIdx = Box<Int64>(0)
    let rawPage = Draw(Page(prompt, String(buf), cursor.value), UnderList(0, []))
    redraw(rawPage, rawPage, phase: DrawPhase.First)

    while (true) {
        let rune = if (let Some(r) <- RawInputUtils.rawGetRune()) {
            r
        } else {
            return None // EOF
        }
        let lnOp = readlineImpl(buf, rune, prompt, history, cursor, selectIdx)
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

public class ListenEsc {
    public static func listen(): ?String {
        try {
            RawInputUtils.rawEnter()
            if (RawInputUtils.listenEscRune()) {
                return '\u{1B}'
            } else {
                return None
            }
        } finally {
            RawInputUtils.rawExit()
        }
    }
}
