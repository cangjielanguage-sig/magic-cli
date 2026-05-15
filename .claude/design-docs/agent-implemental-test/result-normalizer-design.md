# Tool Result Normalizer — Design

**Date**: 2026-05-15
**Status**: Implemented

---

## 1. Problem Statement

The replay system re-executes each recorded tool call and compares the result hash. A mismatch
means the trajectory would diverge. But not every hash mismatch reflects a real environment
change — some are caused by the replay mechanism itself.

The canonical example: Windows `dir` ends with `N Dir(s) X bytes free`. The trace file write
that happens during recording consumes some disk space, so every subsequent replay sees a
slightly different free-space count and reports DIVERGED — even though nothing in the
environment relevant to the agent changed.

---

## 2. The Two-Category Principle

All tool-result non-determinism falls into exactly one of two categories:

### Category 1 — Self-induced

The change happened *because the replay mechanism ran*, not because the external environment
changed.

**Justification for normalizing**: the replay infrastructure always performs the same writes
(trace file, log file). These writes are invisible to the agent's task — they do not represent
a real change the agent should reason about. Normalizing them does not risk false negatives:
even an agent that checks disk space would not care about a 10–100 KB trace write.

**Initial self-induced patterns for our replay mechanism:**
- Trace file: `.magic-cli/traces/<name>.json` written during record
- Log file: `.magic-cli/logs/<timestamp>.log` written on every run
- Readline history: `.magic-cli/readline.history` updated on every run

All three write to the same disk, so any tool that reports disk-level statistics will see a
different `bytes free` at replay time. This is the only currently confirmed self-induced
pattern.

### Category 2 — External

The change happened in the environment for a reason unrelated to the replay mechanism.

**Policy**: always report as DIVERGED. We cannot know without task context whether the change
is meaningful — that depends on what the agent was doing. Reporting divergence is always safe
(false positive at worst). Silently ignoring it is dangerous (false negative).

**Future work**: a "semantic equivalence" judge (see §6 and todo.md) can be invoked
interactively after a DIVERGED report to help the user decide whether the change actually
affects the agent's decision. This is a UX concern, not a detection concern.

---

## 3. What Counts as Self-Induced (current analysis)

For each pattern in our tool taxonomy, we ask: *is this change caused by the replay
mechanism's own file writes?*

### 3.1 Filesystem metadata

| Content | Tool | Self-induced? | Reason |
|---|---|---|---|
| `N Dir(s) X bytes free` | `listDirectory` (Windows `dir`) | **Yes** | Trace + log writes change disk free space |
| `N File(s) N bytes` (summary) | `listDirectory` (Windows `dir`) | No | Counts/sizes files *in the listed dir*; replay writes to `.magic-cli/`, not the listed dir |
| Total block count (`ls -l` header) | `listDirectory` (Linux) | **Maybe** | Depends on whether `.magic-cli/` is on same filesystem; conservative: no |
| Directory `.` modification timestamp | `listDirectory` | No | Replay writes to `.magic-cli/`, not the listed dir |
| Individual file timestamps / sizes | `listDirectory`, `ls -l` | No | These are real environment changes |

**Only the `N Dir(s) X bytes free` line is confirmed self-induced.**

### 3.2 Wall clock / elapsed time

| Content | Self-induced? | Reason |
|---|---|---|
| Elapsed time (`real Nm1.234s`) | No | Caused by real execution duration, not by replay writes |
| Current timestamp in build output | No | Real wall-clock time |
| Log timestamps in shell output | No | Real time |

These are **external** — they fluctuate due to system load and clock, not due to replay
writes. They are false positives if reported, but suppressing them risks false negatives
(a timing-sensitive agent task would correctly diverge if execution became slower).

### 3.3 System resource stats

| Content | Self-induced? | Reason |
|---|---|---|
| Disk free space | **Yes** (partially) | Replay writes cause a small known change |
| Memory usage | No | Not caused by replay writes |
| CPU load | No | Not caused by replay writes |

Note: disk free space is *partially* self-induced (replay writes contribute a small amount)
and *partially* external (other system activity contributes). Since we cannot separate the
two contributions, and the replay contribution is always present, the right policy is to
normalize the `bytes free` line and accept that genuinely external disk-space changes will
also be hidden. This is a known limitation: **an agent task that depends on large-scale disk
usage changes (e.g., "check if build artifacts grew beyond 10 GB") should not use
`listDirectory` as its sensor** — it should use a dedicated disk-usage tool whose output we
can reason about separately.

### 3.4 Process IDs, ports, elapsed time, version strings, ordering, etc.

None of these are caused by the replay mechanism's writes. They are all **external** sources
of non-determinism. Some are noise for many agent tasks (PIDs rarely matter), but since we
cannot know the task without context, they fall into Category 2 and are reported as DIVERGED.

---

## 4. Alternative Considered: Move Trace Files to a Different Filesystem

