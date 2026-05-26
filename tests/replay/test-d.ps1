# Test D: Stage 2 sub-agent change detection.
#
# Records a task handled entirely by ExplorerAgent, then modifies a file the
# sub-agent would have read, then replays. Stage 2 recursively validates the
# sub-agent trace, so the replay reports DIVERGED despite the change being
# inside the sub-agent.
#
# Run from the project root: .\tests\replay\test-d.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"

$sentinelFile = "src\replay\replayer.cj"
$sentinelMarker = "// stage2-test-sentinel"

try {
    Write-Host "=== Test D: Stage 2 sub-agent change detection (ExplorerAgent) ===" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "[1/4] Recording (ExplorerAgent explores src/replay/)..."
    cjpm run --name cli --run-args "--auto --mode record --trace-name replay-test-d --prompt-file tests\replay\prompt-d.txt"
    if (-not $?) { exit 1 }

    Write-Host ""
    Write-Host "[2/4] Checking trace for sub-agent step with embedded sub-trace..."
    $traceContent = Get-Content ".magic-cli\traces\replay-test-d.json" -Raw
    if ($traceContent -match '"isSubAgentCall":\s*true') {
        Write-Host "  OK: trace contains at least one sub-agent step" -ForegroundColor Green
    } else {
        Write-Host "  WARN: no sub-agent step found -- agent may not have called ExplorerAgent" -ForegroundColor Yellow
        Write-Host "  Inspect .magic-cli\traces\replay-test-d.json and adjust the prompt if needed"
    }
    if ($traceContent -match '"subTrace"') {
        Write-Host "  OK: trace contains embedded sub-trace (Stage 2)" -ForegroundColor Green
    } else {
        Write-Host "  WARN: no subTrace field found -- Stage 2 recording may have failed" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "[3/4] Modifying a file ExplorerAgent would have read (replayer.cj)..."
    Add-Content -Path $sentinelFile -Value $sentinelMarker

    Write-Host ""
    Write-Host "[4/4] Replaying after change..."
    $replayOutput = cjpm run --name cli --run-args "--auto --mode replay --trace-name replay-test-d" 2>&1
    Write-Host $replayOutput

    Write-Host ""
    if ($replayOutput -match "DIVERGED|diverge") {
        Write-Host "PASS: Stage 2 detected divergence inside ExplorerAgent sub-trace." -ForegroundColor Green
    } else {
        Write-Host "FAIL: Expected divergence but replay reported cache-hit." -ForegroundColor Red
        Write-Host "      Check that the sub-trace was recorded (Stage 2) and that ExplorerAgent read replayer.cj."
        exit 1
    }
} finally {
    # Remove the sentinel line if it was added
    if (Test-Path $sentinelFile) {
        $lines = Get-Content $sentinelFile -Encoding utf8 | Where-Object { $_ -ne $sentinelMarker }
        Set-Content -Path $sentinelFile -Value $lines -Encoding utf8
    }
}
