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
        FSTool(),
        ShellTool(),
        CJTool(this.model),
        PlanTool()
    ]
]
public class CodeAgent {
    @prompt(
        """
        ${CANGJIE_CODE_AGENT_PROMPT}
        你的当前工作目录是 ${CliConfig.cwd}。
        你的任务是持续迭代，直到完全满足用户的需求。现在开始吧。
        """
    )
}
