package cli

import magic.core.agent.AgentRequest
import magic.log.LogUtils

import cli.core.config.CliConfig
import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.context.CliContext
import cli.core.agents.CodeAnalyzer
import cli.io.{InputUtils, PrintUtils}
import cli.io.{WithColor, AnsiColor}
import cli.utils.TerminalUtils

import std.collection.ArrayList
import std.fs.{exists, File, FSException, Path}
import std.sync.{AtomicOptionReference, AtomicBool}
import std.process.executeWithOutput

/**
 * Check if input is a built-in command
 */
private func isBuiltinCommand(input: String): Bool {
    return input.startsWith("/help") || input.startsWith("/clear") ||
           input.startsWith("/mcp") || input.startsWith("/conversation") ||
           input.startsWith("/cmd") || input.startsWith("/memory") ||
           input.startsWith("/init") || input.startsWith("/compact") ||
           input.startsWith("/exit") || input == "exit" || input == "help"
}

/**
 * Execute shell command (input starting with !)
 */
private func executeShellCommand(command: String, context: CliContext): Unit {
    LogUtils.info("Executing shell command: ${command}")
    if (command.trimAscii().isEmpty()) {
        PrintUtils.printLine("Shell Command: No command provided after '!'.")
        return
    }
    let items = command.split(" ")  // Simple split by space, does not handle quotes
    let args = if (items.size > 1) { items[1..] } else { Array<String>() }
    let (exitCode, stdOutData, stdErrData) = executeWithOutput(items[0], args, workingDirectory: CliConfig.cwd)
    let output = if (exitCode == 0) {
        String.fromUtf8(stdOutData).trimAscii()
    } else {
        String.fromUtf8(stdErrData).trimAscii()
    }
    LogUtils.info("Shell command exited with code ${exitCode}, output: ${output}")
    PrintUtils.printShellResult(output)
}

/**
 * Execute built-in commands and return whether to continue running
 */
private func executeBuiltinCommand(input: String, context: CliContext): Bool {
    match (input) {
        case "/exit" | "exit" =>
            PrintUtils.printExitMessage()
            return false  // Signal to exit main loop
        case "/help" | "help" =>
            PrintUtils.printHelpMessage()
            return true
        case "/clear" | "clear" =>
            context.conversationManager.clearConversation()
            PrintUtils.clearScreen()
            PrintUtils.printLogo()
            return true
        case "/compact" | "compact" =>
            context.conversationManager.compact(manual: true)
            return true
        case "/memory" | "memory" =>
            let userRules = CliConfig.userRules
            if (userRules.isEmpty()) {
                PrintUtils.printTool("User Memory (MAGIC.md)", "📝 No MAGIC.md file found in current directory")
                PrintUtils.printLine("Create a MAGIC.md file in your project to set custom rules and context for Magic-cli to use.")
            } else {
                PrintUtils.printTool("User Memory (MAGIC.md)", "📝 Current MAGIC.md content:")
                PrintUtils.printLine(userRules)
            }
            return true
        case "/init" | "init" =>
            initMagicFile()
            return true
        case _input where _input.startsWith("/cmd") =>
            if (let Some(request) <- context.customCommandManager.handleCommand(input)) {
                executeAgentTask(context, request)
            }
            return true
        case _input where _input.startsWith("/mcp") =>
            context.mcpManager.handleCommand(input.split(" "), context.agent)
            return true
        case _input where _input.startsWith("/conversation") =>
            context.conversationManager.handleCommand(input.split(" "))
            return true
        case _ =>
            return true  // Unknown built-in command, continue
    }
}

private const INIT_PROMPT = """
Please analyze the current project directory and generate practical MAGIC.md configuration file content.

Requirements:
1. Analyze project type, programming languages, frameworks, and tools in depth
2. Identify project structure, important files, and configurations
3. Infer appropriate coding standards and best practices
4. Generate project-specific development guidelines and considerations
5. Include specific guidance for AI assistant behavior

Output format requirements:
- Return the complete MAGIC.md file content directly, no explanatory text
- Use Markdown format
- Include sections: project info, coding standards, development guide, AI assistant guidance
- Content should be specific and practical to guide future AI assistance work
- DO NOT create or write any files, only return the content

Please start analyzing the project and return the MAGIC.md content:
"""

private func initMagicFile(): Unit {
    let agent = CodeAnalyzer()
    let magicFilePath = CliConfig.uerRuleFile

    if (exists(magicFilePath)) {
        if (let Deny(userInput) <- InputUtils.confirm("MAGIC.md already exists.", "Overwrite?")) {
            return
        }
    }

    PrintUtils.printTool("MAGIC.md Init", "🔍 Analyzing project structure and generating MAGIC.md...")
    let response = agent.chat(AgentRequest(INIT_PROMPT))

    try {
        File.writeTo(magicFilePath, response.content.toArray())
        PrintUtils.printTool("MAGIC.md Init", "✅ MAGIC.md initialized successfully!")

        let preview = if (response.content.size > 300) {
            response.content[0..300] + "..."
        } else {
            response.content
        }
        PrintUtils.printLine("📝 Content preview:")
        PrintUtils.printLine(preview)
        PrintUtils.printLine("\n💡 Use '/memory' to view the full content anytime!")
    } catch (e: Exception) {
        PrintUtils.printLine("❌ Failed to write MAGIC.md: ${e.message}")
    }
}

private func executeAgentTask(context: CliContext, input: String) {
    // Start agent execution
    let response = context.agent.asyncChat(AgentRequest(input))

    // Spawn a thread to check for ESC cancellation
    let cancelled = AtomicBool(false)
    let escPressed = AtomicBool(false)

    let escChecker = spawn {
        while (!cancelled.load() && !Thread.currentThread.hasPendingCancellation) {
            // Don't check for ESC when agent is requesting user input
            if (!InputUtils.isRequestingInput() && InputUtils.checkEsc()) {
                // ESC was pressed, cancel the agent response
                if (escPressed.compareAndSwap(false, true)) {  // Ensure only one cancellation
                    response.cancel()
                    PrintUtils.printInterrupt()
                }
                return
            }
            sleep(Duration.millisecond * 50) // Poll every 50ms
        }
    }

    try {
        // Wait for response completion (blocking)
        // This ensures response.content access is safe
        let content = response.content

        // Check if cancellation occurred
        if (!escPressed.load()) {
            if (!content.isEmpty()) {
                PrintUtils.printAgentResponse(response)
            }
            context.conversationManager.compact()
        }
    } finally {
        // Properly shutdown ESC checker
        cancelled.store(true)
        escChecker.cancel()
        try {
            escChecker.get()
        } catch (e: Exception) {
            LogUtils.error("ESC checker thread ended with exception: ${e}")
            // Ignore cancellation exceptions during cleanup
        }
    }
}

/**
 * Main input processing function - determines input type and routes accordingly
 */
func processInput(input: String, context: CliContext): Bool {
    match {
        case input.startsWith("!") =>
            // Shell command - remove "!" and execute
            executeShellCommand(input[1..], context)
            return true  // Continue running
        case isBuiltinCommand(input) =>
            // Built-in commands (/help, /clear, /mcp, /exit, etc.)
            return executeBuiltinCommand(input, context)  // Returns false for /exit
        case _ =>
            // Let agent process the input
            try {
                executeAgentTask(context, input)
            } catch (ex: Exception) {
                let msg = "Execution failure: ${ex.message}"
                PrintUtils.printLine(msg.withColor(AnsiColor(100)))
                LogUtils.error(msg)
            }
            return true  // Continue running
    }
}