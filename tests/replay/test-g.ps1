# Test G: Skill body change — single agent reads a skill file, skill updated.
# Records a code-review task that first fetches the skill definition, then reads
# recorder.cj. Modifies the skill body (adds a new rule). Replays: step 0 should
# DIVERGE (skill changed), go-live applies the updated rules.
# Run from project root: .\tests\replay\test-g.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"
$traceName    = "perf-test-g"
$skillFile    = "src\replay\skills\code-reviewer.md"
$newRule      = "4. Check for hardcoded string or numeric literals that should be named constants."
$resultDir    = ".magic-cli\perf-results"
$resultFile   = "$resultDir\test-g.json"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

Write-Host "=== Test G: Skill Body Change (Single Agent) ===" -ForegroundColor Cyan
Write-Host "Scenario : agent reads skill file then reviews code; skill body gains a new rule."
Write-Host "Expected : step 0 (skill read) DIVERGED; go-live applies updated rules."
Write-Host ""

$originalSkill = [System.IO.File]::ReadAllText((Resolve-Path $skillFile).Path)

try {
    # ── Phase 1: Record ───────────────────────────────────────────────────────
    Write-Host "[1/3] Phase 1 — Record (original skill)..." -ForegroundColor Yellow
    $t_record = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode record --trace-name $traceName --prompt-file tests\replay\prompt-g.txt" 2>&1 | Out-Null
    }).TotalSeconds
    if (-not $?) { Write-Host "FAIL: record phase exited with error." -ForegroundColor Red; exit 1 }
    Write-Host "  T_record = $([math]::Round($t_record, 1))s" -ForegroundColor Gray

    # ── Apply mutation ────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  Mutating: adding rule 4 to skill body..."
    Add-Content -Path $skillFile -Value $newRule

    # ── Phase 2: Replay ───────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[2/3] Phase 2 — Replay (skill body updated)..." -ForegroundColor Yellow
    $replayOutput = @()
    $t_replay = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode replay --trace-name $traceName" 2>&1 |
            Tee-Object -Variable replayOutput
    }).TotalSeconds
    Write-Host ""
    Write-Host "  T_replay = $([math]::Round($t_replay, 1))s" -ForegroundColor Gray

    # ── Phase 3: Fresh run ────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[3/3] Phase 3 — Fresh run (updated skill, no caching)..." -ForegroundColor Yellow
    $t_fresh = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode record --trace-name perf-fresh-g --prompt-file tests\replay\prompt-g.txt" 2>&1 | Out-Null
    }).TotalSeconds
    Write-Host "  T_fresh  = $([math]::Round($t_fresh, 1))s" -ForegroundColor Gray

    # ── Parse & evaluate ──────────────────────────────────────────────────────
    $replayStr  = $replayOutput -join "`n"
    $cacheHits  = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+: cache hit" }).Count
    $totalSteps = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+:" }).Count
    $hasDiverge = $replayStr -match "\[replay\] step \d+: DIVERGED"
    $hasGoLive  = $replayStr -match "\[replay\] (Going live|go-live step)"
    $speedup    = if ($t_replay -gt 0) { [math]::Round($t_fresh / $t_replay, 1) } else { 999 }
    $passed     = $hasDiverge -and $hasGoLive

    Write-Host ""
    Write-Host "--- Summary ---" -ForegroundColor Cyan
    Write-Host "  Steps  : $totalSteps total | $cacheHits cache-hit | $($totalSteps - $cacheHits) live"
    Write-Host "  Times  : record=$([math]::Round($t_record,1))s  replay=$([math]::Round($t_replay,1))s  fresh=$([math]::Round($t_fresh,1))s"
    Write-Host "  Speedup: ${speedup}x"
    if ($passed) {
        Write-Host "  PASS: skill body change detected (DIVERGED) and go-live triggered." -ForegroundColor Green
    } else {
        Write-Host "  FAIL: expected DIVERGED at skill read step. diverged=$hasDiverge goLive=$hasGoLive" -ForegroundColor Red
    }

    @{
        test        = "G"
        scenario    = "Skill body change (code-reviewer.md, new rule added)"
        t_record_s  = [math]::Round($t_record, 1)
        t_replay_s  = [math]::Round($t_replay, 1)
        t_fresh_s   = [math]::Round($t_fresh, 1)
        cache_hits  = $cacheHits
        total_steps = $totalSteps
        live_steps  = $totalSteps - $cacheHits
        diverge_at  = "step 0 (skill read)"
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
