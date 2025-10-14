package cli.io

/**
 * The status indicator is printed by another thread
 * We need a data structure to hold the thread future and stop the thread
 */
protected class StatusIndicator {
    private var future: Option<Future<Unit>> = None
    private let message: String

    init(message: String) {
        this.message = message
    }

    protected func start(): Unit {
        this.future = spawn {
            this.work()
        }
    }

    static let INDICATORS = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    private func work(): Unit {
        // During the working indicator, we hide the cursor
        hideCursor()
        // Print message once (with space for spinner)
        PrintUtils.printString(
            "  ${message}...".withColor(Theme.MUTED), withIndent: true
        )

        var idx = 0
        while (!Thread.currentThread.hasPendingCancellation) {
            let spinner = INDICATORS[idx % INDICATORS.size]
            PrintUtils.printString("\r") // Move cursor to the start of the line
            if (PrintUtils.CURRENT_INDENT > 0) {
                PrintUtils.printString(" " * PrintUtils.CURRENT_INDENT)
            }
            // Overwrite just the first character (spinner position)
            PrintUtils.printString("${spinner}".withColor(Theme.MUTED))

            sleep(Duration.millisecond * 100)
            idx = (idx + 1) % INDICATORS.size
        }
        clearScreen(mode: ClearMode.EntireLine)
        showCursor()
    }

    protected func stop(): Unit {
        this.future.getOrThrow().cancel()
        this.future.getOrThrow().get()
    }
}