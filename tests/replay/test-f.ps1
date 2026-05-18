# Test F: Late-stage file change — partial cache with late divergence.
# Records a 4-file analysis, modifies the LAST file (trace_store.cj),
# then replays. First 3 steps should cache-hit; step 3 should DIVERGED.
# Run from project root: .\tests\replay\test-f.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"
$traceName     = "perf-test-f"
$mutatedFile   = "src\replay\trace_store.cj"
$sentinelLine  = "// PERF-TEST-F-SENTINEL"
$resultDir     = ".magic-cli\perf-results"
$resultFile    = "$resultDir\test-f.json"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

Write-Host "=== Test F: Late-Stage File Change — Partial Cache ===" -ForegroundColor Cyan
Write-Host "Scenario : record 4-file analysis, modify the last file (trace_store.cj), replay."
Write-Host "Expected : first N-1 steps cache-hit, last step DIVERGED, go-live produces answer."
Write-Host ""

# Pre-test restore: undo any leftover mutation from a previously interrupted run.
git checkout -- $mutatedFile 2>$null
$originalMutated = [System.IO.File]::ReadAllText((Resolve-Path $mutatedFile).Path)

try {
    # ── Phase 1: Baseline record (no mutation) ────────────────────────────────
    Write-Host "[1/3] Phase 1 — Record (baseline)..." -ForegroundColor Yellow
    $t_record = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode record --trace-name $traceName --prompt-file tests\replay\prompt-e.txt" 2>&1 | Out-Null
    }).TotalSeconds
    if (-not $?) { Write-Host "FAIL: record phase exited with error." -ForegroundColor Red; exit 1 }
    Write-Host "  T_record = $([math]::Round($t_record, 1))s" -ForegroundColor Gray

    # ── Apply mutation ────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  Mutating: appending sentinel to $mutatedFile ..."
    Add-Content -Path $mutatedFile -Value $sentinelLine

    # ── Phase 2: Replay after mutation ───────────────────────────────────────
    Write-Host ""
    Write-Host "[2/3] Phase 2 — Replay (after mutation)..." -ForegroundColor Yellow
    $replayOutput = @()
    $t_replay = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode replay --trace-name $traceName" 2>&1 |
            Tee-Object -Variable replayOutput
    }).TotalSeconds
    Write-Host ""
    Write-Host "  T_replay = $([math]::Round($t_replay, 1))s" -ForegroundColor Gray

    # ── Phase 3: Fresh run on mutated environment ─────────────────────────────
    Write-Host ""
    Write-Host "[3/3] Phase 3 — Fresh run (mutated env, no caching)..." -ForegroundColor Yellow
    $t_fresh = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode record --trace-name perf-fresh-f --prompt-file tests\replay\prompt-e.txt" 2>&1 | Out-Null
    }).TotalSeconds
    Write-Host "  T_fresh  = $([math]::Round($t_fresh, 1))s" -ForegroundColor Gray

    # ── Parse & evaluate ──────────────────────────────────────────────────────
    $replayStr  = $replayOutput -join "`n"
    $cacheHits  = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+: cache hit" }).Count
    $totalSteps = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+:" }).Count
    $hasDiverge = $replayStr -match "\[replay\] step \d+: DIVERGED"
    $hasGoLive  = $replayStr -match "\[replay\] (Going live|go-live step)"
    $speedup    = if ($t_replay -gt 0) { [math]::Round($t_fresh / $t_replay, 1) } else { 999 }
    # Pass: at least 1 cache-hit, at least 1 divergence, and go-live ran
    $passed     = ($cacheHits -ge 1) -and $hasDiverge -and $hasGoLive

    Write-Host ""
    Write-Host "--- Summary ---" -ForegroundColor Cyan
    Write-Host "  Steps  : $totalSteps total | $cacheHits cache-hit | $($totalSteps - $cacheHits) live"
    Write-Host "  Times  : record=$([math]::Round($t_record,1))s  replay=$([math]::Round($t_replay,1))s  fresh=$([math]::Round($t_fresh,1))s"
    Write-Host "  Speedup: ${speedup}x"
    if ($passed) {
        Write-Host "  PASS: partial cache-hit + late divergence detected + go-live triggered." -ForegroundColor Green
    } else {
        Write-Host "  FAIL: expected >= 1 cache-hit and DIVERGED. Got cacheHits=$cacheHits diverged=$hasDiverge goLive=$hasGoLive" -ForegroundColor Red
    }

    @{
        test        = "F"
        scenario    = "Late-stage file change (trace_store.cj)"
        t_record_s  = [math]::Round($t_record, 1)
        t_replay_s  = [math]::Round($t_replay, 1)
        t_fresh_s   = [math]::Round($t_fresh, 1)
        cache_hits  = $cacheHits
        total_steps = $totalSteps
        live_steps  = $totalSteps - $cacheHits
        diverge_at  = "last step (trace_store.cj)"
        speedup     = $speedup
        passed      = $passed
        replay_output = $replayStr
        timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $resultFile -Encoding utf8
    Write-Host "  Saved  -> $resultFile" -ForegroundColor Gray
    if (-not $passed) { exit 1 }

} finally {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Resolve-Path $mutatedFile).Path, $originalMutated, $utf8NoBom)
}
