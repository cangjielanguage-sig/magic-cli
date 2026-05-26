# Test A: Record then replay immediately — all steps should cache-hit.
# Run from the project root: .\tests\replay\test-a.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"

Write-Host "=== Test A: Record then replay (expect all cache-hit) ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/2] Recording..."
cjpm run --name cli --run-args "--auto --mode record --trace-name replay-test --prompt-file tests\replay\prompt.txt"
if (-not $?) { exit 1 }

Write-Host ""
Write-Host "[2/2] Replaying immediately (nothing changed)..."
cjpm run --name cli --run-args "--auto --mode replay --trace-name replay-test"

Write-Host ""
Write-Host "PASS: if all steps above show 'cache hit' and no divergence was reported." -ForegroundColor Green
