# Go Live from Divergence — Design

**Date**: 2026-05-15
**Status**: Phase 1 implemented (single-agent go-live + Option C sub-agent handling). Recursive sub-agent go-live (Option B / Phase 3) deferred — see `todo.md [LOW]`.
**Prerequisite**: Stage 1 (single-agent dry-run validator) and Stage 2 (recursive sub-agent
validation) are complete. This document designs Stage 3: actually resuming live model execution
from the divergence point rather than just reporting where divergence occurred.

---

## 1. The Gap This Fills

The Stage 2 replayer is a **dry-run validator**. It re-executes each recorded tool call, compares
result hashes, and prints a divergence report. When it finds divergence at step k, it stops
and tells you — but you still have to manually re-run the full task to get a useful outcome.

Stage 3 closes that gap: at the divergence point, the replayer automatically stitches together
the validated steps as conversation context and hands it to the model to continue live. The
user gets a fully-executed run that reused every cache-hit step and only paid model costs from
the divergence onward.

The savings vs. a full re-run are proportional to how many early steps cache-hit. If 7 of
10 steps hit, the cost drops from 10 model calls to 3.

---

## 2. Required Data Structure Additions

Two structures need new fields for go-live. The current `ToolStepRecord` is missing:

```cangjie
public struct ToolStepRecord {
    public let index: Int64
    public let toolName: String
    public let toolArgsJson: String
    public let toolResult: String           // pre-compaction raw result (for hashing only)
    public let toolResultHash: String
    public let isSubAgentCall: Bool
    public let subTrace: Option<AgentTrace> // Stage 2 -- already added

    // MISSING -- needed for Stage 3:
    public let modelOutput: String          // the full assistant message that produced this tool call
                                            // (raw JSON in tool-call mode; <action>...</action> in text mode)
    public let toolResultObserved: String   // the tool result as stored in ChatRound.steps --
                                            // may be an LLM-compacted summary if the raw result
                                            // exceeded toolResultCompactThreshold. This is what
                                            // the model actually saw. Used only for history
                                            // reconstruction during go-live; never for hashing.
}
```

**`modelOutput`**: the assistant's raw message before tag extraction -- including any
`<thought>` content and the tool-call envelope. Used as the "assistant turn" in the
reconstructed conversation history.

**`toolResultObserved`**: the tool result as the model actually saw it during the original
run. This may differ from `toolResult` (raw): when a tool result exceeded the DSL's
`toolResultCompactThreshold`, the DSL LLM-summarized it before adding it to the
conversation -- so `ChatRound.steps` stores the summary, not the full text. The Recorder
captures this directly from the `MessageRole.User` entry in `chatRound.steps` (after the
corresponding assistant message), which is already present. This requires no extra tool
invocation.

`toolResult` (raw, re-invoked) continues to be used for hash comparison -- both recorder
and replayer re-invoke the tool to get the pre-compaction result, keeping them symmetric.
`toolResultObserved` is used only when building the conversation history for go-live.

**`AgentTrace` requires no new fields for conversation-level compaction** — see §6.3 for
why `CompactionEvent` is not needed in the current single-task scope.

---

## 3. Single-Agent Go-Live

### 3.1 Algorithm

```
Replayer.replayLive(trace: AgentTrace, agent: Agent): Unit

1. Check system prompt:
   if hash(agent.systemPrompt) != trace.systemPromptHash:
       go_live_from_step_0(agent, trace.taskPrompt)
       return

2. Walk steps, building conversation history:
   history = []
   for step in trace.steps:
       actualResult = tool.invoke(step.toolArgsJson)

       if hash(normalize(actualResult)) == step.toolResultHash:
           // Cache hit: trust recorded model output, use re-executed result
           history.append(AssistantMessage(step.modelOutput))
           history.append(UserMessage(actualResult))
           print "[replay] step N: cache hit (toolName)"

       else:
           // Divergence at step k:
           // The model's recorded decision (step.modelOutput) was made in a context
           // that still matches (all prior steps were cache-hits). We trust that
           // decision. The new environment just gave a different result. We include
           // both in history so the model can see what actually happened.
           history.append(AssistantMessage(step.modelOutput))
           history.append(UserMessage(actualResult))
           print "[replay] step N: diverged -- going live from step N+1"

           // Hand off to model, which continues from here
           go_live(agent, history)
           return

3. If all steps cache-hit:
   print "[replay] all N step(s) cache-hit -- environment unchanged, run complete"
```

