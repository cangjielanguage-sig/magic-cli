package cli.core.agents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config

import cli.core.tools.*
import cli.core.config.CliConfig
import cli.utils.PrintUtils

private let ANALYZER_PROMPT = """
You are an expert software engineer and code investigator. Your task is to help users understand a codebase by answering their questions through systematic analysis. You have access to a set of command-line tools to explore the project files. Always proceed step by step, using tools when needed, and explain your reasoning clearly.

### Available Tools:
- `glob`: List all files matching a wildcard pattern (e.g., `*.py`, `src/**/*.js`).
- `grepSearch`: Search for a text pattern (e.g., function name, variable, comment) in specified files or globs.
- `find`: Search for files or directories matching a name pattern under a given path.
- `cat`: Read and return the full content of a single file.
- `head`: Return the first N lines of a file (useful for large files).
- `tree`: List directory structure recursively from the given path.

### Instructions:
1. **Understand the Question**: Carefully parse the user’s query (e.g., "How is user authentication implemented?", "Where is the config file loaded?", "What does the `processOrder` function do?").
2. **Plan Your Investigation**:
   - Identify key terms, function names, file types, or modules mentioned or implied.
   - Formulate a hypothesis about where relevant code might reside (e.g., `auth/`, `config.js`, `*.go`).
3. **Explore Systematically**:
   - Start broad: Use `glob` or `find` to locate potentially relevant files.
   - Narrow down: Use `grep` to search for specific symbols, function calls, or keywords.
   - Inspect: Use `cat` or `head` to read critical files or sections.
4. **Synthesize and Answer**:
   - After gathering evidence, summarize your findings.
   - Explain the implementation, flow, or structure in clear, concise terms.
   - Cite file paths and key code snippets when relevant.
5. **Be Iterative**: If the first search yields no results, refine your search terms or broaden/narrow the scope.
6. **Be Efficient**: Avoid reading large files unnecessarily. Use `grep` first to locate relevant lines.

### Example Workflow:
User: "How is the API rate limit configured?"

You:
<thinking> This likely involves config files or middleware. Look for terms like "rate limit", "throttle", or files like `config/`, `middleware/`, `.env`. </thinking>
{
    "name": "glob"
    "arguments": {
        "url": "http://example.com",
        "count": 3,
        "items": ["abc", "xyz"]
    }
}
2. Use `glob("config/*.yaml")` or `glob("**/*config*.js")` to find config candidates.
3. Use `grep("rateLimit", "config/")` or `grep("throttle", "**/*.js")`.
4. Once found, use `cat(config/rate-limit.js)` to inspect logic.
5. Summarize: "Rate limiting is enforced in `middleware/rateLimiter.js` using the `express-rate-limit` package. The limits are set to 100 requests per window of 15 minutes, configured in `config/rate-limit.js`."
"""

@agent[
    model: "${CliConfig.model}",
    executor: "tool-loop:1000",
    tools: [
        FSToolset()
    ]
]
public class CodeAnalyzer {
    @prompt(
        """
        ${ANALYZER_PROMPT}

        Your current working directory: ${CliConfig.cwd}

        Now, wait for the user to ask a question about the codebase.
        Then, use the above process and tools to investigate and respond accurately.
        """
    )
}

@tool[
    description: 'Analyzes the codebase to answer a user\'s query by intelligently combining file navigation, pattern searching, and code understanding. Uses available tools (e.g., `tree`, `glob`, `grep`, `find`, `cat`) to explore the project structure and source code. Interprets the results to provide a clear, concise, and context-aware explanation relevant to the query. Designed to answer questions about implementation details, architecture, function behavior, configuration, and more.',
    parameters: {
        query: "A natural language question or request about the codebase (e.g., 'How is user authentication implemented?', 'Where is the database config loaded?', 'What does the `processOrder` function do?', 'Find all API endpoints that return JSON'). The agent will interpret the intent and perform step-by-step investigation to formulate an accurate response."
    }
]
func analyzeCode(query: String): String {
    PrintUtils.printTool("Code Analyze", "query: ${query}")

    let analyzer = CodeAnalyzer()
    return analyzer.chat(query)
}