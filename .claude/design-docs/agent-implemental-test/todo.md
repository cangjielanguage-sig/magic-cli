# Open Questions / Future Work

## [DONE] Stage 2 — Recursive Sub-Agent Trace Recording and Validation

`ToolStepRecord.subTrace: Option<AgentTrace>` is recorded via `SubAgentEndEvent` + recursive `Recorder.extract`. `Replayer.validate` recurses into `subTrace` using `AgentAsTool.innerAgent`. Backward-compatible with Stage 1 traces (missing `subTrace` key → `Skipped`). Confirmed by Tests C and D (Test D now detects divergence from a file change inside ExplorerAgent).

---

## [DONE] Go Live from Divergence (Stage 3)

**Full design**: `go-live-design.md`

`Replayer.replayLive` walks the recorded trace, feeding cache-hit steps into a `MessageList` history (using `modelOutput` + `toolResultObserved`). At the first divergence it calls `goLive(agent, history, startStep)` — a manual tool loop that calls `agent.model.create`, invokes each tool the model selects, and continues until a final answer. Sub-agent divergence causes go-live at the outer level (sub-agent re-runs from scratch). Pre-Stage-3 traces (missing `modelOutput`) fall back to dry-run.

---

## [LOW] Recursive Go-Live Inside a Sub-Agent

**Problem:** When a sub-agent step diverges, `replayLive` currently goes live at the **outer** level — the sub-agent re-runs entirely from scratch. If the sub-agent had 20 cache-hit internal steps before diverging at step 21, all 20 re-executions are wasted.

**Desired behavior:** At sub-agent divergence, recurse into `goLive` for the sub-agent using its own recorded history up to the inner divergence point, just as the outer agent does.

**Why it's deferred:** Requires passing a `goLive`-capable context into `validateStep` (currently returns a plain `StepResult`). The sub-agent's history reconstruction also needs its `taskPrompt` (currently stored as `""` for sub-agents in `Recorder.extract`). Both are solvable but add non-trivial complexity.

**Related:** Parallel sub-agents would need `roundIndex` grouping (forward-designed in `go-live-design.md`); implement when Magic CLI adds parallel tool-call support.

---

## System Prompt Stability

**Partially validated in Test H (2026-05-18):** AGENTS.md injection into the system prompt works correctly — appending a sentinel line to AGENTS.md causes the system prompt hash to differ, which triggers an immediate full re-run before any tool call. Zero false negatives. However, this only validates the detection side. The false-positive risk (hash shifting due to unintentional dynamic content) is not triggered here because **magic-cli's system prompt is static** — it does not inject current date, environment variables, or other runtime-dynamic content. The strict byte-equality approach is safe for magic-cli as-is, but would need revisiting for agents with genuinely dynamic system prompts.

**Remaining concern:** The hash can shift between runs even when no intentional change was made (e.g., AGENTS.md auto-updated by another tool, or current date injected by the framework). In that case the user pays for a full re-run unnecessarily.

**Current treatment:** For the initial implementation, treat the system prompt as static and use strict byte equality for the hash comparison.

**Ideas for later:**
- Split the system prompt into a *static* part (the agent's `@prompt` content + tool descriptions) and a *dynamic* part (AGENTS.md, injected context). Hash them separately and report changes in each part distinctly.
- On a hash mismatch, show the user a diff of what changed in the system prompt and let them decide: "These changes look unintentional — continue replay anyway?" or "These changes are intentional — go live from step 1."
- Alternatively, let users annotate certain system prompt sections as "dynamic" (exempt from the hash check), so only the stable parts are compared.

**Why it matters:** If AGENTS.md is modified as part of the iteration the user wants to test, the system should correctly start from step 1. But if AGENTS.md changed accidentally (e.g., auto-updated by another tool), the user may want to ignore that diff and replay from where the *intended* change diverges.

---

## [MEDIUM] User-Judged Divergence Exemptions (permission mechanism)

**See design.md Stage 3 for the full specification.** Summary:

Mirror Claude Code's tool-permission flow. When a step reports DIVERGED, prompt the
user interactively: "Step 0 (listDirectory) diverged — only disk free space changed. Ignore
this in future replays? [y/N]". If the user says yes, record their judgment and skip this
category of divergence on subsequent replays — without any static normalization rule.

**Why this is better than static rules for Category 2:**
Static rules bake in the developer's assumptions about what's noise. The user knows their task
and can make a better judgment on the spot. Recording the judgment means they're only asked once
per divergence pattern, same as Claude Code's "always allow this tool" memory.

**Stored in:** `.magic-cli/replay-exemptions.json` (or alongside the trace). Keyed by
`(toolName, divergencePattern)` so the same exemption applies across replay runs.

**Relates to:** Semantic Equivalence item below — the LLM judge could pre-populate exemption
suggestions, but the user has final say.

---

## [MEDIUM] Semantic Equivalence for Category-2 Divergences

**Problem:** The normalizer only suppresses self-induced changes (Category 1 — caused by the
replay mechanism's own file writes, e.g., disk free space). All other divergences are reported
as DIVERGED. But some of these are Category-2 false positives: the tool result changed due to
external noise (CPU jitter, minor disk activity), yet the agent's decision would have been
identical. The user sees DIVERGED and must manually inspect the diff to judge.

**Why we can't suppress Category-2 patterns with static rules:** whether a change is meaningful
depends on the agent's task. Elapsed time matters for a benchmarking task but not for a
file-listing task. Disk usage matters for a capacity-planning task but not for a code-review
task. Static rules that generalize across tasks risk false negatives — silently missing real
divergences.

**Proposed solution: task-context semantic judge (interactive, not in the detection pipeline)**

When DIVERGED is reported, an optional judge can be invoked with:
- The original task prompt
- The tool name and arguments
- The recorded result and the actual (diverged) result

The judge answers: *would the agent's subsequent reasoning have been the same?*

Implementation sketch:
- Small LLM (Haiku) at temperature=0
- System prompt enumerates known noise patterns (elapsed time, minor stat deltas) vs signal
  (file content, function names, directory structure)
- Critically, the task prompt is injected so the judge has context: "given this task, does
  this difference matter?"
- The judge's answer is advisory — it does NOT change the DIVERGED status automatically.
  It is displayed alongside the diff to help the user decide whether to re-run.

**Why LLM is appropriate here (and not in the primary detection path):**
- This is a UX confirmation step, invoked only on DIVERGED steps (rare), not on every step
- Task context makes the judgment tractable — the LLM doesn't need to generalize across all tasks
- A wrong answer (false EQUIVALENT) is less harmful here: the DIVERGED status is still on
  record, and the user sees the actual diff alongside the judgment
- Meta-non-determinism risk is low: the judge is advisory, not authoritative

**Why not in the primary detection path:** detecting divergence must be fast, model-free, and
without false negatives. The judge is a post-divergence tool, not a filter before reporting.

---

## Multi-Turn Sessions

**Problem:** The current design scopes a "task" to a single prompt + response cycle. Multi-turn sessions (multiple back-and-forth exchanges) are not supported.

**Idea for later:** Treat each turn as a task in a chain. The conversation history at the end of turn N becomes a fixed input to turn N+1 (recorded as part of the trace). Replay then works turn by turn, with cache hits possible within each turn's tool loop.