A cleaner fix in principle: if the trace and log files were written to a location on a
*different* filesystem (e.g., `/tmp` on a separate partition, or `C:\Temp` when the project
is on D:), their writes would not affect the `bytes free` count in any `listDirectory` call
on the project's filesystem.

**Why this is incomplete:**

1. **Log files have the same problem.** Every run writes a new `.magic-cli/logs/<timestamp>.log`.
   That log grows during execution, past the point where any `listDirectory` tool call runs.
   Moving only the trace file to temp leaves the log-file confound untouched.

2. **Single-partition systems.** On a typical Linux machine with one filesystem, `/tmp` is on
   the same partition as the project directory. Moving files there changes nothing.

3. **Temp files are not durable.** Traces stored in `/tmp` are deleted on reboot, making
   them unsuitable as persistent recording artifacts. Users expect traces near the project.

4. **Moving both traces and logs to temp** would solve the problem on multi-drive setups
   (e.g., project on D:, temp on C:) but violates the UX expectation that CLI state lives
   under `.magic-cli/` in the working directory, and is fragile across system configurations.

**Conclusion:** the instinct to fix the root cause rather than normalize around the symptom
is correct. But the root cause is "the CLI always writes to the same filesystem the agent
queries" — which is inherent to the project-local design. Normalization is more robust across
all filesystem layouts, and its scope is intentionally narrow (only the `bytes free` line).

---

## 5. Normalization Rules (initial — Category 1 only)

Only patterns confirmed self-induced receive normalization rules. Everything else is reported
as DIVERGED and left to Category 2 handling.

### 5.1 Rule set

| Rule ID | Scope | Pattern | Action | Justification |
|---|---|---|---|---|
| `SI-1` | Global | Lines containing `"bytes free"` | Strip line | Windows `dir` disk-free stat; self-induced by trace/log writes |
| `SI-2` | Global | Lines matching `^\s*\d+\s+Dir\(s\)` | Strip line | Windows `dir` directory count in disk summary; same line as SI-1 (belt-and-suspenders) |

**Intentionally excluded** (Category 2, not self-induced):
- Elapsed time lines — could matter for timing-sensitive tasks
- PIDs, ports — could matter for process-management tasks
- File(s) summary line — counts files in the listed directory, not a replay artifact
- All other patterns from the taxonomy

### 5.2 Where applied

Normalization is hash-only. The raw result is stored unchanged in `ToolStepRecord.toolResult`
for debugging.

```
Record:  computeHash(normalize(toolName, obsContent))  → stored in toolResultHash
Replay:  computeHash(normalize(toolName, actualResult)) → compared with toolResultHash
```

Two call sites, both normalize before hashing:
- `Recorder.buildRecord`: `computeHash(normalize(toolName, rawResult))` — where `rawResult` is obtained by re-invoking the tool directly (not from `ChatRound.steps`, which may store a compacted LLM summary). See `architecture.md §6` for the compaction issue.
- `Replayer.validateStep`: `computeHash(normalize(step.toolName, actualResult))` — `actualResult` is from `tool.invoke(args).content`, always the full raw result.

---

## 6. Implementation

### 6.1 Module: `src/replay/result_normalizer.cj`

```cangjie
public class ToolResultNormalizer {
    // Apply self-induced normalization rules and return the stable form for hashing.
    // Only Category-1 (self-induced) patterns are stripped — everything else is preserved
    // so that genuine environment changes are detected.
    public static func normalize(toolName: String, result: String): String
}
```

Phase 1 (this iteration): strip SI-1 and SI-2 lines.
Phase 2 (future): if new self-induced patterns are confirmed, add rules here.

### 6.2 Adding a new rule

Criteria for a new normalization rule:
1. The pattern **must** be present in the output because the replay mechanism ran (not just
   "usually" present, and not "sometimes irrelevant").
2. The pattern **must** vary between record and replay even when no external environment
   change occurred.
3. The pattern **cannot** be the only signal for a plausible agent task.

If all three hold, add the rule. If criterion 3 is uncertain, do not add the rule — accept
the false positive and let the semantic equivalence mechanism handle it.

---

## 7. Future Work: Semantic Equivalence (Category 2)

Category 2 changes are reported as DIVERGED. Many of them will be true positives (something
really changed). Some will be false positives (disk timing, CPU jitter, etc. caused a
difference that the agent would not have cared about).

The right mechanism for handling Category 2 false positives is a **task-context semantic
judge** — see §[MEDIUM] in `todo.md` for the full specification. In summary:

> When DIVERGED is reported, the user (or an optional automated step) can invoke a judge with:
> - The original task prompt
> - The tool name and arguments
> - The recorded result and the actual result
>
> The judge answers: would the agent's subsequent reasoning have been the same?
>
> A small LLM (Haiku) at temperature=0, given this context, can make a much better
> noise-vs-signal judgment than any static rule — precisely because it has the task context
> that static rules lack.
>
> This is a UX / confirmation feature, not part of the core detection pipeline. Reporting
> DIVERGED is always safe.
