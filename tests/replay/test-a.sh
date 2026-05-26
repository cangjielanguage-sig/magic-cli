#!/usr/bin/env bash
# Test A: Record then replay immediately — all steps should cache-hit.
# Run from the project root: bash tests/replay/test-a.sh
set -euo pipefail

export MAGIC_PATH="D:/projects/CangjieMagic"

echo "=== Test A: Record then replay (expect all cache-hit) ==="
echo ""

echo "[1/2] Recording..."
cjpm run --name cli --run-args "--auto --mode record --trace-name replay-test --prompt-file tests/replay/prompt.txt"

echo ""
echo "[2/2] Replaying immediately (nothing changed)..."
cjpm run --name cli --run-args "--auto --mode replay --trace-name replay-test"

echo ""
echo "PASS: if all steps above show 'cache hit' and no divergence was reported."
