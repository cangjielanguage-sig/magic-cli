package cli.app

import magic.core.agent.AgentRequest

import cli.core.agents.subagents.CodeAnalyzer
import cli.core.config.CliConfig
import cli.io.{InputUtils, PrintUtils, Confirmation}

import std.fs.{exists, File}

private const INIT_PROMPT = """
Please analyze the current project directory and generate practical MAGIC.md configuration file content.

Requirements:
1. Analyze project type, programming languages, frameworks, and tools in depth
2. Identify project structure, important files, and configurations
3. Infer appropriate coding standards and best practices
4. Generate project-specific development guidelines and considerations
5. Include specific guidance for AI assistant behavior

Language requirements:
- Detect the primary language used in existing project files, documentation, and comments
- Generate the MAGIC.md content in the same language as the project's primary language
- If unable to determine project language, default to Chinese
- For mixed language projects, prioritize the language used in README files and main documentation

Output format requirements:
- Return the complete MAGIC.md file content directly, no explanatory text
- Use Markdown format
- Include sections: project info, coding standards, development guide, AI assistant guidance
- Content should be specific and practical to guide future AI assistance work
- DO NOT create or write any files, only return the content

Please start analyzing the project and return the MAGIC.md content:
"""

func initMagicFile(): Unit {
    let agent = CodeAnalyzer()
    if (exists(CliConfig.magicMarkdownPath)) {
        if (InputUtils.confirm("MAGIC.md already exists.", "Overwrite?") == Confirmation.Deny) {
            return
        }
    }

    PrintUtils.printTool("MAGIC.md Init", "🔍 Analyzing project structure and generating MAGIC.md...")
    let response = agent.chat(AgentRequest(INIT_PROMPT))

    try {
        File.writeTo(CliConfig.magicMarkdownPath, response.content.toArray())
        PrintUtils.printTool("MAGIC.md Init", "✅ MAGIC.md initialized successfully!")

        let runes = response.content.toRuneArray()
        let preview = if (runes.size > 300) {
            String(runes[0..300]) + "..."
        } else {
            String(runes)
        }
        PrintUtils.printLine("📝 Content preview:")
        PrintUtils.printLine(preview)
        PrintUtils.printLine("\n💡 Use '/memory' to view the full content anytime!")
    } catch (e: Exception) {
        PrintUtils.printLine("❌ Failed to write MAGIC.md: ${e.message}")
    }
}