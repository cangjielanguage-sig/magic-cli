package cli

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils
import magic.core.message.Conversation
import magic.core.agent.Agent
import magic.core.interaction.EventResponse
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

import std.collection.ArrayList
import std.fs.Path
import std.collection.HashMap
import std.sync.*
import std.env.atExit

protected class CliContext {
    protected let agent: Agent
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
        } catch (e: Exception) {
            LogUtils.error("Failed to load MCP servers: ${e.message}")
            PrintUtils.printTool("MCP Loading", "Warning: Failed to load MCP servers, continuing without MCP tools")
        }

        this.conversationManager = ConversationManager(Compactor())
        this.customCommandManager = CustomCommandManager()

        // Initialize event handlers and callbacks
        this.registerHooks()
    }

    private func registerHooks() {
        // Collect all subAgents as allowed agents that is able to print the thinking indicator
        // CompileErrorFixer is special which is not added as a subAgent
        let allowedAgentName = ArrayList<String>([
            this.agent.name,
            "CompileErrorFixer",
            "CangjieContext7Agent"
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
                this.thinkIndicator.store(PrintUtils.printStatusIndicator(message: "💭 (${evt.agent.name}) Thinking"))
            }
            EventResponse.Continue
        }
        EventHandlerManager.global.addHandler { evt: ChatModelEndEvent =>
            if (allowedAgentName.contains(evt.agent.name) && let Some(i) <- this.thinkIndicator.load()) {
                i.stop()
                this.thinkIndicator.store(None)
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
            if (allowedAgentName.contains(evt.agent.name) && let Some(i) <- this.thinkIndicator.load()) {
                i.stop()
                this.thinkIndicator.store(None)
            }
            EventResponse.Continue
        }
        //------------------------------------------------------------------------------
        // Use sub-agent start/end events to print the sub-agent execution info
        EventHandlerManager.global.addHandler { evt: SubAgentStartEvent =>
            PrintUtils.printTool(evt.agent.name, "question: ${evt.agentRequest.question}")
            PrintUtils.beginSubAgent()
            EventResponse.Continue
        }
        EventHandlerManager.global.addHandler { evt: SubAgentEndEvent =>
            PrintUtils.printLine("🎉 SubAgent ${evt.agent.name} completed 🍻", withIndent: true)
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
    public func switchToFallbackModel(fallbackModel: String): Unit {
        this.agent.model = ModelManager.createChatModel(fallbackModel)
    }
}
