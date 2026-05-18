# Replay Performance Test Suite — Design

**Date**: 2026-05-18
**Status**: Design — pending review

---

## 1. Goals

Tests A–D verify correctness (does replay detect divergence?). This suite asks a different
question: **does replay save time vs. a full re-run, and by how much — across the different
kinds of changes a developer actually makes?**

The core insight from the design doc is that everything entering an agent's context does so
through exactly two channels: the system prompt, or a tool call result. Every developer
action that matters maps to one of these two channels:

| What the developer changed | Replay channel affected |
|---------------------------|------------------------|
| A source file the agent reads | Tool call result changes |
| A skill body (guidance doc) the agent fetches | Tool call result changes |
| A custom tool's implementation / output | Tool call result changes |
| Skill metadata / agent prompt / AGENTS.md | System prompt changes |
| A new tool added to the agent's tool list | System prompt changes (descriptions) |

Tests are organized into three categories to cover each surface:

---

## 2. Test Overview

| Test | Category | Scenario | Divergence point |
|------|----------|----------|-----------------|
| E | Baseline | No change — pure cache | None (all cache-hit) |
| F | File | Late-stage source file change | Step 5/6 |
| G | Skill | Skill body change (guidance doc updated) | Step 0 (skill read first) |
| H | Skill | System prompt change via AGENTS.md | Step 0 (full re-run forced) |
| I | Tool | Tool behavior change (shell script proxy) | Step N (when tool is called) |
| J | Tool + Multi-agent | ExplorerAgent caches; outer script call diverges | Step 1 (after sub-agent cache-hit) |

---

## 3. Measurement Methodology

Each test runs three phases, timed with PowerShell `Measure-Command`:

```
Phase 1 — Baseline record
    Run the agent with --mode record on the original environment.
    Time = T_record. This establishes what a full run costs before any change.

Phase 2 — Replay after mutation
    Apply the change (edit a file, modify a script, update AGENTS.md, etc.).
    Run --mode replay.
    Time = T_replay.

Phase 3 — Fresh re-run after mutation
    Run the same task with --auto --prompt-file but without --mode.
    Time = T_fresh. This is what the user pays without replay.

Cleanup
    Restore all mutated files in try/finally.
```

**Speedup** = T_fresh / T_replay. Values > 1 mean replay was faster.

**Cache-hits** are counted by parsing `[replay] step N: cache hit` lines from replay stdout.

---

## 4. Category 1 — File Content Changes

### Test E — No Change (Pure Cache Baseline)

**Real practice**: re-running a stable benchmark after a refactor to verify nothing drifted.

**Task prompt** (`prompt-e.txt`):
```
Read each of these files in src/replay/ in this exact order:
  recorder.cj, replayer.cj, replay_runner.cj, result_normalizer.cj, trace.cj, trace_store.cj

For each file output: (1) its purpose in one sentence, (2) its public types and functions,
(3) which other replay-module files it imports. Present as a numbered list, one entry per file.
```

The explicit ordering forces a deterministic 6-step `fileBatchRead` sequence.

**Mutation**: none.

**Expected**:
- 6/6 cache-hits; T_replay ≈ 6 × tool_invoke_time (~3–6s total)
- Speedup: very high (15–40×) — the ceiling for replay savings

---

### Test F — Late-Stage Source File Change

**Real practice**: fixing a bug or adding a comment to one file late in the read sequence.

**Task prompt**: same as Test E (`prompt-e.txt`).

**Mutation**: append sentinel to `src/replay/trace_store.cj` (6th file in the read order):
```cangjie
// PERF-TEST-F-SENTINEL
```

**Expected**:
- 5/6 cache-hits; diverge at step 5 (`trace_store.cj` read)
- Go-live produces the same answer as a fresh run, but skipped 5 model calls
- Speedup: 3–6× (proportional to model latency savings)

---

## 5. Category 2 — Skill Changes

Skill changes map to two distinct replay behaviors depending on *where* the skill lives.

### Test G — Skill Body Change (Single Agent)

**Real practice**: developer iterates on a skill's instructions — adding a new rule to a code
review checklist, tightening a constraint, or clarifying guidance. The skill body enters the
agent's context via a tool call (not the system prompt), so changing it triggers a tool-result
divergence at the step where the agent fetches it.

**How skill body enters context**: the agent reads the skill file via `fileBatchRead`. The
skill file has a real skill format — YAML frontmatter (name, description, trigger) plus an
instruction body. Changing the body changes the tool result; changing the frontmatter alone
would be invisible to replay (frontmatter is not in the main agent's system prompt for
custom agents).

