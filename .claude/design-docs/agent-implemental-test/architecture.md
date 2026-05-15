# Incremental Agent Replay — Implementation Architecture

## 1. Scope and Fit

This describes Stage 1 (single agent, manual env reset) and Stage 2 (multi-agent via `AgentAsTool`), implemented as a new operating mode of the existing Magic CLI binary. Sandboxing is deferred.

**Confirmed**: `AgentAsTool(...)` is the only multi-agent mechanism in this project. Both `CangjieCodeAgent` and `GeneralCodeAgent` wrap sub-agents (Explorer, Editor, Reviewer, etc.) exclusively via it. `hooks.cj` already has `is AgentAsTool` detection, which we'll reuse.

---

## 2. User Interface

Two new CLI flags (added to `src/parse_args.cj`):

```
--mode record    Record a run and save the trace.
--mode replay    Replay the most recent trace, skipping cached steps.

--trace-name <name>   Name the trace (default: "last"). Traces are stored
                      in .magic-cli/traces/<name>.json.
```

Usage:

```powershell
# Record a run (use --prompt-file to avoid shell quoting issues inside --run-args)
Set-Content task-prompt.txt "fix the bug in foo.cj"
cjpm run --name cli --run-args "--auto --mode record --trace-name my-task --prompt-file task-prompt.txt"

# Replay after making a change (e.g., editing the agent prompt or a skill file)
cjpm run --name cli --run-args "--auto --mode replay --trace-name my-task"
```

The task prompt is supplied via `--prompt-file <file>` (or `--prompt` / `-p` for short prompts). `--prompt-file` is preferred when the prompt contains spaces, since the entire `--run-args` value is a single string that cjpm splits on whitespace. Record and replay are non-interactive; they exit after one task.

---

## 3. New Module: `src/replay/`

All new code lives here as a top-level module alongside `src/core/`, `src/app/`, etc. It sits on top of the core primitives rather than being part of them. No existing source files need large changes.

```
src/replay/
├── trace.cj               Data structures: AgentTrace, ToolStepRecord; hash + tag helpers
├── trace_store.cj         JSON serialization / deserialization; load/save from disk
├── recorder.cj            Extracts a trace from a completed agent run
├── replayer.cj            Re-executes tool calls, compares hashes, reports divergence
├── result_normalizer.cj   Strips self-induced noise before hashing (see result-normalizer-design.md)
└── replay_runner.cj       Entry point: wires recording / replay into the CLI flow
```

### Modified existing files (minimal changes):

| File | Change |
|---|---|
| `src/parse_args.cj` | Add `--mode` and `--trace-name` to `argSpecs`; store in `CliConfig` |
| `src/core/config/cli_config.cj` | Add `replayMode: ReplayMode`, `traceName: String`, `traceDir: String` |
| `src/main.cj` / `src/app/cli_app.cj` | Branch to `ReplayRunner` when `replayMode != None` |

---

## 4. Data Structures (`trace.cj`)

```cangjie
// A single tool call + result, as recorded during a live run.
public struct ToolStepRecord {
    public let index: Int64           // 0-based position in the tool loop
    public let toolName: String       // name of the tool invoked
    public let toolArgsJson: String   // JSON-encoded arguments object
    public let toolResult: String     // full raw text returned by the tool (pre-compaction)
    public let toolResultHash: String // double polynomial hash of normalize(toolResult)
    public let isSubAgentCall: Bool          // true if this step is an AgentAsTool invocation
    public let subTrace: Option<AgentTrace>  // nested trace for sub-agent steps; None for regular tools
    // Go Live (future): add modelOutput: String (full assistant message, needed for live resume)
}

// The complete trace for one agent run (one task prompt → tool loop → final answer).
public class AgentTrace {
    public let version: String        // "1" — for forward-compat
    public let agentName: String      // e.g. "GeneralCodeAgent"
    public let systemPromptHash: String
    public let taskPrompt: String
    public let steps: Array<ToolStepRecord>
    public let recordedAt: String     // ISO-8601 timestamp
}

public enum ReplayMode {
    | None    // normal interactive run
    | Record
    | Replay
}
```

`AgentTrace` is self-contained: one file = one task run. Sub-agent traces (Stage 2) will be embedded inline as nested `AgentTrace` objects inside `ToolStepRecord`.

