package cli.core.context

import magic.dsl.*
import magic.prelude.*
import magic.agent.ConversationAgent
import cli.core.agents.Compactor
import cli.core.conversation.ConversationManager
import cli.core.mcp.MCPConfigManager
import cli.core.commands.CustomCommandManager
import std.fs.Path
import cli.bean.*

protected class Context {
    protected var agent: ConversationAgent
    protected var compactor: Compactor
    protected var conversationManager: ConversationManager
    protected var mcpManager: MCPConfigManager
    protected var customCommandManager: CustomCommandManager
    protected var mode: CliMode
    protected var workspace: Path

    protected init(agent: ConversationAgent, compactor: Compactor, conversationManager: ConversationManager,
        mcpManager: MCPConfigManager, customCommandManager: CustomCommandManager, workspace: Path, mode!: CliMode = AGENTIC) {
            this.agent = agent
            this.compactor = compactor
            this.conversationManager = conversationManager
            this.mcpManager = mcpManager
            this.customCommandManager = customCommandManager
            this.mode = mode
            this.workspace = workspace
    }

    protected func changeMode(mode: CliMode) {
        this.mode = mode
    }
}

protected var CLI_CONTEXT: Box<Option<Context>> = Box(None)

protected func getContext(): Context {
    CLI_CONTEXT.value.getOrThrow()
}

protected func setContext(context: Context): Unit {
    CLI_CONTEXT.value = context
}
