package cli.core.agents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config

import cli.core.tools.*
import cli.core.config.CliConfig

@agent[
    // model: "ark:ep-20250208101010-dx2ph", //火山v3
    // model: "ark:-20250801112849-w4jk5", //火山k2
    // model: "ark:deepseek-v3-250324",
    // model: "openrouter:moonshotai/kimi-k2:free",
    // model: "ollama:gpt-oss:20b",
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
        ${CODE_AGENT_PROMPT}
        你的当前工作目录是 ${CliConfig.cwd}。
        你的任务是持续迭代，直到完全满足用户的需求。现在开始吧。
        """
    )
}

// @agent[
//     model: "openrouter:qwen/qwen3-coder:free",
//     description: "你是一个专门编写Cangjie代码的专家。",
//     executor: "tool-loop:1000",
// ]
// public class WriteCodeAgent {
//     @prompt(Prompt.get("..\\prompts\\cangjie.md"))
// }
