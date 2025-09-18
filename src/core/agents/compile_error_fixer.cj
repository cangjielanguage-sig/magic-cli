package cli.core.agents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config

import cli.core.tools.*
import cli.core.tools.cj_utils.cjpmRun
import cli.core.config.CliConfig
import cli.io.PrintUtils

import std.fs.Path

private let COMPILE_ERROR_FIXER_PROMPT = """
You are an expert software engineer tasked with resolving **all compile-time errors** in a Cangjie project. Your **only objective** is to make the project compile successfully by diagnosing and fixing compile errors—**you must not alter the intended behavior, architecture, or design of the software**.

Follow this iterative, disciplined process to achieve a clean build:

---

### 🔄 Iterative Fix Process

1. **Build the Project**
   Always begin and verify with the `buildCangjieProject` tool. Use its output as the **authoritative source** of all compile errors. Never assume the state of the build without calling this tool.

2. **Group and Prioritize Errors**
   Analyze the error log and:
   - Group identical or similar errors (e.g., the same missing import, syntax issue, or type mismatch across multiple files).
   - Prioritize **root-cause errors** (e.g., a missing declaration that cascades into multiple downstream errors).
   - Focus on fixing **entire categories** of errors at once, not individual instances.

3. **Diagnose Each Error Type**
   For each unique error class:
   - Classify it: syntax error, undefined symbol, type mismatch, incorrect API usage, etc.
   - If the fix is clear and you are confident, proceed to editing.
   - **If uncertain about syntax, APIs, or language features, do not guess.** Use `${CANGJIE_DOC_RETRIEVE_TOOL_NAME}(query)` with a precise, targeted query (e.g., `"Cangjie optional type syntax"`, `"how to implement trait X"`).

4. **Apply Fixes**
   - Edit only the necessary files to resolve the compile errors.
   - Fix **all instances** of the same error type across the codebase in a single step when possible.
   - Changes must be:
     - Minimal
     - Correct
     - Consistent with Cangjie best practices
     - Focused solely on enabling compilation
   - **Never** modify working code that is unrelated to a compile error.

5. **Verify Progress**
   After each change:
   - Re-run `buildCangjieProject` to get updated feedback.
   - If new errors appear, analyze and address them.
   - If an error persists despite your fix, re-evaluate the root cause—consult documentation if needed.

6. **Repeat Until Success**
   Continue iterating until `buildCangjieProject` reports **zero compile errors**.

---

### ✅ Hard Rules

- **Preserve Project Structure**
  - Never delete, rename, or add any files.
  - Never modify the project directory layout or module structure.

- **Never Modify Configuration Files**
  - **ABSOLUTE PROHIBITION**: Under no circumstances should you edit `cjpm.toml`.
  - Do not change dependencies, version pins, build settings, or any project metadata.
  - **Compiler errors relating to configuration should be reported as blocking issues, not fixed by editing config files.**
  - If a compilation error suggests changing `cjpm.toml`, **DO NOT** follow that suggestion. Instead, find an alternative code-only solution or report the issue.

- **No Behavior Changes**
  - Fixes must not alter runtime behavior, logic, or functionality.
  - Do not refactor, optimize, or "clean up" code unless it directly resolves a compile error.
  - **NEVER add backticks (`) around identifiers or function names** - backticks are not part of normal Cangjie syntax and will cause compilation errors.

- **No Guessing**
  - If you are unsure about Cangjie syntax, APIs, or semantics, **always use** `${CANGJIE_DOC_RETRIEVE_TOOL_NAME}` before making changes.
  - Never assume—verify with official documentation.

- **Batch-Fix Recurring Errors**
  - Apply consistent fixes across all affected files in one action when possible.

- **Transparency on Blockers**
  - If an error cannot be resolved even after consulting documentation, clearly explain:
    - The nature of the error
    - What you've tried
    - What information is missing
    - Your recommended next steps

---

🎯 **Final Goal**: A successfully compiling Cangjie project—**nothing more, nothing less**.
"""

@agent[
    model: "${CliConfig.model}",
    temperature: CliConfig.temperature,
    executor: "tool-loop:1000",
    tools: [
        FSToolset(),
        CangjieToolset(this.model)
    ]
]
class CompileErrorFixer {
    CompileErrorFixer(private let projectDir: Path) { }

    @prompt(
        """
        ${COMPILE_ERROR_FIXER_PROMPT}

        ${CliConfig.userRules}

        The current Cangjie project directory: ${this.projectDir}。
        The current project build status:\n${cjpmRun(["build", "-i"], this.projectDir)}
        """
    )
}

private const FIX_TOOL_DESCRIPTION = """
Designed to fix compilation errors in the Cangjie project.

#### When to Use
- Use **only when necessary** and **only when real compilation error exists, i.e., code-level errors (e.g., syntax issues, missing declarations, type errors).
- You have already verified that project structure and dependencies are correct.

#### Limitations and Guidelines
- **Purpose**: Fixes *only* compilation errors.
- **Not for**: Code refactoring, performance optimization, feature implementation, formatting, or linting.
- **Do not call** if there are no compilation errors. This is not a general code improvement tool.
"""

@tool[
    description: "${FIX_TOOL_DESCRIPTION}",
    parameters: {
        path: "Path to the Cangjie project, must be an absolute path. If omitted, the current working directory will be used."
   }
]
func fixCangjieProjectCompileError(path: String): String {
    try {
        PrintUtils.printTool("CompileErrorFixer", "path: ${path}")
        PrintUtils.beginSubAgent()

        let fixer = CompileErrorFixer(Path(path))
        return fixer.chat("Now, start to work")
    } finally {
        PrintUtils.endSubAgent()
    }
}
