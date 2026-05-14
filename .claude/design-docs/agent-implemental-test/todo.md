# Open Questions / Future Work

## [HIGH] Go Live from Divergence (Stage 1 completion)

**Problem:** The current `--mode replay` is a dry-run validator only. It re-executes tool calls and reports WHERE the trajectory diverges, but does not resume live model calls from that point. This means the user must manually re-run the full task after identifying the divergence step. The core incremental value — skipping unchanged early steps and resuming from the divergence — is not yet delivered.

**What the design requires (design.md §5):** At divergence, reconstruct the conversation history from recorded model outputs + re-executed tool results, then call `asyncChat(conversation: history)` to continue live from that step. This requires storing `modelOutput` in each `ToolStepRecord`.

**Implementation sketch:**
- Add `modelOutput: String` to `ToolStepRecord` (the full assistant message text including `<thought>` and `<action>` blocks)
- In `Recorder.buildRecord`, store `msg.content` as `modelOutput` (the raw assistant message before tag extraction)
- Add `Replayer.replayLive(trace, agent)` that builds `conversation_so_far` from recorded model outputs + re-executed results, detects divergence, then calls `agent.asyncChat(conversation: conversation_so_far)` to resume
- Verify that `asyncChat(conversation: X)` supports a pre-built mid-run history (see architecture.md §7 Approach A vs B)

**Current workaround:** After `--mode replay` identifies the divergence step, manually run the full task with `--prompt`. Not a blocker for initial testing but limits the feature's value.

---

## System Prompt Stability

**Problem:** The system prompt may contain dynamic content (e.g., AGENTS.md injected from the working directory, current date). This means the hash can shift between runs even when no intentional change was made, forcing a full re-run unnecessarily.

**Current treatment:** For the initial implementation, treat the system prompt as static and use strict byte equality for the hash comparison.

**Ideas for later:**
- Split the system prompt into a *static* part (the agent's `@prompt` content + tool descriptions) and a *dynamic* part (AGENTS.md, injected context). Hash them separately and report changes in each part distinctly.
- On a hash mismatch, show the user a diff of what changed in the system prompt and let them decide: "These changes look unintentional — continue replay anyway?" or "These changes are intentional — go live from step 1."
- Alternatively, let users annotate certain system prompt sections as "dynamic" (exempt from the hash check), so only the stable parts are compared.

**Why it matters:** If AGENTS.md is modified as part of the iteration the user wants to test, the system should correctly start from step 1. But if AGENTS.md changed accidentally (e.g., auto-updated by another tool), the user may want to ignore that diff and replay from where the *intended* change diverges.

---

## Multi-Turn Sessions

**Problem:** The current design scopes a "task" to a single prompt + response cycle. Multi-turn sessions (multiple back-and-forth exchanges) are not supported.

**Idea for later:** Treat each turn as a task in a chain. The conversation history at the end of turn N becomes a fixed input to turn N+1 (recorded as part of the trace). Replay then works turn by turn, with cache hits possible within each turn's tool loop.
