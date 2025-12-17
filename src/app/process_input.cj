package cli.app

import magic.core.agent.*
import magic.log.LogUtils
import magic.core.model.ChatModel
import magic.core.message.{Message, MessageList, ChatRound}

import cli.io.*
import cli.core.config.CliConfig
import cli.core.model.{ModelTokenLimits, CliModelManager}
import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.commands.CustomCommandManager
import cli.utils.ShellUtils
import cli.telemetry.DataCollector
import cli.io.CompletionListUtils

import std.collection.{ArrayList, enumerate}
import std.fs.{exists, File, FSException, Path}
import std.sync.{AtomicOptionReference, AtomicBool}
import std.process.executeWithOutput

/**
 * Main input processing function - determines input type and routes accordingly
 */
func processInput(app: CliApp, input: String): Bool {
    if (input.startsWith("!")) {
        // Shell command - remove "!" and execute
        executeShellCommand(input[1..], app)
        return true  // Continue running
    }
    // Try to execute as a built-in or customized command
    if (let Some(status) <- executeCommand(input, app)) {
        return status
    }
    // Otherwise, let agent process the input
    try {
        executeAgent(app, input)
    } catch (ex: Exception) {
        let msg = "Execution failure: ${ex.message}"
        PrintUtils.printLine(msg.withColor(AnsiColor.color256(100)))
        LogUtils.error(ex)
    }
    return true  // Continue running
}

//-------------------------------------------------------

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
    let (exitCode, stdout, stderr) = ShellUtils.execute([command], workDir: CliConfig.cwd)
    let output = if (exitCode == 0) {
        stdout.trimAscii()
    } else {
        stderr.trimAscii()
    }
    LogUtils.info("Shell command exited with code ${exitCode}, output: ${output}")
    PrintUtils.printShellResult(output)
}

//-------------------------------------------------------

/**
 * Execute built-in commands and return whether to continue running
 */
private func executeCommand(input: String, app: CliApp): Option<Bool> {
    match (input) {
        case "/exit" | "exit" =>
            PrintUtils.printExitMessage()
            return false  // Signal to exit main loop

        case "/help" | "help" =>
            CustomCommandManager.printBuiltinCommands()
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
                PrintUtils.printLine("📝 No MAGIC.md file found in current directory")
                PrintUtils.printLine("Create a MAGIC.md file in your project to set custom rules and app for Magic-cli to use.")
            } else {
                PrintUtils.printLine("📝 Current MAGIC.md content:")
                PrintUtils.printLine(userRules)
            }
            return true

        case "/init" | "init" =>
            initMagicFile()
            return true

        case "/status" | "status" =>
            app.tokenStatusManager.printStatus()
            return true

       case _input where _input.startsWith("/mcp") =>
            app.mcpManager.handleCommand(input.split(" "), app.agent)
            return true

        case _input where _input.startsWith("/conversation") =>
            app.conversationManager.handleCommand(input.split(" "))
            return true

        case _input where _input.startsWith("/cmd") =>
            app.customCommandManager.handleCommand(input)
            return true

        case "/agents" =>
            app.customAgentManager.listAgents()
            return true

        // Handle direct /<command> ...
        case _input where _input.startsWith("/") =>
            // Get command name
            if (let Some(pivot) <- _input.indexOf(b' ')) {
                let cmdName = _input[1..pivot] // Remove the leading '/'
                let args = _input[pivot+1..]
                if (let Some(command) <- app.customCommandManager.getCommand(cmdName)) {
                    let question = app.customCommandManager.handleCustomCommand(command, args)
                    LogUtils.debug("Handle custom command '${cmdName}' with args '${args}'")
                    LogUtils.debug("   Question: ${question}")
                    executeAgent(app, question)
                } else {
                    PrintUtils.printLine("💥 Command '${cmdName}' not found. Use '/cmd list' to see available commands.")
                }
                return true
            } else {
                return None
            }

        case _ => // Not an available command
            return None
    }
}

//-------------------------------------------------------

