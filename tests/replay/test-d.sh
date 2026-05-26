#!/usr/bin/env bash
# Test D: Stage 2 sub-agent change detection.
#
# Records a task handled entirely by ExplorerAgent, then modifies a file the
# sub-agent would have read, then replays. Stage 2 recursively validates the
# sub-agent trace, so the replay reports DIVERGED despite the change being
# inside the sub-agent.
#
# Run from the project root: bash tests/replay/test-d.sh
set -uo pipefail

export MAGIC_PATH="D:/projects/CangjieMagic"

SENTINEL_FILE="src/replay/replayer.cj"
SENTINEL_MARKER="// stage2-test-sentinel"

cleanup() {
    # Remove the sentinel line if it was added
    if grep -q "$SENTINEL_MARKER" "$SENTINEL_FILE" 2>/dev/null; then
        grep -v "$SENTINEL_MARKER" "$SENTINEL_FILE" > "${SENTINEL_FILE}.tmp" && mv "${SENTINEL_FILE}.tmp" "$SENTINEL_FILE"
    fi
}
trap cleanup EXIT

echo "=== Test D: Stage 2 sub-agent change detection (ExplorerAgent) ==="
echo ""

echo "[1/4] Recording (ExplorerAgent explores src/replay/)..."
cjpm run --name cli --run-args "--auto --mode record --trace-name replay-test-d --prompt-file tests/replay/prompt-d.txt"

echo ""
echo "[2/4] Checking trace for sub-agent step with embedded sub-trace..."
if grep -q '"isSubAgentCall": true' .magic-cli/traces/replay-test-d.json; then
    echo "  OK: trace contains at least one sub-agent step"
else
    echo "  WARN: no sub-agent step found -- agent may not have called ExplorerAgent"
    echo "  Inspect .magic-cli/traces/replay-test-d.json and adjust the prompt if needed"
fi
if grep -q '"subTrace"' .magic-cli/traces/replay-test-d.json; then
    echo "  OK: trace contains embedded sub-trace (Stage 2)"
else
    echo "  WARN: no subTrace field found -- Stage 2 recording may have failed"
fi

echo ""
echo "[3/4] Modifying a file ExplorerAgent would have read (replayer.cj)..."
echo "$SENTINEL_MARKER" >> "$SENTINEL_FILE"

echo ""
echo "[4/4] Replaying after change..."
REPLAY_OUTPUT=$(cjpm run --name cli --run-args "--auto --mode replay --trace-name replay-test-d" 2>&1)
echo "$REPLAY_OUTPUT"

echo ""
if echo "$REPLAY_OUTPUT" | grep -qi "DIVERGED\|diverge"; then
    echo "PASS: Stage 2 detected divergence inside ExplorerAgent sub-trace."
else
    echo "FAIL: Expected divergence but replay reported cache-hit."
    echo "      Check that the sub-trace was recorded (Stage 2) and that ExplorerAgent read replayer.cj."
    exit 1
fi
