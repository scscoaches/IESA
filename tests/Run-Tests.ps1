#requires -Version 5.1
<#
.SYNOPSIS
    Runs the IESA site tests. Exits 1 if any test fails.

.DESCRIPTION
    Test-SiteIntegrity.ps1 checks the published files (no network).
    Test-Refresh.ps1 runs 2026\Update-IesaScores.ps1 end to end against a fake
    IESA site in a temporary folder (no network, about a minute).
    Run before committing script or template changes:  .\tests\Run-Tests.ps1
#>
$ErrorActionPreference = 'Stop'
$passes = 0
$failures = @()
foreach ($test in 'Test-SiteIntegrity.ps1', 'Test-Refresh.ps1') {
    Write-Host "`n== $test" -ForegroundColor Cyan
    # A child's stderr must not stop the run; anything unexpected shows up as missing results.
    $ErrorActionPreference = 'Continue'
    $lines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $test) 2>&1 | ForEach-Object { "$_" })
    $ErrorActionPreference = 'Stop'
    $passCount = @($lines | Where-Object { "$_" -match '^\s*PASS ' }).Count
    $failLines = @($lines | Where-Object { "$_" -match '^\s*FAIL ' })
    $lines | Where-Object { "$_" -match '^\s*(PASS|FAIL) |^[A-Z]' -and "$_" -notmatch '^(Passes|Failures)\b' } | ForEach-Object { Write-Host $_ }
    $passes += $passCount
    $failures += $failLines
    if (!$passCount -and !$failLines.Count) { $failures += "$test produced no results" }
}
Write-Host "`n$passes passed, $($failures.Count) failed" -ForegroundColor $(if ($failures.Count) { 'Red' } else { 'Green' })
if ($failures.Count) { $failures | ForEach-Object { Write-Host $_ -ForegroundColor Red }; exit 1 }
