#requires -Version 5.1
# Shared helpers for the IESA site tests. Dot-source this file.

$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Passes = 0

function Assert-True([bool]$condition, [string]$message) {
    if ($condition) { $script:Passes++; Write-Host "  PASS $message" -ForegroundColor Green }
    else { $script:Failures.Add($message); Write-Host "  FAIL $message" -ForegroundColor Red }
}

function Assert-Equal($expected, $actual, [string]$message) {
    Assert-True ($expected -eq $actual) "$message (expected '$expected', got '$actual')"
}

function Get-TestResult { [pscustomobject]@{ Passes = $script:Passes; Failures = @($script:Failures) } }

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

# A throwaway copy of the live season with a fake IESA client, so the real refresh
# script can run end to end without a single request to www.iesa.org.
function New-MockSite {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("iesa-test-" + [guid]::NewGuid().ToString('N'))
    $season = Join-Path $root '2026'
    New-Item -ItemType Directory -Force -Path $season | Out-Null
    Copy-Item (Join-Path $script:RepoRoot 'seasons.json') $root
    # Dates in the past and an end far ahead, so every code path runs on any day.
    '{"year":2026,"followedClass":"2A","seedsFrom":"2026-01-01","bracketFrom":"2026-01-01","endDate":"2100-12-31"}' |
        Set-Content -Encoding UTF8 (Join-Path $root 'live-season.json')
    Copy-Item (Join-Path $script:RepoRoot '2026\Update-IesaScores.ps1') $season
    foreach ($grade in '7th', '8th') {
        New-Item -ItemType Directory -Force -Path (Join-Path $season $grade) | Out-Null
        Copy-Item (Join-Path $script:RepoRoot "2026\$grade\data.js") (Join-Path $season $grade)
        Copy-Item (Join-Path $script:RepoRoot "2026\scores-$grade.json") $season
    }
    foreach ($class in '1A', '3A', '4A') {
        foreach ($grade in '7th', '8th') {
            $target = Join-Path $season "$class\$grade"
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            Copy-Item (Join-Path $script:RepoRoot "2026\$class\$grade\data.json") $target
            Copy-Item (Join-Path $script:RepoRoot "2026\$class\scores-$grade.json") (Join-Path $season $class)
        }
    }
    # Child scripts record how they were called instead of doing anything.
    foreach ($stub in 'Update-NfhsEvents', 'Update-HudlEvents', 'Update-Strength', 'Update-IesaSeeds', 'Update-IesaBracket') {
        "param(`$SitePath, `$ClassName, `$Year, `$SeasonStart, `$Grades)`nAdd-Content -LiteralPath (Join-Path (Split-Path -Parent `$PSScriptRoot) 'calls.log') ('$stub|' + `$SitePath + '|' + `$ClassName + '|' + `$Year + '|' + (`$Grades -join ','))" |
            Set-Content -Encoding UTF8 (Join-Path $season "$stub.ps1")
    }
    # Every school page reports one decided game; the member directory lists every
    # school in every roster; assignment pages are empty (no roster drift checked).
    @'
if ($null -eq $global:IesaGuard) { $global:IesaGuard = @{ Count = 0 } }
function Get-IesaPause { $null }
function Invoke-IesaPage([string]$Uri) {
    $global:IesaGuard.Count++
    Add-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'requests.log') $Uri
    if ($Uri -match 'members\.asp') {
        $names = @(Get-ChildItem -Recurse -Filter data.json -Path $PSScriptRoot | ForEach-Object {
            (Get-Content -Raw $_.FullName | ConvertFrom-Json).regionals | ForEach-Object { $_.teams } })
        $names += foreach ($g in '7th', '8th') {
            $text = Get-Content -Raw (Join-Path $PSScriptRoot "$g\data.js")
            [regex]::Matches($text, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        }
        $i = 0
        $html = ($names | Select-Object -Unique | ForEach-Object { $i++; "<a href='memberdetail.asp?SchoolID=$i'>$($_ -replace '\s+\(Co-op\)', '')</a>" }) -join ''
        return [pscustomobject]@{ StatusCode = 200; Content = $html }
    }
    if ($Uri -match 'assignments_Regional') { return [pscustomobject]@{ StatusCode = 200; Content = '' } }
    return [pscustomobject]@{ StatusCode = 200; Content = "<td class='ListData'>Mock School def. Other School</td><td class='ListData-R'>30-20</td>" }
}
'@ | Set-Content -Encoding UTF8 (Join-Path $season 'IesaRequest.ps1')
    return $root
}

# Runs the refresh in a fresh process (the request guard is per process) and
# returns its output, the IESA requests it made and the child scripts it called.
function Invoke-MockRefresh([string]$root, [string]$arguments = '') {
    Remove-Item -LiteralPath (Join-Path $root 'requests.log'), (Join-Path $root 'calls.log') -ErrorAction SilentlyContinue
    $script = Join-Path $root '2026\Update-IesaScores.ps1'
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -Command "try { & '$script' -MinimumHoursBetweenRuns 0 $arguments *>&1 | Out-String } catch { `$_ | Out-String }"
    $requests = @(Get-Content -LiteralPath (Join-Path $root 'requests.log') -ErrorAction SilentlyContinue)
    $calls = @(Get-Content -LiteralPath (Join-Path $root 'calls.log') -ErrorAction SilentlyContinue)
    [pscustomobject]@{ Output = ($output -join "`n"); Requests = $requests; Calls = $calls }
}

function Set-FullSweepToday([string]$root) {
    $today = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Central Standard Time').ToString('yyyy-MM-dd')
    Get-ChildItem -Recurse -Filter 'scores-*.json' -Path (Join-Path $root '2026') | ForEach-Object {
        $cache = Get-Content -Raw $_.FullName | ConvertFrom-Json
        $cache | Add-Member -NotePropertyName fullSweepDate -NotePropertyValue $today -Force
        $cache | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $_.FullName
    }
}
