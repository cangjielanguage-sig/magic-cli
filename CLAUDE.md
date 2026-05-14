# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This project implements a code agent application named Magic CLI, written in the Cangjie programming language.

## Cangjie Language Reference

When unsure about Cangjie standard library APIs (std.fs, std.collection, stdx.encoding.json, etc.), use the context7 MCP tool to look up the documentation. The Cangjie language docs are available via context7.

## Build and Run

```bash
cjpm build -i                                                    # Incremental build
cjpm run --name cli                                              # Run the CLI
cjpm run --name cli --run-args "--auto --language cangjie"       # Run with flags
```

Key CLI flags: `--auto` (skip tool confirmation prompts), `--language cangjie` (use Cangjie-specialized agent), `--model <name>` (override model).

## Architecture

### Entry Point and Input Routing

`src/main.cj` → `src/app/cli_app.cj` (`CliApp`) orchestrates everything. Input in `src/app/process_input.cj` routes based on prefix:
- `!` → shell execution
- `/` → built-in or custom command
- `@AgentName` → invoke a specific agent
- plain text → current default agent

### Agent System

Agents are defined using a Cangjie decorator DSL:

```cangjie
@agent[
    model: CliModelManager.model,
    executor: "tool-loop:1000",
    tools: [FSToolset(), ShellTool(), ...],
    skillRoot: CliConfig.skillRoot
]
public class CangjieCodeAgent {
    @prompt("""...""")
    protected init() { ... }
}
```

The two main agents are:
- **CangjieCodeAgent** (`src/core/agents/cangjie_code_agent/`) — used when `--language cangjie`; has Cangjie-specific tools and documentation RAG
- **GeneralCodeAgent** (`src/core/agents/general_code_agent/`) — default multi-language agent

Sub-agents (ExplorerAgent, EditorAgent, ReviewerAgent, TestGeneratorAgent, RefactoringAgent, PlannerAgent, CangjieFixerAgent) are instantiated as tools via `AgentAsTool(SubAgent(), ...)` and available to both main agents.

**Custom agents** are loaded from `.magic-cli/agents/*/AGENT.md` at startup. Their YAML frontmatter specifies name, description, and which tools they expose.

### Tools

Tools are grouped into toolsets in `src/core/tools/`:
- **FSToolset** — file read/write/edit/list
- **CangjieToolset** — doc retrieval, compile, build, run (Cangjie-specific)
- **ShellTool** — shell execution with optional confirmation
- **SearchToolset** — grep, glob, pattern search
- **GitToolset** — git operations
- **PlanToolset** — todo/task management
- **LSPToolset** — language server protocol (enabled with `--lsp`)

MCP servers defined in `.magic-cli/settings.json` are loaded dynamically as additional tools.

### Commands

Built-in commands live in `src/core/commands/`. Custom commands are JSON files in `.magic-cli/commands/` with `description` and `prompt` fields (supporting `$ARGS` placeholder); invoked as `/cmd:name [args]`.

### Configuration

`src/core/config/cli_config.cj` (`CliConfig`) holds all runtime config as static vars. Key fields: `model`, `fallbackModels`, `temperature`, `auto`, `language`, `enableLSPTool`, `fileReadThreshold`.

Project-level context is read from `AGENTS.md` in the working directory and automatically prepended to agent prompts.

### Context Management

- **Conversation persistence**: `src/core/conversation/` saves/resumes sessions; `last-conversation` is auto-saved on exit.
- **Context compaction**: `FileContextCompactor` summarizes old messages when context grows large.
- **Code compression**: Files exceeding `fileReadThreshold` (default 0.05 × context window × 4 chars/token) are skeletonized before being sent to the model.
- **Model fallback**: `CliModelManager` tries `fallbackModels` on 5xx, 429, 401, or timeout errors.

### Cangjie RAG

`cj-rag/data/cangjiedoc.jsonl` contains Cangjie documentation chunks. Each JSON line has `text`, `short` (summary), and `example_code`. **Search `short` first for efficiency** — the file is large. The `CangjieDocAgent` wraps this retrieval and is available as a tool inside `CangjieCodeAgent`.

## Introduction of Cangjie

Cangjie is a recently introduced programming language. We briefly describe
the syntax of Cangjie below.

### Function definition

Use `func` to define a function, input parameter and return value may have type
annotations. Some parameters may be named (indicated with `!` sign). E.g.

```cangjie
func foo(a: Int64, b!: Int64 = 0)
```

### Function call

In function call, the positional parameters are passed in first,
*without specifying the parameters name*. The named parameters follow in any order,
where the parameter name must be specified. Parameter with default values need not be specified. E.g.