### 3.2 Why the Recorded Model Output Is Trusted at the Divergence Step

At divergence step k, steps 0..k-1 were all cache-hits, meaning the model's input context
at step k is byte-identical to the recording. Therefore the model's decision at step k
(what tool to call, with what args) is the same decision it would make now. We trust
`step.modelOutput` and execute the tool. We get a different result. We put both in history
and let the model see the new outcome and decide what to do next. This is sound.

### 3.3 `go_live` Implementation

```
go_live(agent: Agent, history: Array<Message>): Unit
    // Resume the agent's tool-loop with pre-built history as conversation context.
    // Approach A (preferred): asyncChat with conversation parameter
    agent.asyncChat(conversation: history)

    // Approach B (fallback, if asyncChat doesn't support pre-built history):
    // Manually implement the tool loop:
    loop:
        modelOutput = agent.model.chat(agent.systemPrompt, history)
        if modelOutput.is_final_answer:
            break
        toolResult = agent.toolManager.invoke(modelOutput.toolName, modelOutput.args)
        history.append(AssistantMessage(modelOutput))
        history.append(UserMessage(toolResult))
```

**Critical unknown**: Does `asyncChat(conversation: X)` in the Magic DSL support a
pre-populated mid-run conversation history? This must be prototyped before committing to
Approach A. See §7.

### 3.4 System Prompt Changed — Full Live Run

If the system prompt hash doesn't match, no cached steps are usable. Go live from the
beginning: `agent.run(trace.taskPrompt)` (or equivalent). No conversation history to
reconstruct; this is just a fresh run.

---

## 4. Sub-Agent Go-Live (Sequential)

Magic CLI currently runs sub-agents sequentially: each `AgentAsTool` call is a single
parent step that blocks until the sub-agent finishes. This section covers the sequential case.

### 4.1 The Situation

Parent step i is a sub-agent call (`isSubAgentCall=true`). Stage 2 validation found that
the sub-agent's internal trace diverges at sub-step j.

Three options, in order of ascending power and complexity:

---

### Option A — Re-run Sub-Agent From Scratch, Compare Output

1. Run the sub-agent live from scratch (fresh model calls, starting from the sub-agent's
   task prompt).
2. Get the sub-agent's final answer string.
3. Compare: `hash(final_answer) == step.toolResultHash`?
   - Same → parent step is a **cache-hit**. Continue parent replay.
   - Different → parent step **DIVERGED**. Go live at the parent level (§3).

**Advantage**: Simple. No need for modelOutput in sub-trace steps. No asyncChat history
injection into sub-agent. Sub-agent runs as a black box.

**Disadvantage**: Re-runs the *entire* sub-agent even if only its last 2 of 8 internal
steps diverged. Wastes the sub-agent's own cache-hits.

**When to prefer**: Prototyping, or when sub-agent runs are fast.

---

### Option B — Recursive Live Replay Within Sub-Agent

1. Reconstruct the sub-agent's conversation history for its cache-hit steps 0..j-1.
   Each sub-trace step contributes `(subStep.modelOutput, actualResult)` to the
   sub-agent's history (re-executing each sub-agent tool call along the way).
2. Call `go_live(subAgent, subHistory)` to resume the sub-agent from its divergence step.
3. The sub-agent runs live from step j, producing a final answer.
4. Compare: `hash(final_answer) == step.toolResultHash`?
   - Same → parent step is a **cache-hit**. Continue parent replay.
   - Different → parent step **DIVERGED**. Go live at the parent level.

**Advantage**: Maximally reuses cache. If only the sub-agent's final 2 steps diverged,
only 2 model calls are needed for the sub-agent (instead of 8 from scratch in Option A).

**Disadvantage**: Requires `modelOutput` captured at every sub-trace level. Requires
asyncChat history injection to work in the sub-agent. More complex implementation.

