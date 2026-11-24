#requires -Version 5.1
<#
.SYNOPSIS
    Runs every test for both sports. Exits 1 if any fails.

.DESCRIPTION
    1. girls\tests\Run-Tests.ps1: site integrity, season set-up and score refresh
       (the shared code's tests run against the girls' copy; no IESA requests).
    2. The same site-integrity checks against boys\.
    3. Sync-IesaSharedCode.ps1 -Check: boys\ runs the same code as girls\.
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$failed = @()

Write-Host "`n#### Default page setting" -ForegroundColor Cyan
$ErrorActionPreference = 'Continue'
$lines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-DefaultPage.ps1') 2>&1 | ForEach-Object { "$_" })
$ErrorActionPreference = 'Stop'
$lines | Where-Object { $_ -match '^\s*(PASS|FAIL) |^[A-Z]' -and $_ -notmatch '^(Passes|Failures)\b' } | ForEach-Object { Write-Host $_ }
$defaultPageFailures = @($lines | Where-Object { $_ -match '^\s*FAIL ' })
if ($defaultPageFailures.Count -or !@($lines | Where-Object { $_ -match '^\s*PASS ' }).Count) { $failed += 'default page setting' }

Write-Host "`n#### Girls" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'girls\tests\Run-Tests.ps1')
if ($LASTEXITCODE) { $failed += 'girls tests' }

Write-Host "`n#### Boys site integrity" -ForegroundColor Cyan
$ErrorActionPreference = 'Continue'
$lines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'girls\tests\Test-SiteIntegrity.ps1') -SiteRoot (Join-Path $repo 'boys') 2>&1 | ForEach-Object { "$_" })
$ErrorActionPreference = 'Stop'
$lines | Where-Object { $_ -match '^\s*(PASS|FAIL) |^[A-Z]' -and $_ -notmatch '^(Passes|Failures)\b' } | ForEach-Object { Write-Host $_ }
$boysFailures = @($lines | Where-Object { $_ -match '^\s*FAIL ' })
if ($boysFailures.Count -or !@($lines | Where-Object { $_ -match '^\s*PASS ' }).Count) { $failed += 'boys site integrity' }

Write-Host "`n#### Shared code" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'Sync-IesaSharedCode.ps1') -Check
if ($LASTEXITCODE) { $failed += 'shared code differs between girls and boys (run .\Sync-IesaSharedCode.ps1)' }

if ($failed.Count) {
    Write-Host "`nFailed: $($failed -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "`nAll tests passed." -ForegroundColor Green
