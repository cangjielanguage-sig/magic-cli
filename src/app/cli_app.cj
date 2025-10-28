package cli.app

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils
import magic.core.message.Conversation
import magic.core.agent.Agent
import magic.interaction.*
import magic.config.Config
import magic.tool.{AgentAsTool, SubAgentMode}
import magic.model.ModelManager
import magic.core.model.ChatModel

import cli.core.mcp.MCPConfigManager
import cli.core.conversation.ConversationManager
import cli.core.commands.CustomCommandManager
import cli.core.token_status.TokenStatusManager
import cli.core.config.{CliConfig, ModelTokenLimits}
import cli.core.agents.*
import cli.core.agents.subagents.*
import cli.core.context.{ContextEngine, FileWatcher, DependencyAnalyzer}
import cli.core.tools.FSToolset
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
    protected let tokenStatusManager: TokenStatusManager
    protected let contextEngine: ContextEngine
    protected let fileWatcher: FileWatcher
    protected let dependencyAnalyzer: DependencyAnalyzer

    protected init() {
        // Create main agent
        this.agent = if (CliConfig.language.toAsciiLower() == 'cangjie') {
            CangjieCodeAgent()
        } else {
            GeneralCodeAgent()
        }
        
        // ✨ Multi-Agent System: Create and integrate specialized SubAgents
        // Using AgentAsTool to add SubAgents as tools (equivalent to LeaderGroup pattern)
        
        // Core SubAgents
        let plannerAgent = PlannerAgent()
        let explorerAgent = ExplorerAgent()
        let editorAgent = EditorAgent()
        let reviewerAgent = ReviewerAgent()
        
        // Advanced SubAgents
        let testGeneratorAgent = TestGeneratorAgent()
        let refactoringAgent = RefactoringAgent()
        
        // Add all SubAgents as tools to the main agent
        // SubAgentMode.WithContext allows SubAgents to inherit main agent's context
        agent.toolManager.addTool(AgentAsTool(plannerAgent, mode: SubAgentMode.WithContext))
        agent.toolManager.addTool(AgentAsTool(explorerAgent, mode: SubAgentMode.WithContext))
        agent.toolManager.addTool(AgentAsTool(editorAgent, mode: SubAgentMode.WithContext))
        agent.toolManager.addTool(AgentAsTool(reviewerAgent, mode: SubAgentMode.WithContext))
        agent.toolManager.addTool(AgentAsTool(testGeneratorAgent, mode: SubAgentMode.WithContext))
        agent.toolManager.addTool(AgentAsTool(refactoringAgent, mode: SubAgentMode.WithContext))
        
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
        this.tokenStatusManager = TokenStatusManager()
        this.contextEngine = ContextEngine(maxCacheSize: 50)
        this.fileWatcher = FileWatcher(this.contextEngine)
        this.dependencyAnalyzer = DependencyAnalyzer(this.contextEngine)

        // ✨ FSToolset cache integration - set ContextEngine and FileWatcher
        FSToolset.setContextEngine(this.contextEngine)
        FSToolset.setFileWatcher(this.fileWatcher)

        // Set token info provider (callback pattern used to avoid circular dependency)
        InputUtils.setTokenInfoProvider({ =>
            let currentTokens = this.tokenStatusManager.getLastPromptTokens()
            let maxTokens = ModelTokenLimits.getContextLimit(CliConfig.model.fullName)
            return (currentTokens, maxTokens)
        })

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
            "CodeDesigner",
            "CangjieFixer",
            "CangjieDocAgent",
            // ✨ SubAgents (all 6 SubAgents)
            "PlannerAgent",
            "ExplorerAgent",
            "EditorAgent",
            "ReviewerAgent",
            "TestGeneratorAgent",
            "RefactoringAgent"
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
