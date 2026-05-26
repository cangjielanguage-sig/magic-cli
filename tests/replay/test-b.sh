#!/usr/bin/env bash
# Test B: Replay after adding a file — divergence should be reported at step 0.
# Prerequisite: run test-a.sh first to create the replay-test trace.
# Run from the project root: bash tests/replay/test-b.sh
set -uo pipefail

export MAGIC_PATH="D:/projects/CangjieMagic"

DUMMY="src/replay/dummy_test.cj"

cleanup() {
    rm -f "$DUMMY"
}
trap cleanup EXIT

echo "=== Test B: Replay after file change (expect divergence at step 0) ==="
echo ""

echo "[1/2] Adding dummy file to src/replay/..."
touch "$DUMMY"

echo ""
echo "[2/2] Replaying..."
cjpm run --name cli --run-args "--auto --mode replay --trace-name replay-test"

echo ""
echo "PASS: if step 0 (listDirectory) shows DIVERGED and the summary reports first divergence at step 0."
