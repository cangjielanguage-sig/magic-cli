# Review Analysis & Applied Fixes: feature/agent-replay

**Date**: 2026-05-14
**Based on review**: `.claude/reviews/feature-agent-replay-review.md`

---

## Analysis: Where the Review Was Right / Wrong

### A-1: `model_output` not stored — "go live" impossible
**Review said**: CRITICAL
**Actual severity**: HIGH

The dry-run validator is still genuinely useful as an MVP — it tells you which step diverged so you can manually re-run from there. The feature is not broken, it's incomplete. The real problem was that no comment or doc flagged this as a known limitation. The class was named `Replayer` but only validated.

### B-1/C-2: Path traversal via `--trace-name`
**Review said**: CRITICAL / HIGH
**Actual severity**: MEDIUM

Path traversal is serious for web servers with untrusted remote input. This is a local developer CLI where the user controls all arguments. A user passing `--trace-name ../settings` is self-inflicting. Still worth fixing, but not the same risk class as a server-side vulnerability.

### B-2: Replay re-executes destructive tools
**Review said**: HIGH (framed as a bug)
**Actual assessment**: By design, not a bug

Re-executing side-effecting tools (write, shell, git) during replay is explicitly intentional per design.md §5: "We always re-execute the tool call, even on cache hits. This is intentional — it recreates side effects in the clean environment." The design requires an environment reset before each replay run (§7). The real issue was the lack of a warning telling users this. The reviewer misread a feature as a bug.

### A-2: SHA-256 not used
**Review said**: HIGH
**Actual severity**: LOW

The architecture doc says "SHA-256 if available, otherwise fall back to CRC-32 or raw for MVP." The dual-polynomial hash is a perfectly reasonable MVP fallback for *change detection* — not cryptography. ~60-bit effective space is adequate. Needs a comment, not a rewrite.

### B-3: Double-read of `response.content`
**Review said**: HIGH
**Actual severity**: LOW/MEDIUM (likely a false alarm)

The existing CLI already reads `AsyncAgentResponse.content` multiple times via `PrintUtils.printAgentResponse`. If the value weren't cached after first evaluation, the existing non-replay code would already be broken. Probably safe, but worth a comment.

### A-3: Sub-agent steps — misleading `allCached`
**Review said**: HIGH (framed as "completely silent")
**Actual assessment**: Partially correct

The current output DOES print `skipped (ExplorerAgent) — sub-agent — skipped to avoid model calls` per step, so it is NOT silent at the step level. The real bug is narrower: the summary line says "all N step(s) cache-hit" even when some steps were skipped, and the `allCached` property returns `true` in that case. Medium-severity, easy fix.

### B-5: `extractTagContent` truncates on embedded close tags
**Review said**: MEDIUM
**Actual assessment**: MEDIUM, but more likely to trigger than the review implied

Shell and file-read tools commonly return HTML, XML, markdown with embedded tag strings. A `ReadFile` on any web template would hit this. Using `lastIndexOf` (implemented as a forward scan loop) is a one-line conceptual fix.

---

## Fixes Applied (commit-ready)

### Applied immediately

| Finding | Severity | File | What was done |
|---|---|---|---|
| A-1 | HIGH | `src/replay/replayer.cj` | Updated class comment: "Dry-run validator (Stage 1 only). Does NOT resume live model calls. See todo.md HIGH priority item." |
| A-1 | HIGH | `src/replay/replay_runner.cj` | Updated method comment: clarifies side effects are re-executed, clean env required |
| A-1 | HIGH | `design-docs/agent-implemental-test/todo.md` | Added **[HIGH] Go Live from Divergence** entry with full implementation sketch (add `modelOutput` field, `Replayer.replayLive`, verify `asyncChat(conversation:)` supports pre-built history) |
| A-3 | MEDIUM | `src/replay/replay_runner.cj` | Count skipped steps; summary now says *"X sub-agent step(s) skipped (sub-agent changes not detected)"* instead of false "all cached" |
| B-5 | MEDIUM | `src/replay/trace.cj` | `extractTagContent` now scans for the **last** close tag occurrence via forward loop, preventing truncation when tool results contain XML/HTML |
| D-5 | LOW | `src/replay/trace_store.cj` | Removed unused `remove` import |
| D-2 | LOW | `src/core/config/cli_config.cj` | Added `replayMode` and `traceName` to debug `toString()` output (using match to convert enum to string) |

Build verified: `cjpm build success` after all changes.

---

## Not Fixed — Deferred / Won't Fix

| Finding | Reason |
|---|---|
| A-1 "go live" implementation | Significant work; documented in todo.md as HIGH priority for next iteration |
| B-1 Path traversal | Medium risk for local CLI; acceptable for MVP, track as future hardening |
| B-2 Destructive tool replay | Not a bug — by design per design.md §5; warning added in comment |
| A-2 SHA-256 | Low risk for change detection use case; needs a comment (not done yet) |
| B-3 Double content read | Likely safe given existing code patterns; needs verification against `AsyncAgentResponse` impl |
| A-3 sub-agent Stage 2 | Full nested trace recording is Stage 2 scope; summary warning is sufficient for now |
| A-4 `.json.bak` rotation | Nice-to-have; deferred |
| A-5 `Replayer` naming | Addressed via comment update; renaming deferred |
| B-4 Orphaned action warning | Easy fix, not yet done |
| B-6 Version validation on load | Easy fix, not yet done |
| B-7 `firstDivergenceIndex: Some(0)` inconsistency | Low impact, not yet done |
| D-1 `ReplayMode.None` naming | Low risk in practice, deferred |
| D-3 `--mode replay` not setting `nonInteractive` | No practical impact given dispatch structure in `main.cj` |
| D-4 `tool_replayer.cj` absent | Acceptable consolidation for Stage 1 |

---

## Remaining Easy Fixes (next session candidates)

These are all one-liners or near-trivial:

- **B-4**: After the recorder loop, `if (let Some(_) <- pendingAction) { LogUtils.warn("[record] Orphaned <action> at end of chatRound — step dropped") }`
- **B-6**: In `AgentTrace.fromJsonValue`, check `version != "1"` and throw or warn
- **A-2**: Add comment to `computeHash` explaining the SHA-256 deferral
- **B-1**: In `TraceStore.tracePath`, reject names containing `..`, `/`, `\`
- **D-1**: Rename `ReplayMode.None` → `ReplayMode.Off`
