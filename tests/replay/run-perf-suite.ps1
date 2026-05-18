# run-perf-suite.ps1 — Runs performance tests E through J sequentially and
# generates a Markdown report from per-test JSON results.
# Run from project root: .\tests\replay\run-perf-suite.ps1

$resultDir   = ".magic-cli\perf-results"
$timestamp   = (Get-Date -Format "yyyyMMdd-HHmmss")
$reportFile  = "tests\replay\perf-report-$timestamp.md"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

$tests = @(
    @{ id = "E"; script = "tests\replay\test-e.ps1"; title = "No Change — Pure Cache Speedup" }
    @{ id = "F"; script = "tests\replay\test-f.ps1"; title = "Late-Stage File Change" }
    @{ id = "G"; script = "tests\replay\test-g.ps1"; title = "Skill Body Change" }
    @{ id = "H"; script = "tests\replay\test-h.ps1"; title = "System Prompt Change (AGENTS.md)" }
    @{ id = "I"; script = "tests\replay\test-i.ps1"; title = "Tool Behavior Change" }
    @{ id = "J"; script = "tests\replay\test-j.ps1"; title = "Multi-Agent + Tool Change" }
    @{ id = "K"; script = "tests\replay\test-k.ps1"; title = "Multi-Skill: Middle Skill Change" }
    @{ id = "L"; script = "tests\replay\test-l.ps1"; title = "Multi-Skill: Last Skill Change" }
)

$suiteResults = @()

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       Magic CLI Replay Performance Test Suite        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  Running tests E–J. Each test takes several minutes." -ForegroundColor Gray
Write-Host "  Report will be saved to: $reportFile" -ForegroundColor Gray
Write-Host ""

foreach ($t in $tests) {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "  Running Test $($t.id): $($t.title)" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host ""

    $exitCode = 0
    & powershell.exe -NonInteractive -File $t.script
    $exitCode = $LASTEXITCODE

    $resultPath = "$resultDir\test-$($t.id.ToLower()).json"
    if (Test-Path $resultPath) {
        $data = Get-Content $resultPath -Raw -Encoding utf8 | ConvertFrom-Json
        $suiteResults += $data
        $status = if ($data.passed) { "PASS" } else { "FAIL" }
        Write-Host ""
        Write-Host "  Test $($t.id) → $status" -ForegroundColor (if ($data.passed) { "Green" } else { "Red" })
    } else {
        Write-Host "  Test $($t.id) → FAIL (no result file written)" -ForegroundColor Red
        $suiteResults += @{
            test = $t.id; scenario = $t.title
            t_record_s = 0; t_replay_s = 0; t_fresh_s = 0
            cache_hits = 0; total_steps = 0; live_steps = 0
            diverge_at = "N/A"; speedup = 0; passed = $false
            replay_output = "Script failed or did not produce output."
            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        }
    }

    if ($exitCode -ne 0) {
        Write-Host ""
        Write-Host "  !! Test $($t.id) failed (exit code $exitCode)." -ForegroundColor Red
        Write-Host "  !! Stopping suite. Fix the issue and re-run." -ForegroundColor Red
        Write-Host ""
        # Generate partial report before exiting
        & $PSCommandPath -GenerateReportOnly -Results $suiteResults -ReportFile $reportFile 2>$null
        Write-Host "  Partial report saved to: $reportFile" -ForegroundColor Yellow
        exit 1
    }

    Write-Host ""
}

# ── Generate Markdown report ──────────────────────────────────────────────────

$passCount = ($suiteResults | Where-Object { $_.passed }).Count
$failCount = ($suiteResults | Where-Object { -not $_.passed }).Count
$overallStatus = if ($failCount -eq 0) { "ALL PASS" } else { "$failCount FAILED" }

$md = @"
# Magic CLI Replay — Performance Test Report

**Generated**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Suite**: Tests E–J (6 scenarios)
**Overall**: $overallStatus ($passCount passed, $failCount failed)

---

## Summary Table

| Test | Scenario | T_record | T_replay | T_fresh | Speedup | Cache Hits | Total Steps | Diverge At | Result |
|------|----------|----------|----------|---------|---------|------------|-------------|------------|--------|
"@

foreach ($r in $suiteResults) {
    $status  = if ($r.passed) { "✅ PASS" } else { "❌ FAIL" }
    $speedup = if ($r.speedup -eq 999) { "∞" } else { "$($r.speedup)x" }
    $md += "| $($r.test) | $($r.scenario) | $($r.t_record_s)s | $($r.t_replay_s)s | $($r.t_fresh_s)s | $speedup | $($r.cache_hits) | $($r.total_steps) | $($r.diverge_at) | $status |`n"
}

$md += @"

---

## Test Descriptions and Expected Behavior

| Test | Change Type | Expected Cache Hits | Expected Divergence |
|------|-------------|--------------------|--------------------|
| E | None (baseline) | All steps | None |
| F | File change (last file) | N-1 steps | Last step |
| G | Skill body change | 0 (diverges at skill read) | Step 0 |
| H | System prompt (AGENTS.md) | 0 (full re-run) | Immediate |
| I | Tool behavior (script output) | 0 (diverges at shell call) | Shell step |
| J | Multi-agent + tool change | ≥1 (sub-agent step) | Shell step |

---

## Per-Test Details

"@

foreach ($r in $suiteResults) {
    $status  = if ($r.passed) { "PASS" } else { "FAIL" }
    $speedup = if ($r.speedup -eq 999) { "∞x" } else { "$($r.speedup)x" }
    $md += @"
### Test $($r.test): $($r.scenario)

**Status**: $status | **Timestamp**: $($r.timestamp)

| Metric | Value |
|--------|-------|
| T_record | $($r.t_record_s)s |
| T_replay | $($r.t_replay_s)s |
| T_fresh | $($r.t_fresh_s)s |
| Speedup (T_fresh / T_replay) | $speedup |
| Total Steps | $($r.total_steps) |
| Cache Hits | $($r.cache_hits) |
| Live Steps | $($r.live_steps) |
| Diverge At | $($r.diverge_at) |

<details>
<summary>Replay Output</summary>

``````
$($r.replay_output)
``````

</details>

---

"@
}

$md += @"
## Interpretation

- **Speedup > 1x** means replay was faster than a fresh run — caching paid off.
- **Speedup ≈ 1x** means no caching benefit (full re-run due to early divergence, e.g. Test H).
- **Cache hits = total steps** means the trace was fully reused with no live tool calls (Test E).
- **Diverge at step 0** means the very first tool result differed — common for system prompt changes or early-read files.

*Generated by `tests/replay/run-perf-suite.ps1`*
"@

Set-Content -Path $reportFile -Value $md -Encoding utf8
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Suite complete: $passCount/$($suiteResults.Count) tests passed." -ForegroundColor (if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "Report saved to: $reportFile" -ForegroundColor Cyan
Write-Host ""