**Hash function**: double polynomial hash over UTF-8 bytes, using two independent base/modulus pairs to reduce collision probability. Result format: `"h1:h2"` (both as decimal strings). Implemented in `trace.cj` as `computeHash(s: String): String`. Not SHA-256 — the Cangjie stdlib does not expose a convenient SHA-256 API; the polynomial hash is sufficient for change-detection (not security).

**toolResult stores the pre-compaction raw result**: the Magic DSL's tool-loop may LLM-compact tool results that exceed a size threshold before storing them in `ChatRound.steps`. The recorder re-invokes each tool directly to get the uncompacted result — this is why `toolResult` holds the full raw content, not the `"..."` summary the model saw. See §6 below.

---

## 5. Trace Storage (`trace_store.cj`)

Traces live in `.magic-cli/traces/`. This is consistent with how the project already uses `.magic-cli/` for runtime state (conversations, commands, agents).

```
.magic-cli/
└── traces/
    ├── my-task.json
    ├── my-task.json.bak   ← previous trace, auto-rotated on overwrite
    └── last.json          ← default if --trace-name is omitted
```

`TraceStore` exposes two functions:

```cangjie
public static func save(trace: AgentTrace, name: String): Unit
public static func load(name: String): Option<AgentTrace>
```

Serialization format: JSON (one file per trace). The project already has a TOML parser and uses JSON for MCP configs, so JSON fits naturally. The `AgentTrace` maps 1-to-1 to a JSON object; `ToolStep` arrays map to JSON arrays. Nested sub-traces are embedded as JSON objects.

---

## 6. Recording (`recorder.cj`)

### How the trace is extracted

The Magic DSL's tool-loop records each model output and tool result in a `ChatRound`. After `asyncChat()` completes, `response.execution.chatRound` contains the `steps: MessageList` for the current task.

