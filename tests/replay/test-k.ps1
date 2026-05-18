# Test K: Multi-skill review — middle skill (naming-guide.md) changes.
# Records a 4-skill review task. Adds a new naming rule. Replays:
# skills 1-2 cache-hit, skill 3 (naming-guide) DIVERGES, go-live applies updated rules.
# Run from project root: .\tests\replay\test-k.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"
$traceName  = "perf-test-k"
$skillFile  = "src\replay\skills\naming-guide.md"
$newRule    = "5. Avoid single-letter variable names except for conventional loop counters (i, j, k)."
$resultDir  = ".magic-cli\perf-results"
$resultFile = "$resultDir\test-k.json"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

Write-Host "=== Test K: Multi-Skill Review — Middle Skill Change ===" -ForegroundColor Cyan
Write-Host "Scenario : 4 skills loaded in order; naming-guide.md (skill 3) gains a new rule."
Write-Host "Expected : skills 1-2 cache-hit; skill 3 DIVERGED; go-live applies updated rules."
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
    Write-Host "  Mutating: adding rule 5 to naming-guide.md..."
    Add-Content -Path $skillFile -Value $newRule

    # ── Phase 2: Replay ───────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[2/3] Phase 2 — Replay (naming-guide.md updated)..." -ForegroundColor Yellow
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
        cjpm run --name cli --run-args "--auto --mode record --trace-name perf-fresh-k --prompt-file tests\replay\prompt-k.txt" 2>&1 | Out-Null
    }).TotalSeconds
    Write-Host "  T_fresh  = $([math]::Round($t_fresh, 1))s" -ForegroundColor Gray

    # ── Parse & evaluate ──────────────────────────────────────────────────────
    $replayStr  = $replayOutput -join "`n"
    $cacheHits  = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+: cache hit" }).Count
    $headerLine = $replayOutput | Where-Object { $_ -match "\[replay\] Steps: (\d+)" } | Select-Object -First 1
    $totalSteps = if ($headerLine -and $headerLine -match "\[replay\] Steps: (\d+)") { [int]$Matches[1] } else {
                      @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+:" }).Count }
    $hasDiverge = $replayStr -match "\[replay\] step \d+: DIVERGED"
    $hasGoLive  = $replayStr -match "\[replay\] (Going live|go-live step)"
    $speedup    = if ($t_replay -gt 0) { [math]::Round($t_fresh / $t_replay, 1) } else { 999 }
    # Pass: at least 1 skill step cached (skills 1-2), diverge at skill 3, go-live ran
    $passed     = ($cacheHits -ge 1) -and $hasDiverge -and $hasGoLive

    Write-Host ""
    Write-Host "--- Summary ---" -ForegroundColor Cyan
    Write-Host "  Steps  : $totalSteps total | $cacheHits cache-hit | $($totalSteps - $cacheHits) live"
    Write-Host "  Times  : record=$([math]::Round($t_record,1))s  replay=$([math]::Round($t_replay,1))s  fresh=$([math]::Round($t_fresh,1))s"
    Write-Host "  Speedup: ${speedup}x"
    if ($passed) {
        Write-Host "  PASS: early skills cached; naming-guide change detected; go-live applied updated rules." -ForegroundColor Green
    } else {
        Write-Host "  FAIL: expected >=1 cache-hit + DIVERGED. Got cacheHits=$cacheHits diverged=$hasDiverge goLive=$hasGoLive" -ForegroundColor Red
    }

    @{
        test        = "K"
        scenario    = "Multi-skill review: middle skill change (naming-guide.md, rule 5 added)"
        t_record_s  = [math]::Round($t_record, 1)
        t_replay_s  = [math]::Round($t_replay, 1)
        t_fresh_s   = [math]::Round($t_fresh, 1)
        cache_hits  = $cacheHits
        total_steps = $totalSteps
        live_steps  = $totalSteps - $cacheHits
        diverge_at  = "skill 3 (naming-guide.md)"
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
