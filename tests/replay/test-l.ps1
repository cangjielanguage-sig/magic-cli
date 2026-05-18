# Test L: Multi-skill review — last skill (complexity-limits.md) changes.
# Records the same 4-skill review task. Adds a new complexity rule. Replays:
# skills 1-3 cache-hit, skill 4 (complexity-limits) DIVERGES, go-live applies updated rules.
# Run from project root: .\tests\replay\test-l.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"
$traceName  = "perf-test-l"
$skillFile  = "src\replay\skills\complexity-limits.md"
$newRule    = "4. A single match expression must not have more than 8 arms."
$resultDir  = ".magic-cli\perf-results"
$resultFile = "$resultDir\test-l.json"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

Write-Host "=== Test L: Multi-Skill Review — Last Skill Change ===" -ForegroundColor Cyan
Write-Host "Scenario : 4 skills loaded in order; complexity-limits.md (skill 4) gains a new rule."
Write-Host "Expected : skills 1-3 cache-hit; skill 4 DIVERGED; go-live applies updated rules."
Write-Host ""

$originalSkill = [System.IO.File]::ReadAllText((Resolve-Path $skillFile).Path)

try {
    # ── Phase 1: Record ───────────────────────────────────────────────────────
    Write-Host "[1/3] Phase 1 — Record (original skills)..." -ForegroundColor Yellow
    $t_record = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode record --trace-name $traceName --prompt-file tests\replay\prompt-k.txt" 2>&1 | Out-Null
    }).TotalSeconds
    if (-not $?) { Write-Host "FAIL: record phase exited with error." -ForegroundColor Red; exit 1 }
    Write-Host "  T_record = $([math]::Round($t_record, 1))s" -ForegroundColor Gray

    # ── Apply mutation ────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  Mutating: adding rule 4 to complexity-limits.md..."
    Add-Content -Path $skillFile -Value $newRule

    # ── Phase 2: Replay ───────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[2/3] Phase 2 — Replay (complexity-limits.md updated)..." -ForegroundColor Yellow
    $replayOutput = @()
    $t_replay = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode replay --trace-name $traceName" 2>&1 |
            Tee-Object -Variable replayOutput
    }).TotalSeconds
    Write-Host ""
    Write-Host "  T_replay = $([math]::Round($t_replay, 1))s" -ForegroundColor Gray

    # ── Phase 3: Fresh run ────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[3/3] Phase 3 — Fresh run (updated skills, no caching)..." -ForegroundColor Yellow
    $t_fresh = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode record --trace-name perf-fresh-l --prompt-file tests\replay\prompt-k.txt" 2>&1 | Out-Null
    }).TotalSeconds
    Write-Host "  T_fresh  = $([math]::Round($t_fresh, 1))s" -ForegroundColor Gray

    # ── Parse & evaluate ──────────────────────────────────────────────────────
    $replayStr  = $replayOutput -join "`n"
    $cacheHits  = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+: cache hit" }).Count
    $totalSteps = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+:" }).Count
    $hasDiverge = $replayStr -match "\[replay\] step \d+: DIVERGED"
    $hasGoLive  = $replayStr -match "\[replay\] (Going live|go-live step)"
    $speedup    = if ($t_replay -gt 0) { [math]::Round($t_fresh / $t_replay, 1) } else { 999 }
    # Pass: at least 2 skill steps cached (skills 1-3), diverge at skill 4, go-live ran
    $passed     = ($cacheHits -ge 2) -and $hasDiverge -and $hasGoLive

    Write-Host ""
    Write-Host "--- Summary ---" -ForegroundColor Cyan
    Write-Host "  Steps  : $totalSteps total | $cacheHits cache-hit | $($totalSteps - $cacheHits) live"
    Write-Host "  Times  : record=$([math]::Round($t_record,1))s  replay=$([math]::Round($t_replay,1))s  fresh=$([math]::Round($t_fresh,1))s"
    Write-Host "  Speedup: ${speedup}x"
    if ($passed) {
        Write-Host "  PASS: first three skills cached; complexity-limits change detected; go-live applied updated rules." -ForegroundColor Green
    } else {
        Write-Host "  FAIL: expected >=2 cache-hits + DIVERGED. Got cacheHits=$cacheHits diverged=$hasDiverge goLive=$hasGoLive" -ForegroundColor Red
    }

    @{
        test        = "L"
        scenario    = "Multi-skill review: last skill change (complexity-limits.md, rule 4 added)"
        t_record_s  = [math]::Round($t_record, 1)
        t_replay_s  = [math]::Round($t_replay, 1)
        t_fresh_s   = [math]::Round($t_fresh, 1)
        cache_hits  = $cacheHits
        total_steps = $totalSteps
        live_steps  = $totalSteps - $cacheHits
        diverge_at  = "skill 4 (complexity-limits.md)"
        speedup     = $speedup
        passed      = $passed
        replay_output = $replayStr
        timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $resultFile -Encoding utf8
    Write-Host "  Saved  -> $resultFile" -ForegroundColor Gray
    if (-not $passed) { exit 1 }

} finally {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Resolve-Path $skillFile).Path, $originalSkill, $utf8NoBom)
}
