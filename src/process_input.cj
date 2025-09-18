package cli

import magic.core.agent.{Agent,AgentRequest, AgentResponseStatus, AsyncAgentResponse}
import magic.log.LogUtils

import cli.core.config.CliConfig
import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.agents.CodeAnalyzer
import cli.io.{InputUtils, PrintUtils, WithColor, AnsiColor, Confirmation}
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
    //let items = command.split(" ")  // Simple split by space, does not handle quotes
    //let args = if (items.size > 1) { items[1..] } else { Array<String>() }
    let (exitCode, stdOutData, stdErrData) = TerminalUtils.execute([command], workDir: CliConfig.cwd)
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
        if (InputUtils.confirm("MAGIC.md already exists.", "Overwrite?") == Confirmation.Deny) {
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

/**
 * Check if an exception should trigger model fallback
 */
private func shouldFallback(ex: Exception): Bool {
    if (!CliConfig.enableFallback) {
        return false
    }
    let message = ex.message.toAsciiLower()

    // HTTP and model errors that should trigger fallback
    return message.contains("timeout") ||
           message.contains("5") ||  // 5xx server errors
           message.contains("connection") ||
           message.contains("network") ||
           message.contains("429") ||  // Rate limiting
           message.contains("401") ||  // Unauthorized
           message.contains("rate limit") ||
           message.contains("quota") ||
           message.contains("api key") ||
           message.contains("unauthorized") ||
           message.contains("authentication")
}

// Session-level successful model memory (resets on restart)
private var sessionSuccessfulModel: Option<String> = None

private func executeAgentTask(context: CliContext, input: String): Unit {
    LogUtils.debug("Handle user input `${input}`")

    let models = ArrayList<String>()
    if (let Some(successModel) <- sessionSuccessfulModel) {
        // Use last successful model first
        models.add(successModel)
        if (successModel != CliConfig.model) {
            models.add(CliConfig.model)
        }
        if (CliConfig.enableFallback) {
            for (fallback in CliConfig.fallbackModels) {
                if (fallback != successModel) {
                    models.add(fallback)
                }
            }
        }
    } else {
        // First execution, use original order
        models.add(CliConfig.model)
        if (CliConfig.enableFallback) {
            models.add(all: CliConfig.fallbackModels)
        }
    }

    let maxAttempts = if (models.size > CliConfig.maxFallbackAttempts) {
        CliConfig.maxFallbackAttempts
    } else {
        models.size
    }

    // Try models in sequence
    for (i in 0..maxAttempts) {
        let currentModel = models[i]

        try {
            // Switch to fallback model if needed
            if (i > 0) {
                // Only show user message on first fallback in this session
                if (sessionSuccessfulModel.isNone()) {
                    PrintUtils.printTool("Model Fallback", "Switching to: ${currentModel}")
                }
                context.switchToFallbackModel(currentModel)
            }

            LogUtils.info("Using model: ${currentModel}")

            // Execute with current model
            let response = context.agent.asyncChat(AgentRequest(input, conversation: context.conversationManager.conversation))

            // Spawn a thread to check for ESC cancellation
            let cancelled = AtomicBool(false)
            let escPressed = AtomicBool(false)

            let escChecker = spawn {
                while (!cancelled.load() && !Thread.currentThread.hasPendingCancellation) {
                    // Don't check for ESC when agent is requesting user input
                    if (!InputUtils.isRequestingInput() && InputUtils.checkEsc()) {
                        // ESC was pressed, cancel the agent response
                        if (escPressed.compareAndSwap(false, true)) {  // Ensure only one cancellation
                            LogUtils.info("ESC pressed, cancelling")
                            context.thinkIndicator.load()?.cancel()
                            response.cancel()
                            PrintUtils.printInterrupt()
                        }
                        return
                    }
                    sleep(Duration.millisecond * 50) // Poll every 50ms
                }
            }

            try {
                handleAgentResponse(context, response, escPressed)
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

            // Compact is called once per successful execution, not per retry attempt
            context.conversationManager.compact()
            sessionSuccessfulModel = Some(currentModel)
            break // Success, exit retry loop
        } catch (ex: Exception) {
            if (i == maxAttempts - 1) {
                throw ex
            }
            if (shouldFallback(ex)) {
                LogUtils.info("Model ${currentModel} failed, trying fallback")
                continue
            } else {
                throw ex
            }
        }
    }
}

/**
 * Handle the agent response, print the response and update the conversation
 */
private func handleAgentResponse(context: CliContext,
                                 response: AsyncAgentResponse,
                                 escPressed: AtomicBool): Unit {
    // Wait for response completion (blocking)
    // This ensures response.content access is safe
    let content = response.content
    match (response.status) {
        case AgentResponseStatus.Success =>
            // Check if cancellation occurred
            if (!escPressed.load()) {
                if (!content.isEmpty()) {
                    PrintUtils.printAgentResponse(response)
                }
                context.conversationManager.conversation.addChatRound(response.execution.chatRound)
            }
        case AgentResponseStatus.Cancelled =>
            if (content == "__USER_CLARIFY__") {
                // User needs to clarify the execution,
                // so, we should save the chat round and let it it continue to execute.
                // Change the answer that wil be added to the chat round
                response.execution.setAnswer("The user denied the last tool and will guide the execution.")
                context.conversationManager.conversation.addChatRound(response.execution.chatRound)
            } else {
                PrintUtils.printLine(response.content.withColor(AnsiColor.color256(100)))
            }
            // Otherwise, user denied the execution
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
                PrintUtils.printLine(msg.withColor(AnsiColor.color256(100)))
                LogUtils.error(msg)
            }
            return true  // Continue running
    }
}