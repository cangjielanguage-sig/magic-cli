#!/usr/bin/env bash
# Test C: Record then replay a task that invokes ReviewerAgent.
#
# Verifies (Stage 2):
#   - Sub-agent steps are captured with isSubAgentCall=true and an embedded subTrace
#   - Regular tool steps before the sub-agent call replay as cache hits
#   - Sub-agent internal steps are recursively validated (not skipped)
#   - ReviewerAgent step reports cache hit when environment is unchanged
#   - Summary reports 'all N step(s) cache-hit'
#
# Run from the project root: bash tests/replay/test-c.sh
set -euo pipefail

export MAGIC_PATH="D:/projects/CangjieMagic"

echo "=== Test C: Sub-agent capture and replay (ReviewerAgent) ==="
echo ""

echo "[1/3] Recording (expects listDirectory + ReviewerAgent call)..."
cjpm run --name cli --run-args "--auto --mode record --trace-name replay-test-c --prompt-file tests/replay/prompt-c.txt"

echo ""
echo "[2/3] Checking trace for sub-agent step with embedded sub-trace..."
if grep -q '"isSubAgentCall": true' .magic-cli/traces/replay-test-c.json; then
    echo "  OK: trace contains at least one sub-agent step"
else
    echo "  WARN: no sub-agent step found in trace -- agent may not have called ReviewerAgent"
    echo "  Inspect .magic-cli/traces/replay-test-c.json and adjust the prompt if needed"
fi
if grep -q '"subTrace"' .magic-cli/traces/replay-test-c.json; then
    echo "  OK: trace contains embedded sub-trace (Stage 2)"
else
    echo "  WARN: no subTrace field found -- Stage 2 recording may have failed"
fi

echo ""
echo "[3/3] Replaying immediately..."
cjpm run --name cli --run-args "--auto --mode replay --trace-name replay-test-c"

echo ""
echo "PASS: if all steps show 'cache hit' (including ReviewerAgent, validated recursively)"
echo "      and summary reports 'all N step(s) cache-hit'."
