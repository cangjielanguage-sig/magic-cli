package cli.core.context

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils
import magic.core.message.Conversation
import magic.agent.{ConversationAgent}
import magic.core.interaction.EventResponse
import magic.interaction.{EventHandlerManager, ChatModelStartEvent, ChatModelEndEvent}

import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.commands.CustomCommandManager
import cli.core.config.CliConfig
import cli.core.agents.*
import cli.utils.{PrintUtils, WorkingIndicator, moveCursor, clearScreen, ClearMode}

import std.fs.Path
import std.collection.HashMap
import std.sync.*
import std.env.atExit

protected class CliContext {
    private let _chatAgent: Agent
    private var _agent: AtomicReference<ConversationAgent>
    private let mtx: Mutex = Mutex()
    private let thinkIndicator = AtomicOptionReference<WorkingIndicator>()
    protected let conversationManager: ConversationManager
    protected let customCommandManager: CustomCommandManager
    protected let mcpManager: MCPConfigManager

    protected init() {
        this._chatAgent = if (CliConfig.language.toAsciiLower() == 'cangjie') {
            CangjieCodeAgent()
        } else {
            GeneralCodeAgent()
        }
        let agent = ConversationAgent(this._chatAgent)
        this._agent = AtomicReference(agent)
        // Load MCP servers and add their tools to the agent
        this.mcpManager = MCPConfigManager()
        try {
            agent.toolManager.addTools(mcpManager.loadMCPServers())
        } catch (e: Exception) {
            LogUtils.error("Failed to load MCP servers: ${e.message}")
            PrintUtils.printTool("MCP Loading", "Warning: Failed to load MCP servers, continuing without MCP tools")
        }

        this.conversationManager = ConversationManager(agent, Compactor())
        this.customCommandManager = CustomCommandManager()
    }

    protected func registerHooks() {
        EventHandlerManager.global.addHandler { evt: ChatModelStartEvent =>
            // There may be other agents during the execution.
            // Only show the indicator of the main agent
            if (evt.agent.name == agent.name) {
                this.thinkIndicator.store(PrintUtils.printWorkingIndicator(message: "💭 Thinking"))
            }
            EventResponse.Continue
        }
        // The ToolCallEvent happens after the model giving its reply
        EventHandlerManager.global.addHandler { evt: ChatModelEndEvent =>
            if (evt.agent.name == this.agent.name && let Some(i) <- this.thinkIndicator.load()) {
                i.stop()
            }
        }
        // Register the callback to auto-save conversation
        atExit({
            => conversationManager.autoSave()
        })
    }

    public prop agent: ConversationAgent {
        get() {
            synchronized(mtx) {
                return _agent.load()
            }
        }
    }
}
