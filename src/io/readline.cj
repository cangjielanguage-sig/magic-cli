package cli.io

import magic.log.LogUtils
import std.collection.{ArrayList, LinkedList, collectArray, filter, map}
import std.regex.Regex
import std.deriving.*
import std.fs.{File, Path, exists}
import cli.core.config.CliConfig

/**
 * Input state management
 */
private class InputState {
    public var buffer: LinkedList<Rune>
    public var cursor: Int64
    public var historyIndex: Int64

    public init() {
        this.buffer = LinkedList<Rune>()
        this.cursor = 0
        this.historyIndex = 0
    }

    /**
     * Check if shell mode is active (input starts with !)
     */
    public func isShellMode(): Bool {
        if (this.buffer.size == 0) {
            return false
        }
        return (this.buffer.first ?? r' ') == r'!'
    }

    public func clear() {
        this.buffer.clear()
        this.cursor = 0
    }

    public func getText(): String {
        return String(this.buffer)
    }

    public func insertChar(char: Rune) {
        if (this.cursor == this.buffer.size) {
            this.buffer.addLast(char)
        } else {
            let node = this.buffer.nodeAt(this.cursor).getOrThrow()
            this.buffer.addBefore(node, char)
        }
        this.cursor += 1
    }

    public func deleteChar(): Bool {
        if (this.buffer.size > 0 && this.cursor > 0) {
            if (let Some(node) <- this.buffer.nodeAt(this.cursor - 1)) {
                this.buffer.remove(node)
                this.cursor -= 1
                return true
            }
        }
        return false
    }

    public func deleteCharAt(): Bool {
        if (this.buffer.size > 0 && this.cursor < this.buffer.size) {
            if (let Some(node) <- this.buffer.nodeAt(this.cursor)) {
                this.buffer.remove(node)
                // Cursor stays at same position (character after gets pulled back)
                return true
            }
        }
        return false
    }

    public func moveCursorLeft() {
        this.cursor = max(0, this.cursor - 1)
    }

    public func moveCursorRight() {
        this.cursor = min(this.buffer.size, this.cursor + 1)
    }

    public func setFromHistory(text: String) {
        this.clear()
        for (char in text.toRuneArray()) {
            this.buffer.addLast(char)
        }
        this.cursor = this.buffer.size
    }
}

/**
 * Completion state management
 */
private class CompletionState {
    public var completions: Array<String>
    public var selectedIndex: Int64
    public var isActive: Bool

    public init() {
        this.completions = []
        this.selectedIndex = 0
        this.isActive = false
    }

    public func setCompletions(completions: Array<String>) {
        this.completions = completions
        this.selectedIndex = 0
        this.isActive = completions.size > 0
    }

    public func clear() {
        this.completions = []
        this.selectedIndex = 0
        this.isActive = false
    }

    public func moveUp() {
        if (this.isActive && this.completions.size > 0) {
            this.selectedIndex = if (this.selectedIndex > 0) {
                this.selectedIndex - 1
            } else {
                this.completions.size - 1
            }
        }
    }

    public func moveDown() {
        if (this.isActive && this.completions.size > 0) {
            this.selectedIndex = (this.selectedIndex + 1) % this.completions.size
        }
    }

    public func getSelected(): Option<String> {
        if (this.isActive && this.selectedIndex < this.completions.size) {
            return this.completions[this.selectedIndex]
        }
        return None
    }
}

/**
 * Display context for rendering
 */
private class DisplayContext {
    public let prompt: String
    public var lastRenderedLines: Int64
    public var terminalWidth: Int64

    public init(prompt: String) {
        this.prompt = prompt
        this.lastRenderedLines = 0
        this.terminalWidth = 80 // Default width, could be detected from terminal
    }
}

/**
 * Extract @path context based on cursor position
 * Returns (atIndex, pathStart, pathEnd, pathPrefix) or None
 */
private func extractPathContext(text: String, cursor: Int64): Option<(Int64, Int64, Int64, String)> {
    let runes = text.toRuneArray()

    // Find the last @ symbol before the current cursor
    var atIndex: Int64 = -1
    let maxIndex = min(cursor, runes.size)
    for (i in 0..maxIndex) {
        let reverseIndex = maxIndex - 1 - i
        if (reverseIndex >= 0 && runes[reverseIndex] == r'@') {
            atIndex = reverseIndex
            break
        }
    }

    if (atIndex == -1) {
        return None
    }

    // Find the first space after the @ symbol
    let pathStart = atIndex + 1
    var pathEnd = runes.size
    for (i in pathStart..runes.size) {
        if (runes[i] == r' ') {
            pathEnd = i
            break
        }
    }

    // Check if the first space is before the current cursor
    // If there's a space before cursor, the path has ended and no completion should show
    if (pathEnd < cursor) {
        return None // Path has ended before cursor
    }

    // Extract path prefix up to cursor position
    let pathPrefix = String(runes[pathStart..cursor])

    return Some((atIndex, pathStart, pathEnd, pathPrefix))
}

