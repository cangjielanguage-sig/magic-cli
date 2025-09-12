package cli.core.context

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils
import magic.core.message.Conversation
import magic.agent.{ConversationAgent}
import magic.core.interaction.EventResponse
import magic.interaction.*
import magic.config.Config
import magic.tool.AgentAsTool

import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.commands.CustomCommandManager
import cli.core.config.CliConfig
import cli.core.agents.*
import cli.io.{PrintUtils, WorkingIndicator, moveCursor, clearScreen, ClearMode}

import std.collection.ArrayList
import std.fs.Path
import std.collection.HashMap
import std.sync.*
import std.env.atExit

protected class CliContext {
    private var _agent: AtomicReference<ConversationAgent>
    private let mtx: Mutex = Mutex()
    private let thinkIndicator = AtomicOptionReference<WorkingIndicator>()
    protected let conversationManager: ConversationManager
    protected let customCommandManager: CustomCommandManager
    protected let mcpManager: MCPConfigManager

    protected init() {
        let codeAgent = if (CliConfig.language.toAsciiLower() == 'cangjie') {
            CangjieCodeAgent()
        } else {
            GeneralCodeAgent()
        }
        let agent = ConversationAgent(codeAgent)
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
        // Collect all subAgents as allowed agent that is able to print the thinking indicator
        let allowedAgentName = ArrayList<String>([this.agent.name])
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
                this.thinkIndicator.store(PrintUtils.printWorkingIndicator(message: "💭 (${evt.agent.name}) Thinking"))
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
            if (evt.agent.name == this.agent.name && let Some(i) <- this.thinkIndicator.load()) {
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
        // Register uncaught exception handler to avoid ugly stack traces
        // Note that agent.asyncChat will spawn a thread and throw exceptions there
        // A bug in Cangjie std.core.Thread?
        // If we use Thread.handleUncaughtExceptionBy here, it will not affect threads spawn in Magic
        Config.threadExceptionHandler = { thread: Thread, ex: Exception =>
            LogUtils.error("Uncaught exception in thread ${thread.name}: ${ex}")
        }
        // Register the callback to auto-save conversation when exiting the program
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
