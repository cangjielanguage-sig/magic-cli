# Test E: No change — pure cache speedup.
# Records a 4-file analysis task, then replays immediately with no changes.
# All steps should cache-hit; T_replay should be a fraction of T_fresh.
# Run from project root: .\tests\replay\test-e.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"
$traceName   = "perf-test-e"
$resultDir   = ".magic-cli\perf-results"
$resultFile  = "$resultDir\test-e.json"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

Write-Host "=== Test E: No Change — Pure Cache Speedup ===" -ForegroundColor Cyan
Write-Host "Scenario : record a 4-file analysis, replay immediately with no changes."
Write-Host "Expected : all steps cache-hit; large speedup."
Write-Host ""

# ── Phase 1: Baseline record ──────────────────────────────────────────────────
Write-Host "[1/3] Phase 1 — Record (baseline, no mutation)..." -ForegroundColor Yellow
$recordOutput = @()
$t_record = (Measure-Command {
    cjpm run --name cli --run-args "--auto --mode record --trace-name $traceName --prompt-file tests\replay\prompt-e.txt" 2>&1 |
        Tee-Object -Variable recordOutput
}).TotalSeconds
if (-not $?) { Write-Host "FAIL: record phase exited with error." -ForegroundColor Red; exit 1 }
Write-Host ""
Write-Host "  T_record = $([math]::Round($t_record, 1))s" -ForegroundColor Gray

# ── Phase 2: Replay (no mutation) ─────────────────────────────────────────────
Write-Host ""
Write-Host "[2/3] Phase 2 — Replay (no changes applied)..." -ForegroundColor Yellow
$replayOutput = @()
$t_replay = (Measure-Command {
    cjpm run --name cli --run-args "--auto --mode replay --trace-name $traceName" 2>&1 |
        Tee-Object -Variable replayOutput
}).TotalSeconds
Write-Host ""
Write-Host "  T_replay = $([math]::Round($t_replay, 1))s" -ForegroundColor Gray

# ── Phase 3: Fresh run (same task, no replay, measures full cost) ─────────────
Write-Host ""
Write-Host "[3/3] Phase 3 — Fresh run (full task, no caching)..." -ForegroundColor Yellow
$t_fresh = (Measure-Command {
    cjpm run --name cli --run-args "--auto --mode record --trace-name perf-fresh-e --prompt-file tests\replay\prompt-e.txt" 2>&1 | Out-Null
}).TotalSeconds
Write-Host "  T_fresh  = $([math]::Round($t_fresh, 1))s" -ForegroundColor Gray

# ── Parse & evaluate ──────────────────────────────────────────────────────────
$replayStr  = $replayOutput -join "`n"
$cacheHits  = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+: cache hit" }).Count
$totalSteps = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+:" }).Count
$hasDiverge = $replayStr -match "\[replay\] step \d+: DIVERGED"
$speedup    = if ($t_replay -gt 0) { [math]::Round($t_fresh / $t_replay, 1) } else { 999 }
$passed     = ($totalSteps -ge 2) -and ($cacheHits -eq $totalSteps) -and (-not $hasDiverge)

Write-Host ""
Write-Host "--- Summary ---" -ForegroundColor Cyan
Write-Host "  Steps : $totalSteps total | $cacheHits cache-hit | $($totalSteps - $cacheHits) live"
Write-Host "  Times : record=$([math]::Round($t_record,1))s  replay=$([math]::Round($t_replay,1))s  fresh=$([math]::Round($t_fresh,1))s"
Write-Host "  Speedup: ${speedup}x"
if ($passed) {
    Write-Host "  PASS: all steps cache-hit as expected." -ForegroundColor Green
} else {
    Write-Host "  FAIL: expected all $totalSteps steps to cache-hit, got $cacheHits." -ForegroundColor Red
}

# ── Save JSON result ──────────────────────────────────────────────────────────
@{
    test        = "E"
    scenario    = "No change — pure cache"
    t_record_s  = [math]::Round($t_record, 1)
    t_replay_s  = [math]::Round($t_replay, 1)
    t_fresh_s   = [math]::Round($t_fresh, 1)
    cache_hits  = $cacheHits
    total_steps = $totalSteps
    live_steps  = $totalSteps - $cacheHits
    diverge_at  = "none"
    speedup     = $speedup
    passed      = $passed
    replay_output = $replayStr
    timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
} | ConvertTo-Json -Depth 5 | Set-Content -Path $resultFile -Encoding utf8
Write-Host "  Saved  -> $resultFile" -ForegroundColor Gray
if (-not $passed) { exit 1 }
