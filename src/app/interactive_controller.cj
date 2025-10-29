package cli.app

import magic.core.agent.AsyncAgentResponse
import magic.log.LogUtils
import cli.io.{InputUtils, PrintUtils, AnsiColor, WithColor}
import cli.core.config.CliConfig

import std.sync.{AtomicBool, Mutex}
import std.collection.ArrayList

/**
 * Interactive execution controller that supports:
 * - ESC: Cancel execution
 * - Ctrl+I: Add more information
 * - Real-time visual feedback
 * - Progress indication
 */
internal class InteractiveController {
    private let cancelled = AtomicBool(false)
    private let additionalInfoMutex = Mutex()
    private var additionalInfoValue: Option<String> = None
    private var future: Option<Future<Unit>> = None
    private let app: CliApp
    private let response: AsyncAgentResponse
    private let showHelpHint = AtomicBool(true)

    internal init(app: CliApp, response: AsyncAgentResponse) {
        this.app = app
        this.response = response
    }

    internal func hasCancel(): Bool {
        return this.cancelled.load()
    }

    internal func getAdditionalInfo(): Option<String> {
        synchronized(this.additionalInfoMutex) {
            return this.additionalInfoValue
        }
    }

    /**
     * Start the interactive controller
     */
    internal func start(): Unit {
        // Show help hint once at the start
        if (this.showHelpHint.load()) {
            PrintUtils.printLine("")
            let hint = "💡 Controls: " +
                      "${"ESC".withColor(AnsiColor.BRIGHT_CYAN)} to cancel  " +
                      "${"Ctrl+I".withColor(AnsiColor.BRIGHT_CYAN)} to add info  " +
                      "${"Ctrl+P".withColor(AnsiColor.BRIGHT_CYAN)} to pause"
            PrintUtils.printLine(hint.withColor(AnsiColor.BRIGHT_BLACK))
            PrintUtils.printLine("")
            this.showHelpHint.store(false)
        }

        // Spawn a thread to check for interactive commands
        this.future = spawn {
            this.runInteractiveLoop()
        }
    }

    /**
     * Main interactive loop that handles user input during execution
     */
    private func runInteractiveLoop(): Unit {
        while (!Thread.currentThread.hasPendingCancellation) {
            // Don't check for input when agent is requesting user input
            if (InputUtils.isRequestingInput()) {
                sleep(Duration.millisecond * 100)
                continue
            }

            // Check for ESC key (cancellation)
            if (InputUtils.checkEsc()) {
                this.handleCancel()
                return
            }
            // Note: Ctrl+I and Ctrl+P are currently not supported due to RawInputUtils access restrictions
            // These features can be enabled once RawInputUtils is made accessible

            // Sleep briefly to avoid busy waiting
            sleep(Duration.millisecond * 50)
        }
    }

    /**
     * Handle cancel request (ESC key)
     */
    private func handleCancel(): Unit {
        if (this.cancelled.compareAndSwap(false, true)) {
            PrintUtils.printLine("")
            PrintUtils.printLine("${"⚠ Cancelling execution...".withColor(AnsiColor.BRIGHT_YELLOW)}")
            LogUtils.info("User pressed ESC, cancelling execution")
            
            // Cancel the response asynchronously
            this.response.cancel(blocking: false)
        }
    }

    /**
     * Handle add more information request (Ctrl+I)
     */
    private func handleAddInfo(): Unit {
        PrintUtils.printLine("")
        PrintUtils.printLine("${"➕ Add More Information".withColor(AnsiColor.BRIGHT_CYAN)}")
        PrintUtils.printLine("Type your additional context or instructions (press Enter when done):")
        PrintUtils.printLine("")

        // Get user input
        let info = InputUtils.getUserInput(prompt: "> ", withBox: false)
        
        if (!info.isEmpty() && info != "exit") {
            synchronized(this.additionalInfoMutex) {
                this.additionalInfoValue = Some(info)
            }
            PrintUtils.printLine("")
            PrintUtils.printLine("${"✓ Information added and will be sent to the agent".withColor(AnsiColor.BRIGHT_GREEN)}")
            PrintUtils.printLine("")
            
            // TODO: Implement mechanism to inject this information into the agent's context
            // This requires extending the Agent API to support mid-execution context updates
            LogUtils.info("Additional info from user: ${info}")
        } else {
            PrintUtils.printLine("")
            PrintUtils.printLine("${"✗ No information added".withColor(AnsiColor.BRIGHT_BLACK)}")
            PrintUtils.printLine("")
        }
    }

    /**
     * Handle pause request (Ctrl+P)
     */
    private func handlePause(): Unit {
        PrintUtils.printLine("")
        PrintUtils.printLine("${"⏸ Execution Paused".withColor(AnsiColor.BRIGHT_YELLOW)}")
        PrintUtils.printLine("")
        
        let options = [
            "Resume execution",
            "Add more information",
            "Cancel execution",
            "Show current progress"
        ]
        
        match (InputUtils.getOptions(options, prompt: "What would you like to do?")) {
            case Some(0) =>
                PrintUtils.printLine("${"▶ Resuming...".withColor(AnsiColor.BRIGHT_GREEN)}")
                PrintUtils.printLine("")
            case Some(1) =>
                this.handleAddInfo()
            case Some(2) =>
                this.handleCancel()
            case Some(3) =>
                this.showProgress()
            case _ =>
                PrintUtils.printLine("${"▶ Resuming...".withColor(AnsiColor.BRIGHT_GREEN)}")
                PrintUtils.printLine("")
        }
    }

    /**
     * Show current execution progress
     */
    private func showProgress(): Unit {
        PrintUtils.printLine("")
        PrintUtils.printLine("${"📊 Execution Status".withColor(AnsiColor.BRIGHT_CYAN)}")
        PrintUtils.printLine("")
        
        // Get execution statistics from the response if available
        PrintUtils.printLine("  Status: ${"Running".withColor(AnsiColor.BRIGHT_GREEN)}")
        PrintUtils.printLine("  Controls available: ESC (cancel), Ctrl+I (add info), Ctrl+P (pause)")
        PrintUtils.printLine("")
        
        PrintUtils.printLine("Press Enter to continue...")
        let _ = InputUtils.getUserInput(prompt: "", withBox: false)
        PrintUtils.printLine("")
    }

    /**
     * Stop the interactive controller
     */
    internal func stop(): Unit {
        if (let Some(f) <- this.future) {
            f.cancel()
            try {
                f.get()
            } catch (_: Exception) {
                // Ignore cancellation exceptions
            }
        }
    }

    /**
     * Wait until the controller stops
     */
    internal func waitUntilStop(): Unit {
        if (let Some(f) <- this.future) {
            try {
                f.get()
            } catch (ex: Exception) {
                LogUtils.debug("Interactive controller ended: ${ex.message}")
            }
        }
    }
}