`ChatRound.steps` message format depends on `Config.enableModelToolCall`:
- **`enableModelToolCall=true` (default in magic-cli)**: no XML tags. Assistant messages carry raw JSON `{"name":..., "arguments":...}`; User messages carry the raw tool result string. Role (`MessageRole.Assistant` / `MessageRole.User`) is the discriminator.
- **`enableModelToolCall=false` (text mode)**: action is wrapped in `<action>...</action>` (with a ` ```json ` fence), observation in `<observation>...</observation>`.

`Recorder.extract(chatRound, taskPrompt, agent)` handles both formats: it tries XML tag extraction first, then falls back to raw content for tool-call mode.

**LLM compaction — critical implementation note**: The Magic DSL compacts tool results that exceed a size threshold (`Config.toolResultCompactThreshold`, default ~1500 bytes) using an LLM summarizer (`SimpleToolCompactor`) before storing them in `ChatRound.steps`. A `fileBatchRead` of several files, for example, is stored as `"..."` in the step messages — not the raw file content. If the recorder naively hashes the observation from `ChatRound.steps`, the hash would be of the compacted summary, while the replayer (which calls the tool directly) would hash the full raw result. They would never match.

**Fix**: `Recorder.buildRecord` re-invokes each tool directly using the recorded args to obtain the pre-compaction raw result. This makes the recorder and replayer symmetric — both hash `normalize(tool.invoke(args).content)`. For tools that cannot be safely re-invoked (sub-agents, or tools whose side effects have already been applied), the recorder falls back to the observed content from `chatRound.steps`.

**Sub-agent steps** (Stage 2, implemented): When a step is an `AgentAsTool` call, `isSubAgentCall` is set to `true` and re-invocation is skipped. Before `runRecordableTask` is called in `replay_runner.cj`, a `SubAgentEndEvent` handler collects `(ChatRound, Agent)` pairs in the order sub-agents complete. `Recorder.extract` iterates over parent steps; for each `AgentAsTool` step, it consumes the next collected capture and recursively calls itself to build a nested `AgentTrace`, stored as `step.subTrace`. Old Stage 1 traces (no `subTrace` key) are backward-compatible: `fromJsonValue` returns `None` for the missing key, and the replayer falls back to `Skipped` with a prompt to re-record.

### System prompt hash

The `@agent` decorator likely exposes a `systemPrompt()` accessor on the generated class. If so, we call it directly. If not (magic DSL doesn't expose it), we hash the agent source file at compile time using a build-stage script and embed the hash as a constant — this is simple since changing the prompt requires a recompile anyway.

**Risk note**: If AGENTS.md is injected into the system prompt at runtime, the hash will differ between environments even without intentional edits. See `todo.md`. For Stage 1, we hash the full system prompt including injected content and document this as a known limitation.

---

## 7. Replay Engine (`replayer.cj`)

### Core algorithm

```
Replayer.run(trace: AgentTrace, agent: Agent): Unit

1. Check system prompt:
   if hash(agent.systemPrompt()) != trace.systemPromptHash:
       print "[replay] System prompt changed — running fully live"
       run_live(trace.taskPrompt, agent)
       return

2. re-execute loop:
   conversation_so_far = []
   for step in trace.steps:
       actual_result = ToolReplayer.execute(step.toolName, step.toolArgs, agent)
       
       if hash(actual_result) == step.toolResultHash:
           // Cache hit: rebuild conversation without calling model
           conversation_so_far.append(recorded_model_output=step.toolArgs, tool_result=actual_result)
           print "[replay] step {step.index}: cache hit ({step.toolName})"
       else:
           // Divergence — rebuild context up to here, then go live
           conversation_so_far.append(recorded_model_output=step.toolArgs, tool_result=actual_result)
           print "[replay] step {step.index}: diverged ({step.toolName}) — going live"
           run_live_from(conversation_so_far, agent)
           return
   
   // All steps matched — replay complete, environment is in final state
   print "[replay] all steps cached, run complete"
```

### Resuming live from a divergence point

At the divergence point, we have `conversation_so_far`: the reconstructed message history using recorded model outputs and re-executed tool results. We need the agent to continue from here.

**Approach A (preferred):** Pass `conversation_so_far` as the `conversation` parameter to `asyncChat`. The agent's tool-loop will see the prior steps as context and continue naturally. This works if the Magic DSL treats the `conversation` parameter as a general message history prepend.

**Approach B (fallback):** If the DSL doesn't support this, implement a minimal manual tool-loop using `agent.model.chat(systemPrompt, messages)` and `agent.toolManager.execute(toolName, args)` directly. This requires more Magic DSL internals but is fully general.

We'll attempt Approach A first during implementation. The choice is localized to `replayer.cj` and `replay_runner.cj`.

### Tool re-execution (`tool_replayer.cj`)

```cangjie
public func execute(toolName: String, toolArgs: String, agent: Agent): String
```

Looks up `toolName` in `agent.toolManager`, deserializes `toolArgs` from JSON, invokes the tool, returns the result string. Side effects (file writes, shell commands) are intentionally re-executed — this is what recreates environment state.

For sub-agent steps (`isSubAgentCall == true`): recursively call `Replayer.run(step.subTrace!, subAgent)` using the appropriate sub-agent instance. The final output of the sub-agent replay is compared to `step.toolResultHash`.

---

## 8. Multi-Agent Handling (Stage 2) — Implemented

In this project, sub-agents appear as `AgentAsTool(SubAgent(), mode: SubAgentMode.WithContext)` in the parent's tools list. From the parent tool-loop's perspective, the sub-agent is just a tool that takes a question string and returns a string.

**During recording**: A `SubAgentEndEvent` handler is registered in `replay_runner.cj` before the task runs. Each time a sub-agent completes, the handler appends `(evt.agentResponse.execution.chatRound, evt.agent)` to a list. Sub-agents in this project run sequentially (not in parallel), so the list is in the same order as the parent tool-loop steps. `Recorder.extract` iterates parent steps; for each step where the tool is an `AgentAsTool`, it consumes the next `(ChatRound, Agent)` pair and calls itself recursively to produce the nested `AgentTrace`, stored as `step.subTrace`. `AgentAsTool` exposes a `public prop innerAgent: Agent` (added to the CangjieMagic library) that gives the replayer access to the sub-agent's `Agent` instance.

**During replay**: When `Replayer.validateStep` encounters a step with `isSubAgentCall=true` and a `Some(subTrace)`, it casts the tool to `AgentAsTool` (via `t as AgentAsTool`, which returns `Option<AgentAsTool>` in Cangjie), retrieves `innerAgent`, then calls `Replayer.validate(subTrace, innerAgent)` recursively. If the sub-replay returns `allCached`, the parent step is `CacheHit`. If the sub-replay detects `systemPromptChanged` or a divergence at step N, the parent step is `Diverged("sub-agent system prompt changed")` or `Diverged("sub-agent diverged at step N")` respectively. Old Stage 1 traces (no `subTrace` field) fall back to `Skipped("no sub-trace -- re-record to enable Stage 2 validation")`.

Divergence inside a sub-agent's trace propagates upward to the parent level, enabling full recursive change detection across the agent call tree.

The DAG structure from the design doc maps onto this as a call tree rather than a general DAG. Sub-agents in this project are not shared across parallel invocations (each `AgentAsTool(SubAgent())` call creates a fresh sub-agent instance), so the DAG is effectively a tree.

---

## 9. CLI Integration

### In `src/parse_args.cj`

Add to `argSpecs`:
```cangjie
Long("mode", RequiredValue),       // "record" or "replay"
Long("trace-name", RequiredValue), // defaults to "last"
```

Add parsing logic:
```cangjie
if let Some(mode) = result.options.get("mode") {
    match (mode) {
        case "record" => CliConfig.replayMode = ReplayMode.Record
        case "replay" => CliConfig.replayMode = ReplayMode.Replay
        case _ => // error
    }
}
CliConfig.traceName = result.options.get("trace-name") ?? "last"
CliConfig.traceDir = Path.join(CliConfig.magicDir, "traces")
```

### In `src/app/cli_app.cj` or `src/main.cj`

After `CliApp` is initialized, before the interactive loop:

```cangjie
match (CliConfig.replayMode) {
    case ReplayMode.Record =>
        ReplayRunner.record(app, CliConfig.prompt)
        return
    case ReplayMode.Replay =>
        ReplayRunner.replay(app, CliConfig.traceName)
        return
    case ReplayMode.None =>
        // normal interactive loop
}
```

`CliConfig.prompt` is already set by `--prompt` / `-p`. Record mode requires a prompt; replay mode loads the task prompt from the trace.

---

## 10. Output Format

Record and replay modes print structured output so the user can see what's happening:

```
[record] Task: "fix the bug in foo.cj"
[record] Trace name: my-task
[record] Captured 3 tool step(s) (1 sub-agent with nested trace)
[record] Trace saved -> .magic-cli/traces/my-task.json
```

```
[replay] Trace: my-task  (recorded 2026-05-15T10:42:54)
[replay] Agent: GeneralCodeAgent
[replay] Task:  "fix the bug in foo.cj"
[replay] Steps: 3

[replay] System prompt: unchanged
[replay] step 0: cache hit  (listDirectory)
[replay] step 1: DIVERGED   (fileBatchRead)
[replay] step 2: cache hit  (shellExecute)

[replay] Result: first divergence at step 1 -- re-run from that step onward
```

Note: Step-by-step byte counts and per-step hash values are not printed in the current implementation — only the cache-hit / DIVERGED / skipped status. Live resumption from the divergence point is not yet implemented (see todo.md [HIGH]).

---

## 11. Risks and Unknowns

| Unknown | Impact | Status |
|---|---|---|
| Does `asyncChat(conversation: X)` support pre-built mid-run history? | High — determines whether Approach A works for live resume | **Open** — needed for [HIGH] "Go Live from Divergence" (see todo.md). Not yet prototyped. |
| Does the `@agent` decorator expose `agent.systemPrompt(): String`? | Medium — needed for system prompt hash | **Resolved** — `agent.systemPrompt` is a direct property access (no method call). |
| Are `steps: MessageList` entries structured or raw text? | High — needed to extract tool calls for recording | **Resolved** — entries are `Message` objects with `.role` and `.content`. With `enableModelToolCall=true`: no XML tags, role is the discriminator. See §6. |
| Does `agent.toolManager` expose a way to invoke a tool by name with JSON args? | High — needed for re-execution in recorder and replayer | **Resolved** — `agent.toolManager.findTool(name)` returns `Option<Tool>`; `tool.invoke(args).content` invokes it. Args are deserialized from JSON via `JsonValue.fromStr(argsJson).asObject().getFields()`. |
| LLM compaction of tool results — does `ChatRound.steps` store raw or compacted results? | High — if compacted, recorder and replayer hash different things | **Resolved** — steps store the compacted form. Fix: recorder re-invokes the tool directly to get the raw result. See §6. |
| Sub-agent `ChatRound` + `Agent` available from `SubAgentEndEvent`? | High — needed for Stage 2 recursive capture | **Resolved** — `SubAgentEndEvent` provides `evt.agentResponse.execution.chatRound` and `evt.agent`; `AgentAsTool.innerAgent` (new prop, added to CangjieMagic) exposes the wrapped sub-agent instance to the replayer. |
