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

```bash
# Record a run
cjpm run --name cli --run-args "--mode record --trace-name my-task 'fix the bug in foo.cj'"

# Replay after making a change (e.g., editing the agent prompt or a skill file)
cjpm run --name cli --run-args "--mode replay --trace-name my-task"
```

The prompt is given as a positional argument (the same `--prompt` / `-p` mechanism that already exists). Record and replay are non-interactive; they exit after one task.

---

## 3. New Module: `src/replay/`

All new code lives here as a top-level module alongside `src/core/`, `src/app/`, etc. It sits on top of the core primitives rather than being part of them. No existing source files need large changes.

```
src/replay/
├── trace.cj            Data structures: AgentTrace, ToolStep, SubAgentTrace
├── trace_store.cj      JSON serialization / deserialization; load/save from disk
├── recorder.cj         Extracts a trace from a completed agent run
├── tool_replayer.cj    Re-executes a single tool call via the agent's toolManager
├── replayer.cj         Core replay engine: walks the trace, checks hashes, switches live
└── replay_runner.cj    Entry point: wires recording / replay into the CLI flow
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
public struct ToolStep {
    public let index: Int64          // 0-based position in the tool loop
    public let toolName: String      // name of the tool invoked
    public let toolArgs: String      // JSON-encoded arguments (as the model produced them)
    public let toolResult: String    // full text returned by the tool
    public let toolResultHash: String // SHA-256 of toolResult (hex string)
    public let isSubAgentCall: Bool  // true if this step is an AgentAsTool invocation
    public let subTrace: ?AgentTrace // nested trace for sub-agent steps; None otherwise
}

// The complete trace for one agent run (one task prompt → tool loop → final answer).
public struct AgentTrace {
    public let version: String       // "1" — for forward-compat
    public let agentName: String     // e.g. "GeneralCodeAgent"
    public let systemPromptHash: String
    public let taskPrompt: String
    public let steps: Array<ToolStep>
    public let recordedAt: String    // ISO-8601 timestamp
}

public enum ReplayMode {
    None    // normal interactive run
    Record
    Replay
}
```

`AgentTrace` is self-contained: one file = one task run. Nested sub-agent traces are embedded inline (recursive).

**Hash function**: SHA-256 via `std.crypto.digest` if available in the Cangjie stdlib; otherwise fall back to a CRC-32 or the raw result string for the MVP. This is a localized choice in `trace.cj`; easy to swap.

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
public func saveTrace(trace: AgentTrace, name: String): Unit
public func loadTrace(name: String): ?AgentTrace
```

Serialization format: JSON (one file per trace). The project already has a TOML parser and uses JSON for MCP configs, so JSON fits naturally. The `AgentTrace` maps 1-to-1 to a JSON object; `ToolStep` arrays map to JSON arrays. Nested sub-traces are embedded as JSON objects.

---

## 6. Recording (`recorder.cj`)

### How the trace is extracted

The Magic DSL's tool-loop records each model output and tool result in a `ChatRound`. After `asyncChat()` completes, `response.execution.chatRound` contains the `steps: MessageList` for the current task.

Each entry in `steps` is a pair:
- An assistant message containing the model's tool call (tool name + args in JSON)
- A tool-result message containing the tool's return string

`Recorder.extract(response, taskPrompt, agent)` walks these message pairs, hashes each result, and constructs an `AgentTrace`.

**Sub-agent steps**: `hooks.cj` already fires `SubAgentStartEvent` and `SubAgentEndEvent`. We register a recording hook that, when a sub-agent finishes, recursively calls `Recorder.extract` on the sub-agent's response and attaches the resulting sub-trace to the parent step. The `is AgentAsTool` check is already in `hooks.cj:38`.

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

## 8. Multi-Agent Handling (Stage 2)

In this project, sub-agents appear as `AgentAsTool(SubAgent(), mode: SubAgentMode.WithContext)` in the parent's tools list. From the parent tool-loop's perspective, the sub-agent is just a tool that takes a question string and returns a string.

**During recording**: When the parent's tool-loop calls a sub-agent tool, we hook into `SubAgentEndEvent` (already fired by `hooks.cj`) to get the sub-agent's `AsyncAgentResponse`. We recursively call `Recorder.extract` to build a nested `AgentTrace` and attach it as `step.subTrace`.

**During replay**: When we reach a step with `isSubAgentCall == true`, we:
1. Find the matching sub-agent instance from `agent.toolManager`
2. Call `Replayer.run(step.subTrace!, subAgent)` recursively
3. Get the replay's final result
4. Compare its hash to `step.toolResultHash`

Divergence inside a sub-agent's trace means the sub-agent's final output may differ, which causes divergence at the parent level — exactly as the design doc prescribes.

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
[record] Running task: "fix the bug in foo.cj"
[record] step 0: listDirectory(".") → 342 bytes (hash: a3f2...)
[record] step 1: fileRead("foo.cj") → 1204 bytes (hash: 9b1c...)
[record] step 2: ExplorerAgent("what is the structure of...") → sub-trace recorded (8 steps)
[record] step 3: shellExecute("cjpm build -i") → 88 bytes (hash: 71de...)
[record] Trace saved to .magic-cli/traces/my-task.json (4 steps, 1 sub-trace)
```

```
[replay] Checking system prompt... unchanged
[replay] step 0: listDirectory(".") → cache hit
[replay] step 1: fileRead("foo.cj") → DIVERGED (file changed)
[replay] Going live from step 2 with 1 cached step(s) skipped
[live]   step 2: model call...
...
```

---

## 11. Risks and Unknowns

These need to be verified during implementation before committing to Approach A vs B above.

| Unknown | Impact | Plan |
|---|---|---|
| Does `asyncChat(conversation: X)` support pre-built mid-run history? | High — determines whether Approach A works for live resume | Check Magic DSL docs / source; prototype early |
| Does the `@agent` decorator expose `agent.systemPrompt(): String`? | Medium — needed for system prompt hash | Check generated class interface; fallback: hash source file |
| Are `steps: MessageList` entries structured (name + args + result fields) or raw text? | High — needed to extract tool calls post-run for recording | Inspect a real `ChatRound` at runtime with a debug print |
| Does `agent.toolManager` expose a way to invoke a tool by name with JSON args? | High — needed for `ToolReplayer.execute` | Check `ToolManager` API in magic.tool |
