package cli.core.context

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils
import magic.core.message.Conversation
import magic.agent.{ConversationAgent}
import magic.core.interaction.EventResponse
import magic.interaction.{EventHandlerManager, PromptValidateEvent, ToolCallEvent}
import cli.bean.*
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

protected class Context {
    private let _chatAgent: Agent
    private var _agent: AtomicReference<ConversationAgent>
    protected var _mode: CliMode = AGENTIC
    protected let conversationManager: ConversationManager
    protected let customCommandManager: CustomCommandManager
    protected let mcpManager: MCPConfigManager
    protected let workspace: Path
    protected let mtx: Mutex = Mutex()
    private let workingThread: AtomicInt64 = AtomicInt64(0)
    private let indicator = AtomicOptionReference<WorkingIndicator>()

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
            PrintUtils.printTool("MCP Loading", "❗ Warning: Failed to load MCP servers, continuing without MCP tools")
        }

        this.conversationManager = ConversationManager(agent, Compactor())
        this.customCommandManager = CustomCommandManager()

        this.workspace = CliConfig.cwd
    }

    protected func registerHooks() {
        // Although we cannot precisely insert instrumentation before and after using the model,
        // since the agent operates in a tool-loop mode (i.e., "model-tool" cycle),
        // we can implement event handling as follows:
        // The PromptValidateEvent happens before using the model
        EventHandlerManager
            .global
            .addHandler {
                evt: PromptValidateEvent =>
                // There may be other agents during the execution.
                // Only show the indicator of the main agent
                if (evt.agent.name == agent.name) {
                    indicator.store(PrintUtils.printWorkingIndicator(message: "💭 Thinking"))
                }
                EventResponse.Continue
            }
        // The ToolCallEvent happens after the model giving its reply
        EventHandlerManager
            .global
            .addHandler {
                evt: ToolCallEvent =>
                let evtAgent = evt.agent
                if (evtAgent.name != this.agent.name) {
                    return EventResponse.Continue(ToolResponse(""))
                }
                if (let Some(i) <- indicator.load()) {
                    i.stop()
                }
                let thread = Thread.currentThread
                if (interrupted(thread.id)) {
                    EventResponse.Terminate(ToolResponse("User Interrupt"))
                } else {
                    EventResponse<ToolResponse>.Continue
                }
            }
        // Register the callback to auto-save conversation
        atExit({
            => conversationManager.autoSave()
        })
    }

    protected prop mode: CliMode {
        get() {
            this._mode
        }
    }

    protected prop agent: ConversationAgent {
        get() {
            synchronized(mtx) {
                return _agent.load()
            }
        }
    }

    protected func changeMode(mode: CliMode): Unit {
        synchronized(mtx) {
            this._mode = mode
        }
    }

    protected func startConversation(threadNum: Int64): Bool {
        synchronized(mtx) {
            match (this.mode) {
                case CHATTING =>
                    this.workingThread.store(threadNum)
                    return true
                case _ => return false
            }
        }
    }

    protected func endConversation(threadNum: Int64): Unit {
        synchronized(mtx) {
            if (!interrupted(threadNum)) {
                changeMode(CliMode.AGENTIC)
            }
        }
    }

    protected func interrupted(threadNum: Int64): Bool {
        synchronized(mtx) {
            threadNum != this.workingThread.load()
        }
    }

    protected func interrupt(): Unit {
        synchronized(mtx) {
            match (this.mode) {
                case CHATTING =>
                    _agent.store(ConversationAgent(this._chatAgent, conversation: this.agent.conversation.clone()))
                    conversationManager.agent = agent
                    this.workingThread.store(0)
                    if (let Some(i) <- indicator.load()) {
                        i.stop()
                    }
                    moveCursor(col: 0)
                    clearScreen(AfterCursorScreen)
                    PrintUtils.printInterrupt()
                    changeMode(CliMode.AGENTIC)
                case _ => PrintUtils.printInterrupt()
            }
        }
    }
}

protected var CLI_CONTEXT: Box<Option<Context>> = Box(None)

protected func getContext(): Context {
    CLI_CONTEXT.value.getOrThrow()
}

protected func setContext(context: Context): Unit {
    CLI_CONTEXT.value = context
}
