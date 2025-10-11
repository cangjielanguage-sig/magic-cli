package cli.app

import magic.core.agent.*
import magic.log.LogUtils
import magic.core.model.ChatModel

import cli.core.config.CliConfig
import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.agents.CodeAnalyzer
import cli.io.{InputUtils, PrintUtils, WithColor, AnsiColor, Confirmation}
import cli.utils.ShellUtils
import cli.telemetry.DataCollector
import cli.io.CompletionListUtils

import std.collection.{ArrayList, enumerate}
import std.fs.{exists, File, FSException, Path}
import std.sync.{AtomicOptionReference, AtomicBool}
import std.process.executeWithOutput

/**
 * Execute shell command (input starting with !)
 */
private func executeShellCommand(command: String, app: CliApp): Unit {
    LogUtils.info("Executing shell command: ${command}")
    if (command.trimAscii().isEmpty()) {
        PrintUtils.printLine("Shell Command: No command provided after '!'.")
        return
    }
    //let items = command.split(" ")  // Simple split by space, does not handle quotes
    //let args = if (items.size > 1) { items[1..] } else { Array<String>() }
    let (exitCode, stdOutData, stdErrData) = ShellUtils.execute([command], workDir: CliConfig.cwd)
    let output = if (exitCode == 0) {
        String.fromUtf8(stdOutData).trimAscii()
    } else {
        String.fromUtf8(stdErrData).trimAscii()
    }
    LogUtils.info("Shell command exited with code ${exitCode}, output: ${output}")
    PrintUtils.printShellResult(output)
}

//-------------------------------------------------------

/**
 * Check if input is a built-in command
 */
private func isBuiltinCommand(input: String): Bool {
    for (cmd in CompletionListUtils.COMMANDS) {
        if (input.startsWith(cmd[0])) {
            return true
        }
    }
    return input == "exit" || input == "help"
}

/**
 * Execute built-in commands and return whether to continue running
 */
private func executeBuiltinCommand(input: String, app: CliApp): Bool {
    match (input) {
        case "/exit" | "exit" =>
            PrintUtils.printExitMessage()
            return false  // Signal to exit main loop
        case "/help" | "help" =>
            PrintUtils.printHelpMessage()
            return true
        case "/clear" | "clear" =>
            app.conversationManager.clearConversation()
            PrintUtils.clearScreen()
            PrintUtils.printLogo()
            return true
        case "/compact" | "compact" =>
            app.conversationManager.compact(manual: true)
            return true
        case "/memory" | "memory" =>
            let userRules = CliConfig.userRules
            if (userRules.isEmpty()) {
                PrintUtils.printTool("User Memory (MAGIC.md)", "📝 No MAGIC.md file found in current directory")
                PrintUtils.printLine("Create a MAGIC.md file in your project to set custom rules and app for Magic-cli to use.")
            } else {
                PrintUtils.printTool("User Memory (MAGIC.md)", "📝 Current MAGIC.md content:")
                PrintUtils.printLine(userRules)
            }
            return true
        case "/init" | "init" =>
            initMagicFile()
            return true
        case _input where _input.startsWith("/cmd") =>
            if (let Some(request) <- app.customCommandManager.handleCommand(input)) {
                executeAgentTask(app, request)
            }
            return true
        case _input where _input.startsWith("/mcp") =>
            app.mcpManager.handleCommand(input.split(" "), app.agent)
            return true
        case _input where _input.startsWith("/conversation") =>
            app.conversationManager.handleCommand(input.split(" "))
            return true
        case _ =>
            return true  // Unknown built-in command, continue
    }
}

//-------------------------------------------------------

/**
 * Check if an exception should trigger model fallback
 */
private func shouldFallback(ex: Exception): Bool {
    // Only fallback if we have fallback models configured
    if (CliConfig.fallbackModels.size == 0) {
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

private func executeAgentTask(app: CliApp, input: String): Unit {
    LogUtils.debug("Handle user input `${input}`")
    // Each time we execute an agent task, we need to reset the sub-agent indent
    PrintUtils.resetSubAgent()

    // Try all available models in sequence
     let allModels = ModelFallback.getAllModels()
     for ((idx, currModel) in enumerate(allModels)) {
        try {
            // Switch to fallback model if needed
            if (idx == 0) { // Note that the first model is always lastAvailableModel
                LogUtils.debug("Use model: ${currModel.fullName}")
            } else {
                PrintUtils.printLine("Model Fallback: switch to: ${currModel.fullName}")
                LogUtils.debug("Switch model: ${currModel.fullName}")
                app.switchToFallbackModel(currModel)
            }

            // Execute with current model
            let asyncResponse = app.agent.asyncChat(
                AgentRequest(input, conversation: app.conversationManager.conversation)
            )
            // Start cancellation checker
            let cancelChecker = CancelChecker(app, asyncResponse)
            cancelChecker.start()
            // Since async agent response is in polled mode, we must have a thread to poll it
            // If the response completes, stop the cancel checker
            spawn {
                try {
                    let _content = asyncResponse.content
                } catch (_ex: Exception) {
                    // Skip the exception
                } finally {
                    cancelChecker.stop()
                }
            }
            // Wait for response completion or cancellation
            cancelChecker.waitUntilStop()
            // Check if cancellation occurred
            if (cancelChecker.hasCancel()) {
                app.stopThinkIndicator()
                // PrintUtils.printLine("Cancelled".withColor(AnsiColor.color256(240)))
                return
            } else {
                handleAgentResponse(app, asyncResponse)
            }
            // Compact is called once per successful execution, not per retry attempt
            ModelFallback.lastAvailableModel = currModel
            return // Success, exit retry loop
        } catch (ex: Exception) {
            if (idx == allModels.size - 1) { // All models are tried
                throw ex
            } else if (shouldFallback(ex)) {
                LogUtils.info("Model ${currModel.fullName} failed, trying fallback")
            } else {
                throw ex
            }
        }
    }
}

/**
 * Handle the agent response, print the response and update the conversation
 */
private func handleAgentResponse(app: CliApp,
                                 response: AsyncAgentResponse): Unit {
    // This ensures response.content access is safe
    let content = response.content
    match (response.status) {
        case AgentResponseStatus.Success =>
            // Check if cancellation occurred
            if (!content.isEmpty()) {
                PrintUtils.printAgentResponse(response)
            }
            app.conversationManager.conversation.addChatRound(response.execution.chatRound)
            app.conversationManager.compact()
            spawn {
                DataCollector.collectChatRound(response.execution.chatRound)
            }
        case AgentResponseStatus.Cancelled => ()
        case AgentResponseStatus.Failed =>
            PrintUtils.printLine(response.content.withColor(AnsiColor.color256(240)))
    }
}

//-------------------------------------------------------

/**
 * Main input processing function - determines input type and routes accordingly
 */
func processInput(app: CliApp, input: String): Bool {
    match {
        case input.startsWith("!") =>
            // Shell command - remove "!" and execute
            executeShellCommand(input[1..], app)
            return true  // Continue running
        case isBuiltinCommand(input) =>
            // Built-in commands (/help, /clear, /mcp, /exit, etc.)
            return executeBuiltinCommand(input, app)  // Returns false for /exit
        case _ =>
            // Let agent process the input
            try {
                executeAgentTask(app, input)
            } catch (ex: Exception) {
                let msg = "Execution failure: ${ex.message}"
                PrintUtils.printLine(msg.withColor(AnsiColor.color256(100)))
                LogUtils.error(ex)
            }
            return true  // Continue running
    }
}