**Recursive composition**: Option B composes naturally. If the sub-agent itself has
sub-sub-agents, the same logic applies at every nesting level. The recursion bottoms
out at leaf agents (no sub-traces).

---

### Option C — Propagate Sub-Agent Divergence Immediately to Parent

At the first sub-trace divergence, immediately mark the parent step DIVERGED and go live
at the parent level. The model will re-invoke the sub-agent tool (or not), and the
sub-agent runs fresh.

**Advantage**: Simplest of all. No sub-agent live-replay needed.

**Disadvantage**: Loses all parent-level cache from step i onward, even if the sub-agent's
output would have been the same. The parent model pays full cost from step i.

**When to prefer**: Very early prototype, or when parent steps beyond step i are cheap.

---

### 4.2 Recommendation

**Phase 1 implementation (current)**: Option C. When a sub-agent step diverges,
`replayLive` triggers `goLive` at the outer (parent) level immediately. The parent model
re-invokes the sub-agent tool, which runs entirely from scratch. This is the simplest
implementation — no sub-agent re-run logic or output comparison needed.

**Phase 2 upgrade** (future): Option A. Re-run the sub-agent from scratch after divergence,
compare final output to `step.toolResultHash`; if unchanged, the parent step is a cache-hit.

**Phase 3 upgrade** (future): Option B. Recursive go-live within the sub-agent using its own
recorded history. Requires `modelOutput` at sub-trace level and a way to inject pre-built
history. See `todo.md [LOW]` for blockers.

Option C was chosen for Phase 1 over Option A because it required fewer implementation layers
and could be validated end-to-end immediately. The known cost is losing parent-level cache
steps after the sub-agent divergence point.

---

### 4.3 Full Sequential Flow (Option B, Recursive)

```
replayLive(trace, agent):
    history = []
    for step in trace.steps:
        actualResult, diverged = replayStep(step, agent, history)
        history.append(AssistantMessage(step.modelOutput))
        history.append(UserMessage(actualResult))
        if diverged:
            go_live(agent, history)
            return

replayStep(step, agent, history) -> (result, diverged):
    if step.isSubAgentCall and step.subTrace.isSome():
        subTrace = step.subTrace.getOrThrow()
        subAgent = (agent.toolManager.findTool(step.toolName) as AgentAsTool).innerAgent

        // Recursively replay the sub-agent's trace
        subResult = replayLiveSubAgent(subTrace, subAgent)

        // Compare sub-agent final output to recorded hash
        if hash(subResult) == step.toolResultHash:
            return (subResult, false)   // parent cache-hit
        else:
            return (subResult, true)    // parent DIVERGED
    else:
        actualResult = tool.invoke(step.toolArgsJson)
        diverged = hash(normalize(actualResult)) != step.toolResultHash
        return (actualResult, diverged)

replayLiveSubAgent(subTrace, subAgent) -> String:
    // Like replayLive but returns the sub-agent's final answer instead of calling go_live
    subHistory = []
    for subStep in subTrace.steps:
        actualResult, diverged = replayStep(subStep, subAgent, subHistory)
        subHistory.append(AssistantMessage(subStep.modelOutput))
        subHistory.append(UserMessage(actualResult))
        if diverged:
            return go_live_and_get_answer(subAgent, subHistory)
    // All sub-steps cache-hit -- sub-agent's final answer is in subHistory
    return extract_final_answer(subHistory)
```

---

## 5. Parallel Sub-Agents — Forward Design

Magic CLI currently has no parallel sub-agent mechanism; all `AgentAsTool` calls are
sequential. This section designs for parallel invocation so the trace format and replay
engine don't need to be redesigned later.

### 5.1 What "Parallel" Means

If the Magic DSL ever supports parallel tool calls (multiple `AgentAsTool` invocations
triggered by a single assistant message), a "round" contains:
- One assistant message (the model decision)
- N simultaneous tool calls (N sub-agents, or a mix of sub-agents and regular tools)
- N results that return (possibly in any order)

In the current flat trace model, these N steps all share the same `modelOutput` and
conceptually belong to the same "round."

### 5.2 Trace Format Extension for Parallel Rounds

