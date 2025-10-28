package cli.app

import magic.core.agent.*
import magic.log.LogUtils
import magic.core.model.ChatModel

import cli.core.config.CliConfig
import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.agents.CodeAnalyzer
import cli.core.context.{MentionParser, FileContext}
import cli.io.{InputUtils, PrintUtils, WithColor, AnsiColor, Confirmation}
import cli.core.commands.CustomCommandManager
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
        case "/status" | "status" =>
            app.tokenStatusManager.printStatus()
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

        // Handle direct /<command> format for custom commands
        case _input where _input.startsWith("/") =>
            if (let Some(request) <- app.customCommandManager.handleCommand(input)) {
                executeAgentTask(app, request)
            }
            return true

        case _ => // Not an available command
            return None
    }
}

//-------------------------------------------------------

private func executeAgentTask(app: CliApp, input: String): Unit {
    LogUtils.debug("Handle user input `${input}`")
    // Each time we execute an agent task, we need to reset the sub-agent indent
    PrintUtils.resetSubAgent()
    
    // 1. Check for file changes before processing
    let changes = app.fileWatcher.checkChanges()
    if (changes.size > 0) {
        let syncedChanges = app.fileWatcher.syncContext()
        PrintUtils.printLine("${AnsiColor.BRIGHT_BLACK}📝 Detected ${syncedChanges.size} file change(s), cache updated${AnsiColor.RESET}")
    }
    
    // 2. Parse @mention file references
    let parseResult = MentionParser.parse(input)
    var finalInput = parseResult.cleanedInput
    
    // 3. If there are file mentions, read and format them
    if (parseResult.mentions.size > 0) {
        PrintUtils.printLine("")
        PrintUtils.printLine("${AnsiColor.BRIGHT_WHITE}📎 Referenced Files:${AnsiColor.RESET}")
        for (mention in parseResult.mentions) {
            let info = MentionParser.formatMentionInfo(mention)
            PrintUtils.printLine("  ${AnsiColor.BRIGHT_BLACK}•${AnsiColor.RESET} ${info}")
        }
        
        // 🆕 Phase 4: Recommend related files
        LogUtils.debug("Analyzing file dependencies for recommendations...")
        for (mention in parseResult.mentions) {
            // First analyze file dependencies
            let _ = app.dependencyAnalyzer.analyzeFile(mention.path)
            
            // Recommend up to 3 related files
            let related = app.dependencyAnalyzer.recommendRelatedFiles(mention.path, 3)
            if (related.size > 0) {
                PrintUtils.printLine("${AnsiColor.BRIGHT_BLACK}  💡 Related files:${AnsiColor.RESET}")
                for (relFile in related) {
                    // Calculate relatedness
                    let relatedness = app.dependencyAnalyzer.calculateRelatedness(mention.path, relFile)
                    let score = Int64(relatedness * 100.0)
                    PrintUtils.printLine("${AnsiColor.BRIGHT_BLACK}     • ${relFile.toString()} (${score}% similar)${AnsiColor.RESET}")
                }
            }
        }
        PrintUtils.printLine("")
        
        // 4. Append file contents to the input (with caching and compression)
        let fileContents = ArrayList<String>()
        var totalTokens: Int64 = 0
        let maxTokensPerFile: Int64 = 1000  // Max 1000 tokens per file
        
        for (mention in parseResult.mentions) {
            // Try to get from cache
            var content = ""
            let cachedContent = app.contextEngine.getFile(mention.path)
            match (cachedContent) {
                case Some(c) =>
                    content = c
                    LogUtils.debug("Using cached content for: ${mention.path.toString()}")
                case _ =>
                    // Cache miss, read file and cache it
                    content = MentionParser.readFileContent(mention)
                    if (!content.isEmpty()) {
                        app.contextEngine.addFile(mention.path, content)
                        // Start tracking new file
                        app.fileWatcher.track(mention.path)
                    }
            }
            
            if (!content.isEmpty()) {
                // 🆕 Phase 4: Smart compression for large files
                var finalContent = content
                if (let Some(fileContext) <- app.contextEngine.getFileContext(mention.path)) {
                    totalTokens += fileContext.tokenCount
                    
                    // If file tokens exceed limit, auto-compress
                    if (fileContext.tokenCount > maxTokensPerFile) {
                        finalContent = app.contextEngine.autoCompress(fileContext, maxTokensPerFile)
                        // Simple estimate: words / 4
                        let words = finalContent.split(" ").size
                        let compressedTokens = (words / 4) + (if (words % 4 != 0) { 1 } else { 0 })
                        LogUtils.debug("Compressed file ${mention.path.toString()}: ${fileContext.tokenCount} -> ${compressedTokens} tokens")
                        PrintUtils.printLine("${AnsiColor.BRIGHT_BLACK}  ⚡ Compressed ${mention.path.toString()} (${fileContext.tokenCount} -> ${compressedTokens} tokens)${AnsiColor.RESET}")
                    }
                }
                
                let header = "--- File: ${mention.path.toString()} ---"
                fileContents.add(header)
                fileContents.add(finalContent)
                fileContents.add("--- End of ${mention.path.toString()} ---")
            }
        }
        
        // 🆕 Phase 4: Display context statistics
        if (totalTokens > 0) {
            PrintUtils.printLine("${AnsiColor.BRIGHT_BLACK}📊 Context: ${parseResult.mentions.size} file(s), ~${totalTokens} tokens${AnsiColor.RESET}")
        }
        
        // 🆕 Phase 4: If context is insufficient, recommend related files
        if (parseResult.mentions.size < 3 && parseResult.mentions.size > 0) {
            let firstFile = parseResult.mentions[0].path
            let recommended = app.dependencyAnalyzer.recommendRelatedFiles(firstFile, 2)
            
            if (recommended.size > 0) {
                PrintUtils.printLine("${AnsiColor.BRIGHT_BLACK}💡 Suggested context (use @ to include):${AnsiColor.RESET}")
                for (rec in recommended) {
                    PrintUtils.printLine("${AnsiColor.BRIGHT_BLACK}   @${rec.toString()}${AnsiColor.RESET}")
                }
            }
        }
        PrintUtils.printLine("")
        
        if (fileContents.size > 0) {
            finalInput = "${finalInput}\n\n${String.join(fileContents.toArray(), delimiter: "\n")}"
        }
    }

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

            // Execute with current model (use finalInput with file contents)
            let asyncResponse = app.agent.asyncChat(
                AgentRequest(finalInput, conversation: app.conversationManager.conversation)
            )
            // Start interactive controller (replaces old CancelChecker)
            let controller = InteractiveController(app, asyncResponse)
            controller.start()
            
            // Since async agent response is in polled mode, we must have a thread to poll it
            // If the response completes, stop the controller
            spawn {
                try {
                    let _content = asyncResponse.content
                } catch (_ex: Exception) {
                    // Skip the exception
                } finally {
                    controller.stop()
                }
            }
            
            // Wait for response completion or cancellation
            controller.waitUntilStop()
            
            // Check if cancellation occurred
            if (controller.hasCancel()) {
                app.stopThinkIndicator()
                PrintUtils.printLine("${"✗ Execution cancelled by user".withColor(AnsiColor.BRIGHT_BLACK)}")
                return
            } else {
                // Check if user added additional information
                if (let Some(info) <- controller.getAdditionalInfo()) {
                    PrintUtils.printLine("${"ℹ️  User provided additional context: ${info}".withColor(AnsiColor.BRIGHT_BLUE)}")
                    // Note: The additional info was logged but couldn't be injected mid-execution
                    // This would require extending the Agent API
                }
                handleAgentResponse(app, asyncResponse)
            }
            // Compact is called once per successful execution, not per retry attempt
            ModelFallback.lastAvailableModel = currModel
            return // Success, exit retry loop
        } catch (ex: Exception) {
            if (idx == allModels.size - 1) { // All models are tried
                throw ex
            } else if (ModelFallback.shouldFallback(ex)) {
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
private func handleAgentResponse(app: CliApp, response: AsyncAgentResponse): Unit {
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
    if (input.startsWith("!")) {
        // Shell command - remove "!" and execute
        executeShellCommand(input[1..], app)
        return true  // Continue running
    }
    // Try to execute as a command
    if (let Some(status) <- executeCommand(input, app)) {
        return status
    }
    // Otherwise, let agent process the input
    try {
        executeAgentTask(app, input)
    } catch (ex: Exception) {
        let msg = "Execution failure: ${ex.message}"
        PrintUtils.printLine(msg.withColor(AnsiColor.color256(100)))
        LogUtils.error(ex)
    }
    return true  // Continue running
}