package cli.app

import magic.core.agent.AgentResponseStatus
import magic.config.Config
import magic.interaction.*
import magic.log.LogUtils
import magic.model.ModelManager
import magic.tool.AgentAsTool

import cli.core.agents.*
import cli.core.tools.cj_utils.CangjieDocAgent
import cli.io.{InputUtils, PrintUtils, WithColor, Theme}
import cli.utils.StringUtils
import cli.core.agents.subagents.*
import cli.core.config.CliConfig

import std.collection.ArrayList
import std.env.atExit

func registerHooks(app: CliApp) {
    // Collect all subAgents as allowed agents that is able to print the thinking indicator
    // Some agents are special which are not added as subAgents
    let allowedAgentName = ArrayList<String>([
        app.agent.name,
        CodeAnalyzer.typeName,
        CodeDesigner.typeName,
        CangjieFixer.typeName,
        CangjieDocAgent.typeName,
        ExplorerAgent.typeName,
        ReviewerAgent.typeName,
        RefactoringAgent.typeName,
        PlannerAgent.typeName,
        EditorAgent.typeName,
        TestGeneratorAgent.typeName
    ])
    for (tool in app.agent.toolManager.tools) {
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
            app.startThinkIndicator("💭 (${name}) Thinking")
        }
        EventResponse.Continue
    }
    EventHandlerManager.global.addHandler { evt: ChatModelEndEvent =>
        if (allowedAgentName.contains(evt.agent.name)) {
            app.stopThinkIndicator()
        }
        // Add the token usage of the main agent only
        if (let Some(usage) <- evt.chatResponse.usage && evt.agent.name == app.agent.name) {
            app.tokenStatusManager.addUsage(usage)
        }
    }
    EventHandlerManager.global.addHandler { evt: ChatModelFailureEvent =>
        // If the model context is too long and is truncated, compact the conversation
        if (evt.error == "length") {
            try {
                app.conversationManager.compact()
                return Continue(app.agent.model.create(evt.chatRequest))
            } catch (ex: Exception) {
                LogUtils.error("Failed to compact the conversation or call chat model: ${ex.message}")
            }
        }
        if (allowedAgentName.contains(evt.agent.name)) {
            app.stopThinkIndicator()
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
            let name = StringUtils.splitCamelCase(evt.agent.name).withColor(Theme.current.accent)
            PrintUtils.printLine("🎉 SubAgent ${name} completed 🍻", withIndent: true)
        }
        PrintUtils.endSubAgent()
    }

    // Register the callback to auto-save conversation when exiting the program
    atExit({
        => app.conversationManager.autoSave()
        InputUtils.exitRawMode()
    })
}