Add a `roundIndex: Int64` field to `ToolStepRecord`. Steps with the same `roundIndex`
were issued in the same parallel batch from one model turn.

```
Step 0: roundIndex=0, toolName="listDirectory"
Step 1: roundIndex=1, toolName="ExplorerAgent"   // parallel sub-agents
Step 2: roundIndex=1, toolName="ReviewerAgent"   //
Step 3: roundIndex=2, toolName="shellExecute"
```

All steps with `roundIndex=1` share the same `modelOutput` (the single assistant message
that triggered both sub-agent calls). `roundIndex` is monotonically non-decreasing but
can repeat for parallel steps.

For sequential traces (current case), every step has a unique `roundIndex` — the field
is backward-compatible (or can default to `index`).

### 5.3 Replay Algorithm for Parallel Rounds

```
for round in group_by_roundIndex(trace.steps):
    // Execute all steps in this round (may run concurrently)
    results = parallel_map(round.steps, replayStep)

    allCacheHit = all(not diverged for (_, diverged) in results)

    if allCacheHit:
        // Round is a cache-hit: trust recorded modelOutput, use re-executed results
        history.append(AssistantMessage(round.steps[0].modelOutput))  // shared
        for (step, (result, _)) in zip(round.steps, results):
            history.append(ToolResult(step.toolName, result))

    else:
        // At least one step diverged.
        // Assemble actual results (mix of cached and live outputs):
        assembled = [(step.toolName, result) for (step, (result, _)) in zip(round.steps, results)]

        // Compare each actual result to its recorded hash:
        anyOutputDiffers = any(hash(r) != step.toolResultHash for (step, (r, _)) in ...)

        if not anyOutputDiffers:
            // All divergences were internal (sub-agent internal steps changed but
            // final outputs are the same) -- round is still a cache-hit at the parent level
            history.append(AssistantMessage(round.steps[0].modelOutput))
            for (name, result) in assembled:
                history.append(ToolResult(name, result))
        else:
            // At least one final output differs -- go live from the next round
            history.append(AssistantMessage(round.steps[0].modelOutput))
            for (name, result) in assembled:
                history.append(ToolResult(name, result))
            go_live(agent, history)
            return
```

### 5.4 Key Invariant for Parallel Divergence

**If sub-agent A diverges internally but produces the same final output, and sub-agent B
is a cache-hit, the parent round is still a cache-hit.** The parent model never sees the
difference.

**If sub-agent A produces a different final output, we include the new output in history
(for A) and the cached output (for B), then go live from the next round.** The parent
model will decide what to do with the mixed results.

We do NOT try to run the parent model again for the current round — the recorded
`modelOutput` already decided to call A and B in parallel. We trust that decision (the
input context through the previous round matched). What changes is the results it sees.

### 5.5 Error Cases for Parallel

If one parallel sub-agent **errors** (throws an exception) during live re-execution:
- Treat it as DIVERGED with an error result (the exception message).
- The other parallel sub-agents continue to completion.
- Include the error result in history and go live from the next round.
- Do NOT abort the entire replay — partial results are still useful context.

---

## 6. Conversation History Reconstruction

### 6.1 Message Format

The Magic DSL with `enableModelToolCall=true` uses:

```
AssistantMessage: raw JSON  {"name": "...", "arguments": {...}}
UserMessage:      raw tool result string
```

With `enableModelToolCall=false` (text mode):
```
AssistantMessage: <thought>...</thought><action>```json\n{...}\n```</action>
UserMessage:      <observation>...</observation>
```

`modelOutput` in `ToolStepRecord` stores the **raw assistant message** as seen in
`ChatRound.steps` — whichever format was used during recording. The Recorder captures
this directly from the MessageRole.Assistant entries.

When reconstructing history for `go_live`, wrap each `modelOutput` in an
`AssistantMessage` and each tool result in a `UserMessage` using the same format.

### 6.2 System Prompt Injection

The reconstructed history does NOT re-inject the system prompt — it is passed separately
to the model as the system prompt parameter (Approach A), or prepended by the manual
tool-loop (Approach B). The history only contains the alternating assistant/user turns.

### 6.3 Compaction During the Original Run

Two distinct compaction mechanisms in Magic CLI can affect the conversation context:

