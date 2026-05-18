# Test J: Multi-agent + tool behavior change.
# Records: ExplorerAgent explores src/replay/ (step 0), then outer agent runs
# line-stats.ps1 (step 1). Modifies line-stats.ps1 to add byte counts.
# Replay: step 0 (ExplorerAgent) cache-hits; step 1 (shell) DIVERGES, go-live runs.
# Run from project root: .\tests\replay\test-j.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"
$traceName    = "perf-test-j"
$toolScript   = "tests\replay\tools\line-stats.ps1"
$resultDir    = ".magic-cli\perf-results"
$resultFile   = "$resultDir\test-j.json"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

Write-Host "=== Test J: Multi-Agent + Tool Change ===" -ForegroundColor Cyan
Write-Host "Scenario : ExplorerAgent caches (step 0); outer line-stats.ps1 call diverges (step 1)."
Write-Host "Expected : >= 1 cache-hit; DIVERGED at shell step; go-live produces updated output."
Write-Host ""

# Pre-test restore: undo any leftover mutation from a previously interrupted run.
git checkout -- $toolScript 2>$null
$originalScript = [System.IO.File]::ReadAllText((Resolve-Path $toolScript).Path)

try {
    # ── Phase 1: Record ───────────────────────────────────────────────────────
    Write-Host "[1/3] Phase 1 — Record (original line-stats.ps1)..." -ForegroundColor Yellow
    $t_record = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode record --trace-name $traceName --prompt-file tests\replay\prompt-j.txt" 2>&1 | Out-Null
    }).TotalSeconds
    if (-not $?) { Write-Host "FAIL: record phase exited with error." -ForegroundColor Red; exit 1 }
    Write-Host "  T_record = $([math]::Round($t_record, 1))s" -ForegroundColor Gray

    # ── Apply mutation ────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  Mutating: adding byte-count output to line-stats.ps1..."
    $mutatedScript = @'
# line-stats.ps1 — reports line count and byte count for each .cj file in src/replay/
Get-ChildItem src\replay\*.cj | ForEach-Object {
    $lines = (Get-Content $_.FullName).Count
    $bytes = (Get-Item $_.FullName).Length
    "$($_.Name): $lines lines, $bytes bytes"
} | Sort-Object
'@
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Resolve-Path $toolScript).Path, $mutatedScript, $utf8NoBom)

    # ── Phase 2: Replay ───────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[2/3] Phase 2 — Replay (line-stats.ps1 output changed)..." -ForegroundColor Yellow
    $replayOutput = @()
    $t_replay = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode replay --trace-name $traceName" 2>&1 |
            Tee-Object -Variable replayOutput
    }).TotalSeconds
    Write-Host ""
    Write-Host "  T_replay = $([math]::Round($t_replay, 1))s" -ForegroundColor Gray

    # ── Phase 3: Fresh run ────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[3/3] Phase 3 — Fresh run (mutated script, no caching)..." -ForegroundColor Yellow
    $t_fresh = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode record --trace-name perf-fresh-j --prompt-file tests\replay\prompt-j.txt" 2>&1 | Out-Null
    }).TotalSeconds
    Write-Host "  T_fresh  = $([math]::Round($t_fresh, 1))s" -ForegroundColor Gray

    # ── Parse & evaluate ──────────────────────────────────────────────────────
    $replayStr  = $replayOutput -join "`n"
    $cacheHits  = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+: cache hit" }).Count
    $totalSteps = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+:" }).Count
    $hasDiverge = $replayStr -match "\[replay\] step \d+: DIVERGED"
    $hasGoLive  = $replayStr -match "\[replay\] (Going live|go-live step)"
    $speedup    = if ($t_replay -gt 0) { [math]::Round($t_fresh / $t_replay, 1) } else { 999 }
    # Pass: sub-agent step cached (>=1), outer shell step diverged, go-live ran
    $passed     = ($cacheHits -ge 1) -and $hasDiverge -and $hasGoLive

    Write-Host ""
    Write-Host "--- Summary ---" -ForegroundColor Cyan
    Write-Host "  Steps  : $totalSteps total | $cacheHits cache-hit | $($totalSteps - $cacheHits) live"
    Write-Host "  Times  : record=$([math]::Round($t_record,1))s  replay=$([math]::Round($t_replay,1))s  fresh=$([math]::Round($t_fresh,1))s"
    Write-Host "  Speedup: ${speedup}x"
    if ($passed) {
        Write-Host "  PASS: sub-agent cached + tool output change detected + go-live triggered." -ForegroundColor Green
    } else {
        Write-Host "  FAIL: expected >=1 cache-hit and DIVERGED. Got cacheHits=$cacheHits diverged=$hasDiverge goLive=$hasGoLive" -ForegroundColor Red
    }

    @{
        test        = "J"
        scenario    = "Multi-agent + tool change (ExplorerAgent cache-hit, line-stats.ps1 diverges)"
        t_record_s  = [math]::Round($t_record, 1)
        t_replay_s  = [math]::Round($t_replay, 1)
        t_fresh_s   = [math]::Round($t_fresh, 1)
        cache_hits  = $cacheHits
        total_steps = $totalSteps
        live_steps  = $totalSteps - $cacheHits
        diverge_at  = "shell step (after ExplorerAgent cache-hit)"
        speedup     = $speedup
        passed      = $passed
        replay_output = $replayStr
        timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $resultFile -Encoding utf8
    Write-Host "  Saved  -> $resultFile" -ForegroundColor Gray
    if (-not $passed) { exit 1 }

} finally {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Resolve-Path $toolScript).Path, $originalScript, $utf8NoBom)
}