**Setup**: create `tests/replay/skills/code-reviewer.md`:
```markdown
---
name: code-reviewer
description: Reviews Cangjie code for quality issues following project standards
trigger: when asked to review code
---

Apply these rules when reviewing Cangjie code:
1. Flag any function exceeding 50 lines.
2. Verify all caught exceptions are handled (not silently swallowed).
3. Check that all public functions and types have a one-line doc comment.
```

**Task prompt** (`prompt-g.txt`):
```
Read the skill definition at tests/replay/skills/code-reviewer.md to load your review
criteria. Then read src/replay/recorder.cj and apply those criteria exactly.
List each finding with the rule number it violates. If no violations, say "No issues found."
```

Agent reads the skill first (step 0), then the source file (step 1). Single agent, no sub-agents.

**Mutation**: add a new rule to the skill body:
```
4. Check for hardcoded string or numeric literals that should be named constants.
```

**Expected**:
- Step 0 (skill read) `DIVERGED` → go-live from step 0
- Live agent reads the updated skill and applies all 4 rules to `recorder.cj`
- Speedup: ~1× (diverge at step 0, rest runs live)
- **What this validates**: the two-channel model covers skill body changes transparently —
  skill content is a tool result, so it is caught by the same hash comparison as any other
  file. No special skill-awareness is needed in the replay engine.

---

### Test H — System Prompt Change via AGENTS.md

**Real practice**: developer updates skill metadata — the agent's description, a tool's
description, or which skills it claims to have. This is the more disruptive change.

**Why this is different**: AGENTS.md content is injected into the agent's system prompt at
startup. Changing it changes the system prompt hash → replay detects this immediately at step 0
and forces a full re-run without executing any cached tool steps.

**Setup**: create `AGENTS.md` in the project root (or append to it if one exists):
```markdown
# Project Context

This is the Magic CLI project. When analyzing code, note that this codebase uses
the Cangjie programming language.
```

**Record** with this AGENTS.md present.

**Mutation**: add a line to AGENTS.md:
```markdown
Key module: src/replay/ implements incremental agent replay (record/replay).
```

**Expected**:
- `[replay] System prompt changed -- going live from step 0`
- No cache-hit steps at all; full fresh model run
- T_replay ≈ T_fresh (replay overhead is negligible — immediate go-live)
- Speedup: ~1× (no caching possible)
- **Key insight**: this test explicitly shows when replay CANNOT help — and that is correct. The report should highlight the contrast with Test G: both are "skill changes", but body changes (Test G) are tool-result divergences that cache early steps, while metadata changes (Test H) are system-prompt divergences that cache nothing.

**Implementation note**: if no AGENTS.md exists at project root, the test creates one for
recording and modifies it for replay. Cleanup removes it entirely. If one already exists, the
test appends/restores (using try/finally).

---

## 6. Category 3 — Tool Changes

Tool changes mean the tool's output for the same inputs has changed. From the replay system's
perspective, this is identical to a file change — what matters is the tool result hash.

### Test I — Tool Behavior Change (Shell Script Proxy)

**Real practice**: developer fixes a bug in a custom tool (e.g., a search tool, a code
analysis tool, a database lookup tool). The tool now returns different output for the same
inputs.

**How we simulate without modifying Magic CLI source**: the agent calls `ShellTool` to run
a PowerShell script. That script IS the "tool". Changing the script simulates changing the
tool's implementation.

**Setup**: create `tests/replay/tools/line-stats.ps1`:
```powershell
# Reports the line count for each .cj file in src/replay/
Get-ChildItem src\replay\*.cj | ForEach-Object {
    $lines = (Get-Content $_.FullName).Count
    "$($_.Name): $lines lines"
} | Sort-Object
```

**Task prompt** (`prompt-i.txt`):
```
Run the following PowerShell command and report the results:
  powershell -File tests\replay\tools\line-stats.ps1

Then tell me which file has the most lines and which has the fewest.
```

**Mutation**: modify `line-stats.ps1` to also report file sizes:
```powershell
Get-ChildItem src\replay\*.cj | ForEach-Object {
    $lines = (Get-Content $_.FullName).Count
    $size  = $_.Length
    "$($_.Name): $lines lines, $size bytes"
} | Sort-Object
```

**Expected**:
- Diverge at the step where the shell command runs (its output now includes byte counts)
- Go-live from that step; agent re-interprets the richer output
- Speedup: depends on how many steps precede the tool call; with a direct prompt like above,
  diverge at step 0 → speedup ~1×
- **Key insight**: the replay system detects tool behavior changes through the same hash
  mechanism as file changes. No special handling needed. This validates the design's claim
  that the two channels cover tool changes transparently.