#### Per-Result Compaction (DSL `SimpleToolCompactor`)

When a single tool result exceeds `toolResultCompactThreshold` (~1500 bytes), the DSL
LLM-summarizes it before storing it in `ChatRound.steps`. The model sees the summary.

**Impact on go-live**: If we reconstruct history using `toolResult` (raw), the model gets
much more text than it originally saw. Two problems:
- Context window could be exhausted before the divergence step is even reached.
- The model's reasoning at the divergence step is conditioned on a different (richer)
  context than during the original run.

**Fix**: Use `toolResultObserved` for history reconstruction. This is exactly the text
the model originally saw — compacted if the DSL compacted it, raw if it didn't. The
trace stores both fields; go-live uses `toolResultObserved`, hashing uses `toolResult`.

#### Conversation-Level Compaction (`FileContextCompactor`)

`FileContextCompactor` summarizes completed `ChatRound` objects — it fires AFTER a full
chat round has been added to the conversation, not during the execution of a chat round.
A `--mode record` run is a single task = one fresh chat round from an empty conversation.
There are no prior rounds to compact, so `FileContextCompactor` is a no-op for the current
single-task scope. `chatRound.steps` always contains the full uncompacted step messages.

**No `CompactionEvent` needed for now.** The per-result compaction (handled by
`toolResultObserved`) is the only compaction that affects `chatRound.steps`.

**Future scope — multi-turn sessions**: If replay is extended to multi-turn sessions
(where earlier turns may have been compacted before the divergent turn runs), a
`CompactionEvent` structure would be required to record which rounds were summarized and
what summary text was produced, so go-live reconstruction can inject the same summary
rather than the full verbatim earlier turns. This is deferred to that future milestone.

**Compaction during the live phase**: Once `go_live(agent, history)` is running, context
compaction is handled transparently by the DSL's `FileContextCompactor`. No special
handling needed — the DSL takes over from here.

#### Summary: Which Field for Which Purpose

| Purpose | Field to use |
|---|---|
| Hash comparison (divergence detection) | `toolResult` (raw, re-invoked) |
| History reconstruction for go-live | `toolResultObserved` (from `ChatRound.steps`) |
| Divergence report display | `toolResult` (raw, shows actual diff) |

### 6.4 Final Answer Detection

The agent's tool loop terminates when the model outputs a "final answer" (no tool call).
In the replayer:
- During the cached phase: this can't happen mid-trace (recorded steps are all tool calls).
- During the live phase: the `go_live` function runs the full tool loop until the model
  outputs a final answer. No special handling needed — the DSL's asyncChat does this.

---

## 7. asyncChat API Investigation — Resolved

Approach B (manual tool-loop) was implemented directly, without prototyping Approach A.

**Approach B (implemented)**:
```cangjie
// We own the loop — call agent.model.create, invoke tools, append to history
while liveStep < maxSteps:
    let chatResp = agent.model.create(ChatRequest(history, tools: tools))
    let content = chatResp.message.content

    if let Some((toolName, toolArgs)) <- parseToolCall(content, chatResp.toolRequests):
        let result = tool.invoke(toolArgs).content
        if Config.enableModelToolCall:
            history.add(Message.assistant(ToolRequest(name: toolName, args: toolArgs).toJsonValue().toJsonString()))
            history.add(Message.user(result))
        else:
            history.add(Message.assistant(content))
            history.add(Message.user("<observation>${result}</observation>"))
        liveStep++
    else if !content.isEmpty():
        print content   // final answer
        return
    else:
        return          // empty response
```

Approach B requires `agent.model` (for `model.create`) and `agent.toolManager` (for tool lookup),
both of which were already accessible in the replayer. It is fully general and requires no DSL changes.

Approach A (`asyncChat` with pre-built history) was not prototyped. If the DSL ever adds clean support
for it, it could replace the manual loop in `goLive` and allow the sub-agent's own `asyncChat` flow
(including its tool confirmation UX) to handle live execution.

---

## 8. Output Format (Actual — as Implemented)