private func executeAgent(app: CliApp, input: String): Unit {
    LogUtils.debug("Handle user input `${input}`")
    // Each time we execute an agent task, we need to reset the sub-agent indent
    PrintUtils.resetSubAgent()

    // Parse agent name and question to get the agent to use
    let (agent, question) = parseAgentAndQuestion(app, input.trimAscii())
    let isSubagent = agent.name != app.agent.name

    // Try all available models in sequence
     let allModels = CliModelManager.getAllModels()
     for ((idx, currModel) in enumerate(allModels)) {
        try {
            // Switch to fallback model if needed
            if (idx == 0) { // Note that the first model is always lastAvailableModel
                LogUtils.debug("Use model: ${currModel.fullName}")
            } else {
                PrintUtils.printLine("Model Fallback: switch to: ${currModel.fullName}")
                LogUtils.debug("Switch model: ${currModel.fullName}")
                // Switch to the fallback model
                agent.model = currModel
            }

            // Execute with the current model
            let asyncResponse = if (isSubagent) {
                //  Sub-agent process the question without conversations
                agent.asyncChat(AgentRequest(question))
            } else {
                agent.asyncChat(
                    AgentRequest(question, conversation: app.conversationManager.conversation)
                )
            }
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
                // Mark cancellation without blocking
                asyncResponse.cancel(blocking: false)
                // Immediately save steps without waiting for execution to finish
                if (!isSubagent) {
                    try {
                        let partialChatRound = asyncResponse.execution.getPartialChatRound("对话被用户取消 (Cancelled by user)")
                        app.conversationManager.conversation.addChatRound(partialChatRound)
                        LogUtils.debug("Immediately saved cancelled chat round with steps")
                    } catch (ex: Exception) {
                        saveIncompleteChatRound(app, question, "对话被用户取消 (Cancelled by user)")
                        LogUtils.debug("Failed to save cancelled chat round immediately, used fallback: ${ex.message}")
                    }
                }
                return
            }
            // Unified handling for all cases (Success, Cancelled, Failed)
            handleAgentResponse(app, question, asyncResponse, isSubagent: isSubagent)
            CliModelManager.lastAvailableModel = currModel
            return // Success, exit retry loop
        } catch (ex: Exception) {
            if (idx == allModels.size - 1) { // All models are tried
                if (!isSubagent) {
                    saveIncompleteChatRound(app, question, ex.message)
                }
                throw ex
            } else if (CliModelManager.shouldFallback(ex)) {
                LogUtils.info("Model ${currModel.fullName} failed, trying fallback")
            } else {
                throw ex
            }
        }
    }
}

/**
 * Save an incomplete chat round when conversation is cancelled or failed
 */
private func saveIncompleteChatRound(
    app: CliApp,
    question: String,
    answer: String): Unit {
    try {
        let chatRound = ChatRound(
            Message.user(question),
            Message.assistant(answer),
            MessageList() // Empty steps to avoid concurrent access
        )
        app.conversationManager.conversation.addChatRound(chatRound)
        LogUtils.debug("Saved incomplete chat round: question='${question}', answer='${answer}'")
    } catch (ex: Exception) {
        LogUtils.error("Failed to save incomplete chat round: ${ex.message}")
    }
}

/**
 * Parse the input string to extract the agent name and the question.
 * Case 1: @<agent-name> ...., return agent and question
 * Case 2: no agent name, return None for agent name
 */
private func parseAgentAndQuestion(app: CliApp, input: String): (Agent, String) {
    if (!input.startsWith("@")) {
        return (app.agent, input) // No agent name, return default agent
    }
    if (let Some(pivot) <- input.indexOf(b' ')) {
        let name = input[1..pivot] // Remove the leading '@'
        let args = input[pivot..].trimAscii()

        if (let Some(subAgent) <- app.customAgentManager.getAgent(name)) {
            return (subAgent, args)
        }
    }
    return (app.agent, input) // No sub-agent found, return default agent
}
/**
 * Handle the agent response, print the response and update the conversation
 */
private func handleAgentResponse(
    app: CliApp,
    input: String,
    response: AsyncAgentResponse,
    isSubagent!: Bool): Unit {
    // This ensures response.content access is safe
    let content = response.content
    match (response.status) {
        case AgentResponseStatus.Success =>
            // Check if cancellation occurred
            if (!content.isEmpty()) {
                PrintUtils.printAgentResponse(response)
            }
            if (!isSubagent) {
                app.conversationManager.conversation.addChatRound(response.execution.chatRound)
                app.conversationManager.compact()
                spawn {
                    DataCollector.collectChatRound(response.execution.chatRound)
                }
            }
        case AgentResponseStatus.Cancelled =>
            if (!isSubagent) {
                // After response.content is accessed, finished = true, execution thread has stopped
                // Set answer manually for cancelled case, then try to access chatRound to get steps
                try {
                    // Set answer manually since it's not set in cancelled case
                    response.execution.setAnswer(content)
                    app.conversationManager.conversation.addChatRound(response.execution.chatRound)
                    LogUtils.debug("Saved cancelled chat round with steps")
                } catch (ex: Exception) {
                    // Fallback if chatRound access fails
                    saveIncompleteChatRound(app, input, content)
                    LogUtils.debug("Failed to access chatRound for cancelled case, used fallback: ${ex.message}")
                }
            }
        case AgentResponseStatus.Failed =>
            PrintUtils.printLine(response.content.withColor(AnsiColor.color256(240)))
            if (!isSubagent) {
                try {
                    response.execution.setAnswer(content)
                    app.conversationManager.conversation.addChatRound(response.execution.chatRound)
                    LogUtils.debug("Saved failed chat round with steps")
                } catch (ex: Exception) {
                    saveIncompleteChatRound(app, input, content)
                    LogUtils.debug("Failed to access chatRound for failed case, used fallback: ${ex.message}")
                }
            }
    }
}