**Variant (optional)**: make the tool call happen at step 2 (after some directory listing)
to show a mid-trace tool divergence with partial cache savings.

---

### Test J — Multi-Agent with Tool Change at Outer Level

**Real practice**: a pipeline where one sub-agent does exploration (files unchanged, cache-hit)
and the outer agent also calls a tool directly. The tool's output changes. The sub-agent step
caches; the subsequent tool-call step diverges.

**Why this design (not "tool change inside sub-agent")**: relying on ExplorerAgent to
internally call a specific shell script is unreliable — the sub-agent is autonomous and may
choose different tools. Instead, the outer agent calls the script directly (reliable), and
ExplorerAgent does its natural file exploration (also reliable). This gives a cleaner
partial-cache scenario.

**Setup**: reuse `tests/replay/tools/line-stats.ps1` from Test I (in its original form).

**Task prompt** (`prompt-j.txt`):
```
Do two things in order:

1. Use the ExplorerAgent to explore src/replay/ and list the public types and functions
   defined in each file (names only).

2. Run the following command and report which file has the most lines and which has the fewest:
   powershell -File tests\replay\tools\line-stats.ps1

Present both results clearly labeled.
```

Step 0: ExplorerAgent (sub-agent, reads src/replay/ files).
Step 1: outer agent runs `line-stats.ps1` via ShellTool.

**Mutation**: modify `line-stats.ps1` (same change as Test I — add byte counts to output).

**Expected**:
- Step 0 (ExplorerAgent): files unchanged → `cache hit` (sub-trace all-cached)
- Step 1 (script call): script output changed → `DIVERGED` → go-live from step 1
- Live agent re-runs the script, reads new output, produces updated answer
- Speedup: moderate — 1 sub-agent step caches (skips all internal ExplorerAgent model calls)
- **Key insight**: partial caching in a multi-agent pipeline. The sub-agent caches even when
  a subsequent outer tool call diverges. This shows the replay boundary working correctly:
  caching stops at the divergence step, not at the first sub-agent call.

---

## 7. Metrics Per Test

```
T_record      seconds   full-run cost before any change (trace write included)
T_replay      seconds   replay cost after mutation
T_fresh       seconds   fresh re-run cost after mutation (no replay infrastructure)
cache_hits    int       parent-level steps that were cache-hits during replay
total_steps   int       total parent-level steps in the trace
speedup       float     T_fresh / T_replay
diverge_at    string    "step N (toolName)" or "system prompt" or "none"
```

---

## 8. Infrastructure

### File layout

```
tests/replay/
├── prompt-e.txt                 # shared: file analysis, explicit order
├── prompt-g.txt                 # skill body: guide + apply to recorder.cj
├── prompt-i.txt                 # tool behavior: run line-stats, summarize
├── prompt-j.txt                 # multi-agent + tool: ExplorerAgent + direct read
├── skills/
│   └── analysis-guide.md       # skill body used in Test G
├── tools/
│   └── line-stats.ps1          # shell script proxy for custom tool (Tests I, J)
├── test-e.ps1
├── test-f.ps1
├── test-g.ps1
├── test-h.ps1
├── test-i.ps1
├── test-j.ps1
└── run-perf-suite.ps1           # runs all 6, generates report
```

### Per-test script structure

Each script:
1. Sets up fixtures (creates skill/tool files if needed)
2. Phase 1: `Measure-Command { cjpm run ... --mode record }` → `T_record`
3. Applies mutation
4. Phase 2: `Measure-Command { cjpm run ... --mode replay }` → `T_replay`; captures stdout; parses cache-hit count
5. Phase 3: `Measure-Command { cjpm run ... --auto --prompt-file ... }` → `T_fresh`
6. `try/finally` restores all mutated files and removes fixtures
7. Emits JSON result to `.magic-cli/perf-results/<test>.json`

### Suite runner

`run-perf-suite.ps1` runs E through J in sequence, then reads the 6 JSON results and
renders `tests/replay/report-<timestamp>.md`.

---

## 9. Test Report Format