### Record mode:
```
[record] Task: "fix the bug in foo.cj"
[record] Trace name: my-task
[record] Captured 3 tool step(s) (1 sub-agent with nested trace)
[record] Trace saved -> .magic-cli/traces/my-task.json
```
`modelOutput` and `toolResultObserved` are stored silently — no extra output.

### Replay mode — all cache-hits:
```
[replay] Trace: my-task  (recorded 2026-05-18T...)
[replay] Agent: GeneralCodeAgent
[replay] Task:  "fix the bug in foo.cj"
[replay] Steps: 2

[replay] System prompt: unchanged
[replay] step 0: cache hit  (listDirectory)
[replay] step 1: cache hit  (fileBatchRead)

[replay] Result: all 2 step(s) cache-hit -- no divergence detected
```

### Replay mode — divergence, going live:
```
[replay] System prompt: unchanged
[replay] step 0: cache hit  (listDirectory)
[replay] step 1: DIVERGED   (fileBatchRead)
[replay] Going live from step 1

[replay] go-live step 1: fileBatchRead
[replay] go-live step 2: shellExecute
[replay] go-live: agent finished

<final answer text>
```

### Replay mode — sub-agent diverged (Option C — go live at outer level):
```
[replay] System prompt: unchanged
[replay] step 0: DIVERGED   (ExplorerAgent)
[replay] Going live from step 0

[replay] go-live step 0: ExplorerAgent
[replay] go-live step 1: ExplorerAgent
[replay] go-live: agent finished

<final answer text>
```
The parent model re-invokes ExplorerAgent (which runs from scratch inside `AgentAsTool`).

### Replay mode — system prompt changed:
```
[replay] System prompt changed -- going live from step 0

[replay] go-live step 0: listDirectory
...
[replay] go-live: agent finished

<final answer text>
```

### Replay mode — pre-Stage-3 trace (dry-run fallback):
```
[replay] Trace missing modelOutput (pre-Stage-3) -- dry-run only (re-record to enable go-live)
[replay] System prompt: unchanged
[replay] step 0: cache hit  (listDirectory)
[replay] step 1: DIVERGED   (fileBatchRead)

[replay] Result: diverged at step 1 -- re-record to enable go-live
```

---

## 9. Failure Modes and Edge Cases

### 9.1 Tool Invocation Error During Cached Phase

If re-executing a tool throws an exception (e.g., a file that used to exist is gone):
- Treat as DIVERGED with the error message as the "actual result."
- Include `AssistantMessage(step.modelOutput)` + `UserMessage("ERROR: ...")` in history.
- Go live from the next step.
- The live model will see the error and decide how to handle it.

### 9.2 Sub-Agent Tool Not Found During Live Phase

If the parent goes live and the model decides to call a sub-agent that no longer exists
(e.g., it was removed from the tools list), the tool invocation will fail. This is a
normal live-run failure — report it as an agent error, not a replay error.

### 9.3 Infinite Divergence (All Steps Diverge)

If step 0 diverges, history is empty (no assistant message was appended yet). We call
`go_live(agent, [])` which is equivalent to a full fresh run from the task prompt.

