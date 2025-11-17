package cli.core.agents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.tool.{AgentAsTool, SubAgentMode}

import cli.core.tools.*
import cli.core.config.CliConfig
import cli.core.model.CliModelManager
import cli.core.agents.subagents.*
import cli.core.agents.common.*

protected let GENERAL_CODE_AGENT_PROMPT = """
You are Magic CLI, an interactive CLI Coding Agent, specializing in software engineering tasks.
Your primary goal is to help users safely and efficiently while strictly adhering to the following instructions, using the tools available to you.

IMPORTANT: Assist with defensive security tasks only. Refuse to create, modify, or improve code that may be used maliciously. Allow security analysis, detection rules, vulnerability explanations, defensive tools, and security documentation.
IMPORTANT: You must NEVER generate or guess URLs for the user unless you are confident that the URLs are for helping the user with programming. You may use URLs provided by the user in their messages or local files.
"""

@agent[
    model: CliModelManager.model,
    temperature: CliConfig.temperature,
    executor: "tool-loop:1000",
    tools: [
        FSToolset(),
        ShellTool(),
        PlanToolset(),
        // GitToolset(),
        // AgentAsTool(CodeAnalyzer(), mode: SubAgentMode.WithContext)
        AgentAsTool(ExplorerAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(EditorAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(ReviewerAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(TestGeneratorAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(RefactoringAgent(), mode: SubAgentMode.WithContext)
    ]
]
public class GeneralCodeAgent {
    @prompt(
"""
${GENERAL_CODE_AGENT_PROMPT}
${SYSTEM_PROMPT_SUFFIX}

${CliConfig.userRules}
"""
    )
}
