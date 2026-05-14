# Code Review: feature/agent-replay — Incremental Agent Replay

**Reviewed**: 2026-05-14
**Branch**: `feature/agent-replay`
**Commit**: `373eb5d` — init incremental replay code
**Decision**: REQUEST CHANGES

---

## Summary

The plumbing (arg parsing, config wiring, trace serialization, recorder) is solid and well-structured. The critical gaps are: (1) the feature's central promise — resuming live from a divergence — is not implemented and not declared as deferred; (2) a path traversal security vulnerability exists in `--trace-name` handling; (3) the dry-run replay mode has unguarded destructive side effects. Three issues must be resolved before merge.

---

## Findings

### CRITICAL

**A-1. `model_output` not stored — "go live" is impossible**
`src/replay/trace.cj`, `src/replay/replayer.cj`

The design (design.md §5) requires each step to store the model's output so conversation history can be reconstructed at divergence and the agent can resume with live model calls. `ToolStepRecord` only stores `toolArgsJson` (the action arguments), not the full assistant message. `Replayer.validate` is a dry-run validator only — it cannot "go live." The entire incremental replay value of the feature is absent and not flagged as a known deferral anywhere.

**Fix:** Add `modelOutput: String` to `ToolStepRecord`. Store the full assistant message in `Recorder.buildRecord`. Rename `Replayer.validate` to `Replayer.dryRun` or add a TODO comment explicitly noting live resumption is deferred to a follow-up.

---

**B-1. Path traversal via unsanitized `--trace-name`**
`src/replay/trace_store.cj:41`, `src/parse_args.cj:285`

`CliConfig.traceDir.join("${name}.json")` where `name = trimAscii(userInput)`. A value like `--trace-name ../settings` resolves to `.magic-cli/settings.json` — the MCP config file — and with `--mode record` would silently overwrite it. A value like `../../secret` escapes the project directory entirely.

**Fix:** Reject names containing `/`, `\`, or `..` in `tracePath()`. Ideally allowlist `[a-zA-Z0-9_-]+` only:

```cangjie
public static func tracePath(name: String): Path {
    if (name.contains("/") || name.contains("\\") || name.contains("..")) {
        throw IllegalArgumentException("Invalid trace name: '${name}'")
    }
    return CliConfig.traceDir.join("${name}.json")
}
```

---

### HIGH

**A-2. SHA-256 not implemented — undocumented polynomial hash used**
`src/replay/trace.cj:6-19`

architecture.md §4 specifies SHA-256 via `std.crypto.digest`. The implementation uses a dual-polynomial rolling hash with no explanation or comment. Should either use SHA-256 or document the deliberate fallback.

---

**A-3. `subTrace` field missing — sub-agent changes go undetected**
`src/replay/trace.cj`, `src/replay/replayer.cj`

architecture.md §4 specifies `subTrace: ?AgentTrace` in `ToolStep` for recursive sub-agent replay. The implementation sets `isSubAgentCall = true` but stores nothing sub-agent-specific. `validateStep` unconditionally skips sub-agent steps with `Skipped("sub-agent — skipped to avoid model calls")`. Changes to any sub-agent's prompt or tools will produce false "all cached" results silently.

**Fix:** Either implement Stage 2 sub-trace recording, or change the skip reason to explicitly warn users: *"sub-agent changes will not be detected"* and print a warning in the replay summary when any steps were skipped.

---

**B-2. Replay re-executes destructive tools with side effects**
`src/replay/replayer.cj:111-114`

`tool.invoke(args).content` is called unconditionally for every tool in the trace, including `ShellTool`, `FSToolset` write/edit/delete operations, and `GitToolset` commit/push. Running `--mode replay` on a trace that recorded a `shellExecute("git push origin main")` will push to the remote. The current `--mode replay` has no environment reset and no warning about side effects.

**Fix:** Document clearly that replay is not read-only and requires a clean environment before use. As a minimum, add a printed warning at the start of replay listing which tools will be re-executed.

---

**B-3. Double-read of `response.content`**
`src/replay/replay_runner.cj:26-29`, `src/app/cli_app.cj:69`

`runRecordableTask` calls `let _ = asyncResponse.content` to block but discards the value. `record()` then reads `.content` again on the next line. Safe only if `AsyncAgentResponse` caches the value after the first evaluation. If `content` is a one-shot stream, the second read returns empty or blocks indefinitely.

**Fix:** Return the content from `runRecordableTask`:
```cangjie
public func runRecordableTask(prompt: String): (AsyncAgentResponse, String) {
    let asyncResponse = this.agent.asyncChat(...)
    let content = asyncResponse.content
    return (asyncResponse, content)
}
```

---

**C-2. `--trace-name` accepts arbitrary characters**
`src/parse_args.cj:285`

Only `.trimAscii()` is applied. Shell-special characters and path separators pass through unvalidated. Validate against an allowlist immediately after parsing.

---

### MEDIUM

| ID | File | Issue |
|---|---|---|
| A-4 | `trace_store.cj` | `.json.bak` rotation not implemented (designed in architecture.md §5) — previous trace silently destroyed on overwrite |
| A-5 | `replayer.cj` | Class named `Replayer` but only does dry-run; `tool_replayer.cj` from architecture absent without explanation |
| B-4 | `recorder.cj` | Orphaned `<action>` at end of chatRound silently dropped with no `LogUtils.warn` |
| B-5 | `trace.cj:26-32` | `extractTagContent` uses first `indexOf` for closing tag — truncates if tool results contain `</observation>` or `</action>` |
| B-6 | `trace.cj:127-148` | `version` field not validated on load — future format changes will cause silent corrupt replays |

---

### LOW

| ID | File | Issue |
|---|---|---|
| B-7 | `replayer.cj:51` | `firstDivergenceIndex: Some(0)` with `stepResults: []` on system prompt change is semantically inconsistent; `None` would be more accurate |
| D-1 | `cli_config.cj:14` | `ReplayMode.None` shadows built-in `Option.None` — rename to `Off` or `Normal` |
| D-2 | `cli_config.cj:318` | `replayMode` and `traceName` missing from debug `toString()` output |
| D-3 | `parse_args.cj:276` | `--mode replay` doesn't set `auto`/`nonInteractive` unlike `--mode record` — inconsistency |
| D-4 | `replayer.cj` | `tool_replayer.cj` consolidation undocumented; makes the tool-execution logic harder to unit-test independently |
| D-5 | `trace_store.cj:7` | `remove` imported but unused |

---

## Files Reviewed

| File | Change |
|---|---|
| `src/replay/trace.cj` | Added |
| `src/replay/json_helpers.cj` | Added |
| `src/replay/recorder.cj` | Added |
| `src/replay/replayer.cj` | Added |
| `src/replay/replay_runner.cj` | Added |
| `src/replay/trace_store.cj` | Added |
| `src/app/cli_app.cj` | Modified |
| `src/core/config/cli_config.cj` | Modified |
| `src/main.cj` | Modified |
| `src/parse_args.cj` | Modified |

---

## Must Fix Before Merge
- A-1: `model_output` not stored (or explicitly declare as deferred)
- B-1/C-1: Path traversal in `--trace-name`
- B-2: Replay executes destructive tools without warning
- B-3: Double-read of `response.content`
- A-2: SHA-256 not implemented (or document fallback)
- A-3: Sub-agent changes go undetected (or warn explicitly)
- C-2: `--trace-name` allowlist validation

## Address in Follow-up
A-4, A-5, B-4, B-5, B-6, and all LOW items.
