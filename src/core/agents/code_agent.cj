package cli.core.agents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config

import cli.core.tools.*
import cli.core.config.CliConfig

@agent[
    model: "${CliConfig.model}",
    executor: "tool-loop:1000",
    tools: [
        FSToolset(),
        ShellTool(),
        PlanToolset(),
        analyzeCode
    ]
]
public class GeneralCodeAgent {
    @prompt(
        """
        ${GENERAL_CODE_AGENT_PROMPT}
        Your current working directory: ${CliConfig.cwd}。
        Reply in the same language as the user's input. If unsure, reply in Chinese.

        Finally, you are an agent - please keep going until the user's query is completely resolved.

        """
    )
}

@agent[
    model: "${CliConfig.model}",
    executor: "tool-loop:1000",
    tools: [
        FSToolset(),
        ShellTool(),
        CangjieToolset(this.model),
        PlanToolset(),
        analyzeCode
    ]
]
public class CangjieCodeAgent {
    @prompt(
        """
        ${CANGJIE_CODE_AGENT_PROMPT}
        Your current working directory: ${CliConfig.cwd}。
        Reply in the same language as the user's input. If unsure, reply in Chinese.

        Finally, you are an agent - please keep going until the user's query is completely resolved.

        """
    )
}