```cangjie
foo(3)
foo(3, b: 2)
```

### Variable declaration

Variable declarations use either `let` or `var`. Variables declared using `let`
are immutable (cannot be assigned after initialization). Variables declared
using `var` can be assigned again within the function.

### Number types

The primitive types for numbers include:

* Signed integers: `Int8`, `Int16`, `Int32`, `Int64`, `IntNative`
* Unsigned integers: `UInt8`, `UInt16`, `UInt32`, `UInt64`, `UIntNative`
* Floating points: `Float16`, `Float32`, `Float64` (Float literals must have a `.`, e.g. 4 should be written as 4.0 to be Float type.)

### Array and ArrayList

Arrays with fixed length are declared using `Array<T>`, where `T` is the type
of elements in the array. Arrays with dynamic length are declared with `ArrayList<T>`.
The use of `ArrayList` requires `import std.collection.*`.

### HashMap and HashSet

`HashMap` represents mapping from keys to values using a hash table. `HashSet` represents
a set of values. Hashable values include numbers and strings but not tuples, `Array` or `ArrayList`.
Use of `HashMap` and `HashSet` requires `import std.collection.*`.

### Sorting

Sorting on arrays requires `import std.sort.*`. The basic syntax is `sort(arr)`.

### Tuples

Tuple types are represented using `(T1, T2, ..., TN)`, where `T1` to `TN` can be any type.
Tuples are immutable. Tuple values are represented using the parenthesis syntax as well.
Elements of a tuple are accessed by array indexing with constant indices (e.g. `t[0]`, `t[1]`).

### If-then-else

In Cangjie, if-then-else expressions require parenthesis around the condition and
brackets around the if and else blocks. E.g.

```cangjie
if (x > 0) {
    y = 1
} else {
    y = 2
}
```

### Iteration

In Cangjie, `..` is used to represent a range, left-closed and right-open. For example, `1..n` represents
from 1 to n, excluding n. `1..=n` represents including n. `n..1 :-1` represents from n down to 1,
excluding 1, when n > 1. To iterate over the interval `[low, high)`, with step k, use:

```cangjie
for (i in low..high: k) {
    ...
}
```

Syntax for while-loops is the same as in other languages.

### Division

In Cangjie, `/` is used instead of `//` to indicate integer division, while the latter is used for comments.

### Option types

Option types are declared using `Option<T>`, with values either `None<T>` (no parenthesis)
or `Some<T>(x)`, where `x` has type `T`. The type `Option<T>` can also be abbreviated as `?T`.

### Strings and characters

The type for characters is called `Rune` in Cangjie. A `Rune` literal starts with the character `r`,
followed by a character enclosed in a pair of single or double quotes. For example:

```cangjie
let a: Rune = r'a'
let s: String = "hello"
```

Use `s.runes()` to return iterator of Runes (type `Iterator<Rune>`). Use `s.toRuneArray()` to
convert the string directly to `Array<Rune>`.

### Bool

The Boolean type has only two literals: `true` and `false`. Operators include `!`, `&&` and `||`.

### Print statements

Function call `print(s)` prints string `s` to the terminal. Function call `println(s)` prints
string `s` followed by newline to the terminal. It is possible to *interpolate* values within
print statements using syntax `\${}`. For example

```cangjie
let a = 1
println("a = \${a}")
```

### Regular expressions

Functionality for regular expressions (including matching, replacement, splitting, obtaining
group information) can be used after import `std.regex.*`. For more examples of using
regular expression in Cangjie, retrieve its documents.

### Datetime functionality

Functionality for working with datetime and duration can be used after importing `std.time.*`.

### Main function

Test code can be placed in the main function. The declaration of main function is *not* preceded
by the `func` keyword. For example:

```cangjie
main() {
    println("Hello")
}
```

### Pipe operator

The pipe operator is convenient for expressing operation on iterators, e.g. when in combination
with functions such as `all`, `any`, `filter`, `map`, etc. For example,

```cangjie
println(0..10 |> map({x: Int64 => 2 * x}) |> all({x: Int64 => x % 2 == 0}))  // true
```

### NOTES

If you are unsure how to use Cangjie, you can search the document `cj-rag/data/cangjiedoc.jsonl`. Each line in this document is a json line containing:

- `text`: split text chunks of original Cangjie documents
- `short`: a short summary of the text
- `example_code`: some example code using elements documented by text

Note it is a huge file; search the `short` field for efficiency.

## Code Style

Write readable code with clear and concise comments.
