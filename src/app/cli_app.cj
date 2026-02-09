package cli.app

import magic.log.LogUtils
import magic.core.agent.Agent
import magic.core.model.ChatModel

import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.commands.CustomCommandManager
import cli.core.model.TokenStatusManager
import cli.core.config.CliConfig
import cli.core.agents.*
import cli.io.*

import std.collection.ArrayList
import std.fs.{Path, exists, Directory, canonicalize}
import std.collection.HashMap
import std.sync.{Mutex, AtomicOptionReference}

protected class CliApp {
    private let mutex = Mutex()
    protected let agent: Agent
    protected let thinkIndicator = AtomicOptionReference<StatusIndicator>()
    protected let conversationManager: ConversationManager
    protected let customCommandManager: CustomCommandManager
    protected let customAgentManager: CustomAgentManager
    protected let mcpManager: MCPConfigManager
    protected let tokenStatusManager: TokenStatusManager

    protected init() {
        let lang = CliConfig.language.toAsciiLower()
        this.agent = if (lang == 'cangjie') {
            CangjieCodeAgent()
        } else if (lang.startsWith("agent:")) {
            // Currently, this is an internal experimental feature
            // Customized agent: --language agent:<agent_dir>
            let agentDir = lang["agent:".size..]
            CustomAgent(canonicalize(agentDir))
        } else {
            GeneralCodeAgent()
        }
        // Load MCP servers and add their tools to the agent
        this.mcpManager = MCPConfigManager()
        try {
            agent.toolManager.addTools(mcpManager.loadMCPServers())
        } catch (ex: Exception) {
            LogUtils.error("Failed to load MCP servers: ${ex.message}")
            PrintUtils.printProcedureFailure("MCP Loading", failure: "Failed to load MCP servers, continuing without MCP tools")
        }

        this.conversationManager = ConversationManager(FileContextCompactor())
        this.customCommandManager = CustomCommandManager()
        this.customAgentManager = CustomAgentManager()
        this.tokenStatusManager = TokenStatusManager()

        // Initialize event handlers and callbacks
        registerHooks(this)
    }

    func startThinkIndicator(message: String) {
        this.thinkIndicator.store(PrintUtils.printStatusIndicator(message: message))
    }

    func stopThinkIndicator() {
        // Multiple threads may stop the thinkIndicator at the same time:
        // 1. stopped in ChatModelEndEvent by one thread
        // 2. stopped by the main thread when canceling the execution.
        synchronized(this.mutex) {
            if (let Some(i) <- this.thinkIndicator.swap(None)) {
                i.stop()
            }
        }
    }

    protected func startNonInteractive(input: String): Unit {
        processInput(this, input)
        return
    }

    protected func startInteractive(): Unit {
        PrintUtils.printWelcome()
        // Simplified event loop
        while (true) {
            // Update the context usage footnote after each input processing
            this.setContextUsageFootnote()

            let input = InputUtils.getUserInput()
            if (input.trimAscii().isEmpty()) {
                continue
            }
            // Process input and check whether to continue
            if (!processInput(this, input)) {
                break
            }
        }
    }

    /**
    * Display the context usage percentage as the footnote of the readline prompt
    */
    private func setContextUsageFootnote(): Unit {
        // Get the last available model or the default model
        try {
            let percentage = this.tokenStatusManager.contextUsagePercentage
            let remaining = max(0, 100 - percentage)
            let footnote = padString(
                "Context: ${remaining}% remaining".withColor(Theme.current.muted),
                align: Align.Right
            )
            InputUtils.readline.setFootnote(footnote)
        } catch (ex: Exception) {
            LogUtils.error("Failed to compute context usage ${ex.message}")
            InputUtils.readline.setFootnote("")
        }
    }
}
