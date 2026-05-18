# Test H: System prompt change via AGENTS.md.
# Records a 4-file analysis with the current AGENTS.md. Appends a sentinel line
# to AGENTS.md (changing the system prompt hash). Replays: system prompt mismatch
# detected immediately, full re-run forced, zero cache-hits.
# Run from project root: .\tests\replay\test-h.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"
$traceName     = "perf-test-h"
$agentsMd      = "AGENTS.md"
$sentinelLine  = "<!-- PERF-TEST-H-SENTINEL: replay system prompt change test -->"
$resultDir     = ".magic-cli\perf-results"
$resultFile    = "$resultDir\test-h.json"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

Write-Host "=== Test H: System Prompt Change via AGENTS.md ===" -ForegroundColor Cyan
Write-Host "Scenario : record task with current AGENTS.md; append sentinel line; replay."
Write-Host "Expected : 'System prompt changed' reported; zero cache-hits; full re-run."
Write-Host ""

$originalAgentsMd = [System.IO.File]::ReadAllText((Resolve-Path $agentsMd).Path)

try {
    # ── Phase 1: Record with current AGENTS.md ────────────────────────────────
    Write-Host "[1/3] Phase 1 — Record (current AGENTS.md)..." -ForegroundColor Yellow
    $t_record = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode record --trace-name $traceName --prompt-file tests\replay\prompt-e.txt" 2>&1 | Out-Null
    }).TotalSeconds
    if (-not $?) { Write-Host "FAIL: record phase exited with error." -ForegroundColor Red; exit 1 }
    Write-Host "  T_record = $([math]::Round($t_record, 1))s" -ForegroundColor Gray

    # ── Apply mutation ────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  Mutating: appending sentinel line to AGENTS.md..."
    Add-Content -Path $agentsMd -Value "`n$sentinelLine"

    # ── Phase 2: Replay ───────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[2/3] Phase 2 — Replay (AGENTS.md changed)..." -ForegroundColor Yellow
    $replayOutput = @()
    $t_replay = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode replay --trace-name $traceName" 2>&1 |
            Tee-Object -Variable replayOutput
    }).TotalSeconds
    Write-Host ""
    Write-Host "  T_replay = $([math]::Round($t_replay, 1))s" -ForegroundColor Gray

    # ── Phase 3: Fresh run ────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[3/3] Phase 3 — Fresh run (changed AGENTS.md, no caching)..." -ForegroundColor Yellow
    $t_fresh = (Measure-Command {
        cjpm run --name cli --run-args "--auto --mode record --trace-name perf-fresh-h --prompt-file tests\replay\prompt-e.txt" 2>&1 | Out-Null
    }).TotalSeconds
    Write-Host "  T_fresh  = $([math]::Round($t_fresh, 1))s" -ForegroundColor Gray

    # ── Parse & evaluate ──────────────────────────────────────────────────────
    $replayStr       = $replayOutput -join "`n"
    $cacheHits       = @($replayOutput | Where-Object { $_ -match "\[replay\] step \d+: cache hit" }).Count
    # System prompt change bypasses the step loop entirely, so count from the trace header instead.
    $headerLine  = $replayOutput | Where-Object { $_ -match "\[replay\] Steps: (\d+)" } | Select-Object -First 1
    $totalSteps  = if ($headerLine -and $headerLine -match "\[replay\] Steps: (\d+)") { [int]$Matches[1] } else { 0 }
    $sysPromptChange = $replayStr -match "System prompt changed"
    $speedup         = if ($t_replay -gt 0) { [math]::Round($t_fresh / $t_replay, 1) } else { 999 }
    $passed          = $sysPromptChange -and ($cacheHits -eq 0)

    Write-Host ""
    Write-Host "--- Summary ---" -ForegroundColor Cyan
    Write-Host "  System prompt changed detected: $sysPromptChange"
    Write-Host "  Steps  : $totalSteps total | $cacheHits cache-hit (expected 0)"
    Write-Host "  Times  : record=$([math]::Round($t_record,1))s  replay=$([math]::Round($t_replay,1))s  fresh=$([math]::Round($t_fresh,1))s"
    Write-Host "  Speedup: ${speedup}x (expected ~1x — no caching possible)"
    if ($passed) {
        Write-Host "  PASS: system prompt change detected; no cache-hits; full re-run." -ForegroundColor Green
    } else {
        Write-Host "  FAIL: expected 'System prompt changed' + 0 cache-hits. Got sysPromptChange=$sysPromptChange cacheHits=$cacheHits" -ForegroundColor Red
    }

    @{
        test        = "H"
        scenario    = "System prompt change (AGENTS.md sentinel appended)"
        t_record_s  = [math]::Round($t_record, 1)
        t_replay_s  = [math]::Round($t_replay, 1)
        t_fresh_s   = [math]::Round($t_fresh, 1)
        cache_hits  = $cacheHits
        total_steps = $totalSteps
        live_steps  = $totalSteps - $cacheHits
        diverge_at  = "system prompt (step 0)"
        speedup     = $speedup
        passed      = $passed
        replay_output = $replayStr
        timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $resultFile -Encoding utf8
    Write-Host "  Saved  -> $resultFile" -ForegroundColor Gray
    if (-not $passed) { exit 1 }

} finally {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Resolve-Path $agentsMd).Path, $originalAgentsMd, $utf8NoBom)
}
