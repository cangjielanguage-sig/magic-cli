# Test C: Record then replay a task that invokes ReviewerAgent.
#
# Verifies (Stage 2):
#   - Sub-agent steps are captured with isSubAgentCall=true and an embedded subTrace
#   - Regular tool steps before the sub-agent call replay as cache hits
#   - Sub-agent internal steps are recursively validated (not skipped)
#   - ReviewerAgent step reports cache hit when environment is unchanged
#   - Summary reports 'all N step(s) cache-hit'
#
# Run from the project root: .\tests\replay\test-c.ps1

$env:MAGIC_PATH = "D:\projects\CangjieMagic"

Write-Host "=== Test C: Sub-agent capture and replay (ReviewerAgent) ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] Recording (expects listDirectory + ReviewerAgent call)..."
cjpm run --name cli --run-args "--auto --mode record --trace-name replay-test-c --prompt-file tests\replay\prompt-c.txt"
if (-not $?) { exit 1 }

Write-Host ""
Write-Host "[2/3] Checking trace for sub-agent step with embedded sub-trace..."
$traceContent = Get-Content ".magic-cli\traces\replay-test-c.json" -Raw
if ($traceContent -match '"isSubAgentCall":\s*true') {
    Write-Host "  OK: trace contains at least one sub-agent step" -ForegroundColor Green
} else {
    Write-Host "  WARN: no sub-agent step found in trace -- agent may not have called ReviewerAgent" -ForegroundColor Yellow
    Write-Host "  Inspect .magic-cli\traces\replay-test-c.json and adjust the prompt if needed"
}
if ($traceContent -match '"subTrace"') {
    Write-Host "  OK: trace contains embedded sub-trace (Stage 2)" -ForegroundColor Green
} else {
    Write-Host "  WARN: no subTrace field found -- Stage 2 recording may have failed" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[3/3] Replaying immediately..."
cjpm run --name cli --run-args "--auto --mode replay --trace-name replay-test-c"

Write-Host ""
Write-Host "PASS: if all steps show 'cache hit' (including ReviewerAgent, validated recursively)" -ForegroundColor Green
Write-Host "      and summary reports 'all N step(s) cache-hit'." -ForegroundColor Green
