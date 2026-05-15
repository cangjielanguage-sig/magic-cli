# Incremental Replay — Manual Test Plan

## Goal

Verify two things:
1. **Happy path**: record a run, replay immediately → all steps cache-hit
2. **Divergence detection**: replay after a file change → divergence reported at the right step

---

## Test A — Record then Replay (no change)

### Setup
None. Run from the project root.

### Run
```bash
bash tests/replay/test-a.sh   # bash
.\tests\replay\test-a.ps1     # PowerShell
```

**What the agent will do:** Call a directory-listing tool on `src/replay/`, then batch-read the `.cj` files to describe them. Gives 2–3 tool steps to replay. Task prompt lives in `tests/replay/prompt.txt`.

**Expected output:**
```
[record] Task: "List the files in src/replay/..."
[record] Captured N tool step(s)
[record] Trace saved → .magic-cli/traces/replay-test.json
...
[replay] System prompt: unchanged
[replay] step 0: cache hit  (listDirectory)
[replay] step 1: cache hit  (fileBatchRead)
[replay] Result: all N step(s) cache-hit — no divergence detected
```

### Pass criteria
- All steps show `cache hit`
- Summary says "no divergence detected"

---

## Test B — Replay After File Change (divergence)

Prerequisite: Test A has been run (the `replay-test` trace is on disk).

### Run
```bash
bash tests/replay/test-b.sh   # bash
.\tests\replay\test-b.ps1     # PowerShell
```

The scripts add `src/replay/dummy_test.cj`, run replay, then remove it on exit (bash: `trap EXIT`; PowerShell: `try/finally`).

**Expected output:**
```
[replay] System prompt: unchanged
[replay] step 0: DIVERGED   (listDirectory)
[replay] step 1: cache hit  (fileBatchRead)
[replay] Result: first divergence at step 0 — re-run from that step onward
```

### Pass criteria
- Step 0 (`listDirectory`) shows `DIVERGED` — the new file appears in the listing
- Step 1 (`fileBatchRead`) still shows `cache hit` — file contents are unchanged
- Summary reports first divergence at step 0

---

## Test C — Sub-agent Capture and Replay (ReviewerAgent)

### Purpose
Verify that sub-agent calls are captured in the trace with an embedded `subTrace` and are
recursively validated (not skipped) during Stage 2 replay.

### Run
```bash
bash tests/replay/test-c.sh   # bash
.\tests\replay\test-c.ps1     # PowerShell
```

Prompt (`tests/replay/prompt-c.txt`): lists `src/replay/` then explicitly delegates to
ReviewerAgent — giving a mix of one regular tool step and one sub-agent step.

**Expected output (record):**
```
[record] Captured 2 tool step(s) (1 sub-agent with nested trace)
```

**Expected output (replay):**
```
[replay] step 0: cache hit  (listDirectory)
[replay] step 1: cache hit  (ReviewerAgent)
[replay] Result: all 2 step(s) cache-hit -- no divergence detected
```

### Pass criteria
- Trace file has at least one step with `"isSubAgentCall": true` and a `"subTrace"` field (checked by the script)
- All steps (including ReviewerAgent) show `cache hit`
- Summary reports `all N step(s) cache-hit`

---

## Test D — Stage 2 Positive: Sub-agent Internal Changes Are Detected (ExplorerAgent)

### Purpose
Verify that Stage 2 recursive validation propagates divergence from inside a sub-agent to
the parent. Records a task delegated entirely to ExplorerAgent, modifies a file that
ExplorerAgent read, then replays. The sub-agent's internal `fileBatchRead` step diverges,
which causes the parent `ExplorerAgent` step to report `DIVERGED`.

### Run
```bash
bash tests/replay/test-d.sh   # bash
.\tests\replay\test-d.ps1     # PowerShell
```

Prompt (`tests/replay/prompt-d.txt`): asks ExplorerAgent to explain the `src/replay/` module.
The script appends a sentinel comment to `replayer.cj` between record and replay, then removes
it in cleanup (`trap EXIT` / `try/finally`).

**Expected output (record):**
```
[record] Captured 1 tool step(s) (1 sub-agent with nested trace)
```

**Expected output (replay, after modifying replayer.cj):**
```
[replay] step 0: DIVERGED   (ExplorerAgent)
[replay] Result: first divergence at step 0 -- re-run from that step onward
```

### Pass criteria
- Trace file contains a `"subTrace"` field (checked by the script)
- Replay reports `DIVERGED` for the ExplorerAgent step
- Summary reports first divergence at step 0
- The divergence is caused by the sentinel change inside the sub-agent's nested trace

---

## What We Are NOT Testing Here

- Live resumption from divergence (deferred — see todo.md [HIGH] item)
- System prompt change detection (harder to trigger without rebuilding)
- Multi-turn sessions

---

## Notes

- The `--auto` flag must be passed explicitly for `--mode record` (suppresses tool confirmation prompts). It is not set automatically.
- Traces are saved under `.magic-cli/traces/`. Inspect the JSON file after recording to verify the structure.
- If the agent answers without calling sub-agents, `"isSubAgentCall": true` will be absent from the trace. The scripts warn about this — adjust the prompt if it happens.
- Tests C and D use only read-only sub-agents (ReviewerAgent, ExplorerAgent) to avoid file modifications under `--auto`.