```markdown
# Replay Performance Report

Generated: 2026-05-18T14:32:11
Branch: feature/agent-replay

## Results

| Test | Category | Scenario | Steps | Cache Hits | Diverge At | T_record | T_replay | T_fresh | Speedup |
|------|----------|----------|-------|------------|------------|----------|----------|---------|---------|
| E | Baseline | No change | 6 | 6/6 | none | 93s | 4s | 91s | 22.8× |
| F | File | Late file change | 6 | 5/6 | step 5 | 95s | 22s | 92s | 4.2× |
| G | Skill | Skill body change | 2 | 0/2 | step 0 | 48s | 44s | 46s | 1.0× |
| H | Skill | System prompt change | 6 | 0/6 | sys prompt | 93s | 91s | 91s | 1.0× |
| I | Tool | Tool behavior change | 1 | 0/1 | step 0 | 31s | 29s | 30s | 1.0× |
| J | Tool+Multi | ExplorerAgent caches; outer script diverges | 2 | 1/2 | step 1 | 72s | 38s | 70s | 1.8× |

## Key Findings

### When replay saves the most (Tests E, F)
Pure file-read pipelines with late-stage changes are the ideal case. T_replay drops to
near-zero for all-cache-hit runs (Test E: 22.8×). With a late change, 5/6 model calls
are saved (Test F: 4.2×).

### Skill body vs. skill metadata (Tests G vs. H)
Both are "skill changes" but have opposite replay behaviors:
- Skill body (fetched via tool): detected as a tool-result divergence. Partial caching
  is possible if other steps precede it. Same mechanism as file changes.
- Skill metadata / system prompt (AGENTS.md): detected immediately via system prompt hash.
  No caching possible. Speedup is ~1×. This is correct and expected — the model's entire
  reasoning from step 0 might be affected by a prompt change.

The contrast shows that the design's two-channel model maps naturally onto real development
workflows: iterate on content → tool-result divergence (partial cache); iterate on prompts/
metadata → system-prompt divergence (full re-run).

### Tool changes behave like file changes (Tests I, J)
A tool whose output changes is detected at the point of invocation, via the same hash
comparison. No special-casing needed. Tool changes inside sub-agents propagate to the
parent level correctly (Test J).

### Where replay does not help
System prompt changes (Test H) and early-step divergences (Tests G, I, J in their current
form) show speedup ~1×. Replay is still correct — no false negatives — but saves nothing.
The report explicitly shows these cases to set accurate expectations.

## Pass Criteria

| Test | Correctness check | Result |
|------|------------------|--------|
| E | All 6 steps cache-hit | ✓ |
| F | Steps 0–4 cache-hit; step 5 DIVERGED; go-live produces correct answer | ✓ |
| G | Step 0 DIVERGED (guide changed); go-live applies updated rules | ✓ |
| H | "System prompt changed" reported; no cache-hit steps; full re-run | ✓ |
| I | Diverge at shell-script step; go-live reports updated line-stats format | ✓ |
| J | Step 0 (ExplorerAgent) `cache hit`; step 1 (script) `DIVERGED`; go-live produces updated answer | ✓ |
```

---

## 10. Pass/Fail Criteria

### Correctness (hard pass/fail)

| Test | Check |
|------|-------|
| E | All steps show `cache hit`; replay output semantically matches record |
| F | Steps 0–4 `cache hit`; step 5 `DIVERGED`; agent produces a valid final answer |
| G | Step 0 `DIVERGED`; go-live answer mentions findings from the updated guide |
| H | Output contains `System prompt changed`; zero `cache hit` lines in output |
| I | The script-call step `DIVERGED`; go-live answer reflects the new output format |
| J | ExplorerAgent step `DIVERGED`; output contains `sub-agent diverged`; both tasks in final answer |

### Performance (informational — warnings, not failures)

| Test | Expected speedup |
|------|-----------------|
| E | > 10× |
| F | > 2× |
| G | 0.8–1.5× |
| H | 0.8–1.2× |
| I | 0.8–1.5× |
| J | 0.8–1.5× |

Speedup outside these ranges is flagged in the report as a warning. Model API latency
varies ±20% per run; single-measurement results are directionally correct, not precise
benchmarks.

---

## 11. Known Limitations

**AGENTS.md injection**: Test H depends on AGENTS.md being injected into the system prompt.
This is documented in CLAUDE.md. If the project already has an AGENTS.md, the test appends
and restores; if not, it creates and removes. Either way, the presence/absence of AGENTS.md
affects the system prompt hash, which is the mechanism being tested.

**Tool-step non-determinism**: Tests I and J rely on the agent calling the shell script via
ShellTool. If the model decides to answer without calling the tool (possible if the prompt is
not directive enough), the test will record 0 steps and replay will be trivially all-cache-hit.
The prompt is written to be directive (`Run the following PowerShell command`) to minimize this.

**Test J ExplorerAgent behavior**: ExplorerAgent is expected to read files in `src/replay/`
using its natural tools (listDirectory, fileBatchRead). If it answers without tool calls, the
sub-trace will be empty and replay will trivially cache-hit. The prompt is directive enough
that this is unlikely, but it is not guaranteed.

**Single measurement per phase**: each T_record, T_replay, T_fresh is measured once. For
production benchmarking, 3-run median would be more reliable. One run is sufficient here for
directional validation and developer feedback.
