package cli.app

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils
import magic.core.message.Conversation
import magic.core.agent.Agent
import magic.interaction.*
import magic.config.Config
import magic.tool.AgentAsTool
import magic.model.ModelManager

import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.commands.CustomCommandManager
import cli.core.config.CliConfig
import cli.core.agents.*
import cli.io.{InputUtils, PrintUtils, StatusIndicator}
import cli.utils.StringUtils
import cli.core.tools.fs_utils.writeFileBasic

import std.collection.ArrayList
import std.fs.{Path, exists, Directory}
import std.collection.HashMap
import std.sync.*
import std.env.atExit

protected class CliApp {
    protected let agent: Agent
    private let mutex = Mutex()
    protected let thinkIndicator = AtomicOptionReference<StatusIndicator>()
    protected let conversationManager: ConversationManager
    protected let customCommandManager: CustomCommandManager
    protected let mcpManager: MCPConfigManager

    protected init() {
        this.agent = if (CliConfig.language.toAsciiLower() == 'cangjie') {
            CangjieCodeAgent()
        } else {
            GeneralCodeAgent()
        }
        // Load MCP servers and add their tools to the agent
        this.mcpManager = MCPConfigManager()
        try {
            agent.toolManager.addTools(mcpManager.loadMCPServers())
        } catch (ex: Exception) {
            LogUtils.error("Failed to load MCP servers: ${ex.message}")
            PrintUtils.printTool("MCP Loading", "Warning: Failed to load MCP servers, continuing without MCP tools")
        }

        this.conversationManager = ConversationManager(Compactor())
        this.customCommandManager = CustomCommandManager()

        // Initialize event handlers and callbacks
        this.registerHooks()
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

    private func registerHooks() {
        // Collect all subAgents as allowed agents that is able to print the thinking indicator
        // CangjieFixer is special which is not added as a subAgent
        let allowedAgentName = ArrayList<String>([
            this.agent.name,
            "CodeAnalyzer",
            "CodeDesigner",
            "CangjieFixer",
            "CangjieDocAgent"
        ])
        for (tool in this.agent.toolManager.tools) {
            if (tool is AgentAsTool) {
                allowedAgentName.add(tool.name)
            }
        }
        //------------------------------------------------------------------------------
        // Use chat model start/end/failure events to show and stop the thinking indicator
        EventHandlerManager.global.addHandler { evt: ChatModelStartEvent =>
            // There may be other agents during the execution.
            // Only show the indicator of the allowed agents
            if (allowedAgentName.contains(evt.agent.name)) {
                let name = StringUtils.splitCamelCase(evt.agent.name)
                this.startThinkIndicator("💭 (${name}) Thinking")
            }
            EventResponse.Continue
        }
        EventHandlerManager.global.addHandler { evt: ChatModelEndEvent =>
            if (allowedAgentName.contains(evt.agent.name)) {
                this.stopThinkIndicator()
            }
        }
        EventHandlerManager.global.addHandler { evt: ChatModelFailureEvent =>
            // If the model context is too long and is truncated, compact the conversation
            if (evt.error == "length") {
                try {
                    this.conversationManager.compact()
                    return Continue(this.agent.model.create(evt.chatRequest))
                } catch (ex: Exception) {
                    LogUtils.error("Failed to compact the conversation or call chat model: ${ex.message}")
                }
            }
            if (allowedAgentName.contains(evt.agent.name)) {
                this.stopThinkIndicator()
            }
            EventResponse.Continue
        }
        //------------------------------------------------------------------------------
        // Use sub-agent start/end events to print the sub-agent execution info
        EventHandlerManager.global.addHandler { evt: SubAgentStartEvent =>
            let name = StringUtils.splitCamelCase(evt.agent.name)
            PrintUtils.printTool(name, "question: ${evt.agentRequest.question}")
            PrintUtils.beginSubAgent()
            EventResponse.Continue
        }
        EventHandlerManager.global.addHandler { evt: SubAgentEndEvent =>
            if (evt.agentResponse.status == AgentResponseStatus.Success) {
                let name = StringUtils.splitCamelCase(evt.agent.name)
                PrintUtils.printLine("🎉 SubAgent ${name} completed 🍻", withIndent: true)
            }
            PrintUtils.endSubAgent()
        }
        // Register the callback to auto-save conversation when exiting the program
        atExit({
            => conversationManager.autoSave()
            InputUtils.exitRawMode()
        })
    }

    /**
     * Switch agent to fallback model
     */
    public func switchToFallbackModel(fallbackModel: ChatModel): Unit {
        this.agent.model = fallbackModel
    }

    protected func startNonInteractive(input: String): Unit {
        if (!exists(CliConfig.printInfoSavingDir)) {
            Directory.create(CliConfig.printInfoSavingDir, recursive: true)
        }
        processInput(this, input)
        return
    }

    protected func startInteractive(): Unit {
        PrintUtils.printWelcome()
        // Simplified event loop
        while (true) {
            let input = InputUtils.getUserInput()
            if (input.isEmpty()) {
                continue
            }

            // Process input and check if we should continue
            if (!processInput(this, input)) {
                break  // Exit requested
            }
        }
    }
}