// Command definitions: (command_name, [subcommands])
// Commands without subcommands have empty array
private let COMMANDS: Array<(String, Array<String>)> = [
    ("/help", []),
    ("/clear", []),
    ("/compact", []),
    ("/memory", []),
    ("/init", []),
    ("/exit", []),
    ("/mcp", ["add", "add-sse", "remove"]),
    ("/conversation", ["list", "save", "load", "delete", "rename"]),
    ("/cmd", ["list", "add", "remove", "edit"])
]

/**
 * Build completion list based on current input and cursor position
 * Supports both /commands and @paths (but @paths are disabled in shell mode)
 */
private func buildCompletionList(input: String, cursor: Int64, isShellMode!: Bool = false): Option<Array<String>> {
    let text = input
    if (text.isEmpty()) {
        return None
    }

    // Check for @path completion based on cursor position (disabled in shell mode)
    if (!isShellMode) {
        if (let Some((atIndex, pathStart, pathEnd, pathPrefix)) <- extractPathContext(text, cursor)) {
            let pathCompletions = getPathCompletionList(prefix: pathPrefix)
            if (pathCompletions.size > 0) {
                // For empty prefix (just "@"), show all files
                // For non-empty prefix, show paths that start with prefix but are different
                if (pathPrefix.isEmpty()) {
                    return pathCompletions
                } else {
                    return pathCompletions |>
                        filter { path => path.startsWith(pathPrefix) && path != pathPrefix } |>
                        collectArray
                }
            }
        }
    }

    // Check for /command completion (only at beginning and cursor at end)
    if (!text.startsWith("/") || cursor != text.size) {
        return None
    }

    let allCompletions = ArrayList<String>()

    // Generate all possible completions from command definitions
    for ((commandName, subcommands) in COMMANDS) {
        // Add the base command if it matches
        if (commandName.startsWith(text) && commandName != text) {
            allCompletions.add(commandName)
        }

        // Add subcommands if they match
        if (subcommands.size > 0) {
            for (subcommand in subcommands) {
                let fullSubcommand = commandName + " " + subcommand
                if (fullSubcommand.startsWith(text) && fullSubcommand != text) {
                    allCompletions.add(fullSubcommand)
                }
            }
        }
    }

    let results = allCompletions.toArray()
    if (results.size > 0) {
        return results
    }

    return None
}

/**
 * Calculate cursor position in wrapped boxed content
 * Uses existing calculateCursorPos function to calculate cursor position
 */
private func calculateCursorPosition(text: String, cursor: Int64, prefix: String): (Int64, Int64) {
    // Use wrapBox to wrap text, then use existing calculateCursorPos function
    let wrappedContent = wrapBox(text)
    return calculateCursorPos(wrappedContent, cursor, prefix: prefix)
}

// Removed wrapText function, use wrapBox instead

/**
 * Render completion list using existing wrapShowList function
 */
private func renderCompletionList(completions: Array<String>, selectedIndex: Int64): String {
    return wrapShowList(completions, selectedIndex)
}

/**
 * Clear previous render and move cursor to start
 * Uses existing moveCursor and clearScreen functions
 */
private func clearPreviousRender(lines: Int64) {
    if (lines > 0) {
        moveCursor(lines, direction: Direction.Up)
        moveCursor(col: 0)
        clearScreen(mode: ClearMode.AfterCursorScreen)
    }
}

