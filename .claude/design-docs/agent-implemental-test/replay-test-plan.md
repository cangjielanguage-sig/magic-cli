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

## What We Are NOT Testing Here

- Live resumption from divergence (deferred — see todo.md [HIGH] item)
- Sub-agent step recording (Stage 2)
- System prompt change detection (harder to trigger without rebuilding)
- Multi-turn sessions

---

## Notes

- The `--auto` flag must be passed explicitly for `--mode record` (suppresses tool confirmation prompts). It is not set automatically.
- Traces are saved to `.magic-cli/traces/replay-test.json`. Inspect this file after Step 1 to verify the structure.
- If the agent answers the prompt without using any tools (pure LLM knowledge), `[record] Captured 0 tool step(s)` will appear and Test B won't be meaningful. In that case, use a more specific prompt that forces file access, e.g. `"Read src/replay/trace.cj and tell me how many public functions it defines"`.
