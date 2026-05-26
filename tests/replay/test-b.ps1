# Test B: Replay after adding a file — divergence should be reported at step 0.
# Prerequisite: run test-a.ps1 first to create the replay-test trace.
# Run from the project root: .\tests\replay\test-b.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"

$dummy = "src\replay\dummy_test.cj"

try {
    Write-Host "=== Test B: Replay after file change (expect divergence at step 0) ===" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "[1/2] Adding dummy file to src\replay\..."
    New-Item -Path $dummy -ItemType File -Force | Out-Null

    Write-Host ""
    Write-Host "[2/2] Replaying..."
    cjpm run --name cli --run-args "--auto --mode replay --trace-name replay-test"

    Write-Host ""
    Write-Host "PASS: if step 0 (listDirectory) shows DIVERGED and step 1 (fileBatchRead) shows cache hit." -ForegroundColor Green
} finally {
    if (Test-Path $dummy) {
        Remove-Item $dummy -Force
    }
}