Actually: step 0 has `step.modelOutput` (the model's first decision). We still append it
plus the new result to history. Then go live from step 1 onward. The model sees the new
step-0 result as context.

### 9.4 Trace Has No modelOutput (Old Stage 1/2 Traces)

Old traces recorded before `modelOutput` was added will have an empty string for
`modelOutput`. If go-live is attempted with an old trace:
- Any cache-hit step contributes an empty assistant message to history — this is wrong.
- Detection: check for `modelOutput == ""` at the first cache-hit step.
- Action: warn the user that the trace must be re-recorded to enable go-live, then fall
  back to dry-run validation (report divergence but don't resume live).

### 9.5 Parallel Sub-Agent with Partial Failure

One sub-agent errors, the other succeeds. See §5.5 — treat the errored sub-agent as
DIVERGED, include error result in history, continue with the successful sub-agent's result.

---

## 10. Implementation Plan

### Phase 1 — Single-Agent Go-Live ✓ Implemented

**Changes (all committed):**
1. Added `modelOutput: String` and `toolResultObserved: String` to `ToolStepRecord`; updated
   `init`, `toJsonValue`, `fromJsonValue` (empty string defaults — backward compatible). (f72f6ed)
2. Updated `Recorder.buildRecord` to capture `modelOutput` and `toolResultObserved` from
   `chatRound.steps`. (f72f6ed)
3. Implemented `Replayer.replayLive(trace, agent)` per §3 — uses Approach B (manual tool-loop). (6f3cc51)
4. Implemented `Replayer.goLive(agent, history, startStep)` — manual tool-loop calling
   `agent.model.create`. (6f3cc51)
5. Updated `ReplayRunner.replay()` to call `replayLive` instead of `validate`. (6f3cc51)

**Sub-agent handling**: Option C — when a sub-agent step diverges, `goLive` fires at the outer
level immediately. The parent model re-invokes the sub-agent tool, which runs from scratch.

**Verified by**: Tests A, B, C, D all pass.
- Test A: all cache-hit with go-live trace.
- Test B: step 0 diverges → go live → agent answers including new file.
- Test C: ReviewerAgent step cache-hit.
- Test D: ExplorerAgent diverges → outer go-live → agent re-runs ExplorerAgent.

### Phase 2 — Sequential Sub-Agent Go-Live (Option A)

**Status**: Not yet started. See `todo.md [LOW]` (currently merged with Option B as Phase 3).

**Changes:**
1. In `replayLive`, when a sub-agent step diverges: re-run the sub-agent tool from scratch
   via `AgentAsTool.invoke`, compare output hash to `step.toolResultHash`.
2. If output hash matches → parent cache-hit; if changed → parent DIVERGED → go live at parent.

### Phase 3 — Sequential Sub-Agent Go-Live (Option B — Recursive)

**Status**: Deferred. See `todo.md [LOW]` for blockers.

**Prerequisites:** `modelOutput` captured in sub-trace steps (currently stored as `""` for
sub-agent inner steps, since their `taskPrompt` is empty and their history is not reconstructed).
Needs changes to `Recorder.extract` for sub-agent calls.

**Changes:**
1. Add `replayLiveSubAgent(subTrace, subAgent)` per §4.3.
2. Replace Option C/A with Option B recursive replay in `replayLive`.

### Phase 4 — Parallel Sub-Agent Go-Live

**Prerequisites:** Magic CLI adds parallel tool-call support; Phase 3 working.

**Changes:**
1. Add `roundIndex: Int64` to `ToolStepRecord`.
2. Update Recorder to assign `roundIndex` per parallel batch.
3. Implement `replayLiveRound` per §5.3.

---

## 11. Summary of Decisions

| Decision | Choice | Reason |
|---|---|---|
| modelOutput field | Add to ToolStepRecord | Required to reconstruct conversation history |
| toolResultObserved field | Add to ToolStepRecord | Per-result compaction: model saw the compacted version, not the raw |
| History reconstruction | Use toolResultObserved | Avoids context window overflow; matches what model originally saw |
| Hash comparison | Use toolResult (raw) | Symmetric with replayer re-invocation; compaction is LLM non-deterministic |
| Conversation-level compaction replay | Not needed for single-task scope | FileContextCompactor fires after a round completes; single-task record runs have no prior rounds to compact |
| Pre-built history overflow | Not a concern; detect model-switch and error | toolResultObserved matches original context size; only model-switch between record and replay can break this |
| asyncChat injection | Approach B (manual tool-loop) | Approach A not prototyped; Approach B is fully general and requires no DSL changes |
| Sub-agent strategy Phase 1 (current) | Option C (outer-level go-live) | Simplest; sub-agent re-runs from scratch via parent model |
| Sub-agent strategy Phase 2 (future) | Option A (re-run + compare output) | Sub-agent as black box; simpler than Option B |
| Sub-agent strategy Phase 3 (future) | Option B (recursive live replay) | Maximally reuses cache; deferred — see todo.md [LOW] |
| Parallel sub-agents | Design now, implement later | Trace format must be forward-compatible |
| roundIndex | Add when parallel is implemented | No need before parallel support exists |
| Old trace backward compat | Empty modelOutput → dry-run only | Warn and degrade gracefully |
| Sub-agent with no output change | Parent cache-hit | Maximizes savings; sub-agent internal changes are noise to parent |