/**
 * Enhanced Readline implementation with improved UI and completion
 */
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

    /**
     * Handle key input and return result
     */
    private func handleInput(
        rune: Rune,
        inputState: InputState,
        completionState: CompletionState,
        displayContext: DisplayContext
    ): Option<String> {
        match (rune) {
            case r'\r' | r'\n' => // Enter
                let text = inputState.getText()

                // Always finalize input on Enter, don't auto-complete
                if (text.size > 0) {
                    this.history.add(text)
                    this.appendHistoryFile(text)
                }
                return text

            case r'\u{7F}' | r'\b' => // Backspace - delete character before cursor
                if (inputState.deleteChar()) {
                    // Always clear completions when deleting characters
                    completionState.clear()

                    // Update completion list based on new text
                    let newText = inputState.getText()
                    if (!newText.isEmpty()) {
                        if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                            completionState.setCompletions(completions)
                        }
                    }
                }
                return None

            case r'\u{4}' => // Delete key - delete character at cursor (forward delete)
                // This is mapped from ESC[3~ in the C FFI
                if (inputState.deleteCharAt()) {
                    // Always clear completions when deleting characters
                    completionState.clear()

                    // Update completion list based on new text
                    let newText = inputState.getText()
                    if (!newText.isEmpty()) {
                        if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                            completionState.setCompletions(completions)
                        }
                    }
                }
                return None

            case r'\t' => // Tab
                if (completionState.isActive) {
                    if (let Some(selected) <- completionState.getSelected()) {
                        let currentText = inputState.getText()
                        var newText = ""
                        var newCursor: Int64 = inputState.cursor

                        // Handle @path completion
                        if (let Some((atIndex, pathStart, pathEnd, pathPrefix)) <- extractPathContext(currentText, inputState.cursor)) {
                            // Replace the path part with selected path
                            let beforePath = currentText[0..pathStart]
                            let afterPath = currentText[pathEnd..]
                            newText = beforePath + selected + afterPath
                            // Set cursor to end of inserted path
                            newCursor = beforePath.size + selected.size
                        }
                        // Handle /command completion
                        else if (currentText.startsWith("/")) {
                            newText = selected
                            newCursor = selected.size
                        }
                        else {
                            newText = selected
                            newCursor = selected.size
                        }

                        // Replace buffer with new text
                        inputState.clear()
                        for (char in newText.toRuneArray()) {
                            inputState.buffer.addLast(char)
                        }
                        inputState.cursor = newCursor
                        completionState.clear()

                        // Update completion list for further completions
                        if (let Some(newCompletions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                            completionState.setCompletions(newCompletions)
                        }
                    }
                }
                return None

            case r'\u{2191}' => // Up ↑
                if (completionState.isActive) {
                    completionState.moveUp()
                } else {
                    // Navigate history
                    if (inputState.historyIndex > 0) {
                        inputState.historyIndex -= 1
                        inputState.setFromHistory(this.history[inputState.historyIndex])
                    }
                }
                return None

            case r'\u{2193}' => // Down ↓
                if (completionState.isActive) {
                    completionState.moveDown()
                } else {
                    // Navigate history
                    if (inputState.historyIndex + 1 < this.history.size) {
                        inputState.historyIndex += 1
                        inputState.setFromHistory(this.history[inputState.historyIndex])
                    } else if (inputState.historyIndex + 1 == this.history.size) {
                        inputState.historyIndex = this.history.size
                        inputState.clear()
                    }
                }
                return None

            case r'\u{2190}' => // Left ←
                inputState.moveCursorLeft()
                // Update completion list after cursor movement
                let newText = inputState.getText()
                if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                    completionState.setCompletions(completions)
                } else {
                    completionState.clear()
                }
                return None

            case r'\u{2192}' => // Right →
                inputState.moveCursorRight()
                // Update completion list after cursor movement
                let newText = inputState.getText()
                if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                    completionState.setCompletions(completions)
                } else {
                    completionState.clear()
                }
                return None

            case r'\u{1B}' => // ESC
                return None // Could be used to cancel completion or exit


            case _ => // Regular character
                inputState.insertChar(rune)

                // Update completion list
                let newText = inputState.getText()
                if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                    completionState.setCompletions(completions)
                } else {
                    completionState.clear()
                }
                return None
        }
    }

    /**
     * Render the current state following the original redraw pattern
     * Uses existing drawing functions and box style with proper positioning
     * Different colors are used in shell mode
     */
    private func render(
        inputState: InputState,
        completionState: CompletionState,
        displayContext: DisplayContext,
        isFirst!: Bool = false
    ) {
        // Create current and previous drawing state
        let currentText = inputState.getText()
        let isShellMode = inputState.isShellMode()

        // Use different colors for shell mode
        let boxColor = if (isShellMode) { BRIGHT_YELLOW } else { BRIGHT_BLACK }
        let textColor = if (isShellMode) { BRIGHT_GREEN } else { "" }

        // Apply colors to both prompt and text in shell mode
        let displayPrompt = if (isShellMode) {
            "${textColor}${displayContext.prompt}${RESET}"
        } else {
            displayContext.prompt
        }

        let displayText = if (isShellMode) {
            "${textColor}${currentText}${RESET}"
        } else {
            currentText
        }

        let wrappedContent = wrapBox("${displayPrompt}${displayText}", boxColor: boxColor)

        // Calculate cursor position for current state
        // Use original text for cursor calculation (without color codes)
        let cursorWrappedContent = wrapBox("${displayContext.prompt}${currentText}", boxColor: boxColor)
        let (cursorRow, cursorCol) = calculateCursorPos(
            cursorWrappedContent,
            inputState.cursor,
            prefix: displayContext.prompt
        )

        // Clear previous render (similar to original redraw logic)
        if (!isFirst && displayContext.lastRenderedLines > 0) {
            // Move up based on previous cursor position + 1, like original implementation
            moveCursor(displayContext.lastRenderedLines, direction: Direction.Up)
            moveCursor(col: 0)
            clearScreen(mode: ClearMode.AfterCursorScreen)
        }

        // Print the wrapped content
        PrintUtils.printString(wrappedContent)

        // Handle completion list (similar to extendLine in original)
        if (completionState.isActive) {
            let completionText = renderCompletionList(
                completionState.completions,
                completionState.selectedIndex
            )
            if (!completionText.isEmpty()) {
                let completionLines = completionText.lines().count() - 1
                PrintUtils.printString(completionText)
                // Move cursor up by completion lines (like original colomShift)
                if (completionLines > 0) {
                    moveCursor(completionLines, direction: Direction.Up)
                }
            }
        }

        // Move cursor to correct position (following original pattern)
        let totalLines = wrappedContent.lines().count()
        let linesToMoveUp = totalLines - cursorRow - 2  // -2 like in original
        if (linesToMoveUp > 0) {
            moveCursor(linesToMoveUp, direction: Direction.Up)
        }
        moveCursor(col: cursorCol)

        // Store cursor row for next cycle (not total lines)
        displayContext.lastRenderedLines = cursorRow + 1
    }

    /**
     * Final render when input is complete (similar to DrawPhase.Last)
     * Positions cursor at the bottom of the input box
     * Uses shell mode colors if active
     */
    private func renderFinal(inputState: InputState, displayContext: DisplayContext) {
        let currentText = inputState.getText()
        let isShellMode = inputState.isShellMode()

        // Use different colors for shell mode
        let boxColor = if (isShellMode) { BRIGHT_YELLOW } else { BRIGHT_BLACK }
        let textColor = if (isShellMode) { BRIGHT_GREEN } else { "" }

        // Apply colors to both prompt and text in shell mode
        let displayPrompt = if (isShellMode) {
            "${textColor}${displayContext.prompt}${RESET}"
        } else {
            displayContext.prompt
        }

        let displayText = if (isShellMode) {
            "${textColor}${currentText}${RESET}"
        } else {
            currentText
        }

        let wrappedContent = wrapBox("${displayPrompt}${displayText}", boxColor: boxColor)

        // Clear previous render
        if (displayContext.lastRenderedLines > 0) {
            moveCursor(displayContext.lastRenderedLines, direction: Direction.Up)
            moveCursor(col: 0)
            clearScreen(mode: ClearMode.AfterCursorScreen)
        }

        // Print the final content
        PrintUtils.printString(wrappedContent)

        // Print newline and position cursor at bottom (like DrawPhase.Last)
        PrintUtils.printLine("")
    }

    /**
     * Main readline function
     */
    public func readline(prompt: String): Option<String> {
        try {
            RawInputUtils.rawEnter()

            let inputState = InputState()
            let completionState = CompletionState()
            let displayContext = DisplayContext(prompt)
            inputState.historyIndex = this.history.size

            // Initial render (first time)
            this.render(inputState, completionState, displayContext, isFirst: true)

            while (true) {
                let rune = if (let Some(r) <- RawInputUtils.rawGetRune()) {
                    r
                } else {
                    return None // EOF
                }

                let result = this.handleInput(rune, inputState, completionState, displayContext)

                if (let Some(line) <- result) {
                    // Final render to position cursor at bottom of input box (like DrawPhase.Last)
                    this.renderFinal(inputState, displayContext)
                    return line
                } else {
                    // Re-render after handling input (not first time)
                    this.render(inputState, completionState, displayContext, isFirst: false)
                }
            }

            return None
        } finally {
            RawInputUtils.rawExit()
        }
    }

    /**
     * Simple blocking readline without fancy UI
     */
    public func simpleReadLine(prompt: String): Option<String> {
        PrintUtils.printString(prompt)
        return readln()
    }

    /**
     * Conditional readline based on withBox parameter
     */
    public func readline(prompt: String, withBox!: Bool): Option<String> {
        if (withBox) {
            return this.readline(prompt)
        } else {
            return this.simpleReadLine(prompt)
        }
    }
}