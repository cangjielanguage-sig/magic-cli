package cli.core.context

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils
import magic.core.message.Conversation
import magic.agent.{ConversationAgent}
import magic.core.interaction.EventResponse
import magic.interaction.{EventHandlerManager, ChatModelStartEvent, ChatModelEndEvent}
import cli.context.*
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

protected class CliContext <: Context {
    private let _mainThreadId: Int64
    private let _chatAgent: Agent
    private var _agent: AtomicReference<ConversationAgent>
    private var _mode: CliMode = AGENTIC
    private let _workspace: Path
    private let mtx: Mutex = Mutex()
    private let _workingThread: AtomicInt64 = AtomicInt64(-1)
    private let thinkIndicator = AtomicOptionReference<WorkingIndicator>()
    protected let conversationManager: ConversationManager
    protected let customCommandManager: CustomCommandManager
    protected let mcpManager: MCPConfigManager


    protected init() {
        this._mainThreadId = Thread.currentThread.id
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

        this._workspace = CliConfig.cwd
        this._workingThread.store(this._mainThreadId)
    }

    protected func registerHooks() {
        EventHandlerManager.global.addHandler { evt: ChatModelStartEvent =>
            // There may be other agents during the execution.
            // Only show the indicator of the main agent
            let thread = Thread.currentThread
            if (evt.agent.name == agent.name && !interrupted(thread.id)) {
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

    public prop workspace: Path {
        get() {
            this._workspace
        }
    }

    public prop workingThread: Int64 {
        get() {
            this._workingThread.load()
        }
    }

    public prop mode: CliMode {
        get() {
            this._mode
        }
    }

    public prop agent: ConversationAgent {
        get() {
            synchronized(mtx) {
                return _agent.load()
            }
        }
    }

    public func changeMode(mode: CliMode): Unit {
        synchronized(mtx) {
            this._mode = mode
        }
    }

    public func startConversation(threadNum: Int64): Bool {
        synchronized(mtx) {
            match (this.mode) {
                case CHATTING =>
                    this._workingThread.store(threadNum)
                    return true
                case _ => return false
            }
        }
    }

    public func endConversation(threadNum: Int64): Unit {
        synchronized(mtx) {
            if (!interrupted(threadNum)) {
                this._workingThread.store(this._mainThreadId)
                changeMode(CliMode.AGENTIC)
            }
        }
    }

    public func interrupted(threadNum: Int64): Bool {
        synchronized(mtx) {
            threadNum != this._workingThread.load()
        }
    }

    public func interrupt(): Unit {
        synchronized(mtx) {
            match (this.mode) {
                case CHATTING =>
                    _agent.store(ConversationAgent(this._chatAgent, conversation: this.agent.conversation.clone()))
                    conversationManager.agent = agent
                    this._workingThread.store(this._mainThreadId)
                    if (let Some(i) <- this.thinkIndicator.load()) {
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
