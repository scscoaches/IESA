#requires -Version 5.1
# Tests of the IESA calendar reader and the automatic season setup (Sync-IesaSeason.ps1),
# against a saved copy of the calendar and a fake IESA site. No network.
. (Join-Path $PSScriptRoot 'IesaTestHelpers.ps1')
. (Join-Path $script:RepoRoot 'IesaCalendar.ps1')

$fixture = Join-Path $PSScriptRoot 'fixtures\gbk-calendar.html'

Write-Host 'Calendar dates'
$calendar = Get-IesaCalendar (Get-Content -Raw $fixture)
Assert-Equal '2026,2027,2028,2029' (($calendar.Keys | Sort-Object) -join ',') 'four seasons read'
$day = { param($year, $grade, $item, $edge = 'first') $calendar[$year][$grade][$item].$edge.ToString('yyyy-MM-dd') }
Assert-Equal '2027-08-01' (& $day 2027 '7th' 'finalEntryDeadline') 'Final Entry Deadline'
Assert-Equal '2027-09-25' (& $day 2027 '8th' 'gamesMayBegin') 'Games may begin'
Assert-Equal '2027-11-11' (& $day 2027 '7th' 'onlineRanking') '7th grade Online Ranking'
Assert-Equal '2027-11-18' (& $day 2027 '8th' 'onlineRanking') '8th grade Online Ranking'
Assert-Equal '2026-11-10' (ConvertFrom-IesaCalendarDate 'Nov.10, 2026').first.ToString('yyyy-MM-dd') '"Nov.10, 2026" (no space) parses'
Assert-Equal '2026-11-25' (& $day 2026 '7th' 'regionals' 'last') '"Nov. 21, 23-25, 2026" ends on the 25th'
Assert-Equal '2026-12-04' (& $day 2026 '8th' 'regionals' 'last') '"Nov. 30, Dec. 1, 3, 4 2026" crosses into December'
Assert-Equal '2028-12-01' (& $day 2028 '8th' 'regionals' 'last') '"Nov. 27,28,30 Dec.1,2028" parses'
Assert-Equal '2027-12-16' (& $day 2027 '8th' 'state' 'last') '8th grade state final'
Assert-Equal '2027-12-20' (& $day 2027 '7th' 'seasonMustEnd') 'Season must end'

$dates = Get-IesaSeasonDates $calendar 2027
Assert-Equal '2027-09-25' $dates.gamesFrom 'scores tracked from Games may begin'
Assert-Equal '2027-11-11' $dates.grades['7th'].seedsFrom '7th grade official seeds from its ranking date'
Assert-Equal '2027-11-18' $dates.grades['8th'].seedsFrom '8th grade official seeds from its ranking date'
Assert-Equal '2027-11-29' $dates.grades['8th'].bracketFrom '8th grade results from its first regional'
Assert-Equal '2027-12-19' $dates.endDate 'refreshes stop on the Season must end date (last day is the day before)'

# A fake site: live-season.json, the real setup script and calendar reader, a
# fake IESA client and a Start-IesaSeason stub that records how it was called.
function New-SetupSite([string]$liveYear = '2026', [switch]$published) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('iesa-setup-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path (Join-Path $root '2026') | Out-Null
    "{`"year`":$liveYear,`"followedClass`":`"2A`"}" | Set-Content -Encoding UTF8 (Join-Path $root 'live-season.json')
    Copy-Item (Join-Path $script:RepoRoot 'Sync-IesaSeason.ps1'), (Join-Path $script:RepoRoot 'IesaCalendar.ps1') $root
    Copy-Item $fixture (Join-Path $root 'calendar.html')
    if ($published) { 'yes' | Set-Content (Join-Path $root 'published.txt') }
    @'
if ($null -eq $global:IesaGuard) { $global:IesaGuard = @{ Count = 0 } }
function Get-IesaPause { $null }
function Invoke-IesaPage([string]$Uri) {
    $root = Split-Path -Parent $PSScriptRoot
    Add-Content -LiteralPath (Join-Path $root 'requests.log') $Uri
    $published = Test-Path (Join-Path $root 'published.txt')
    $content = if ($Uri -match 'calendar\.asp') { Get-Content -Raw (Join-Path $root 'calendar.html') }
        elseif ($Uri -match 'assignments_Regional' -and $published) { (1..16 | ForEach-Object { "<td class='TableSubtitle2'>Regional $_</td>" }) -join '' }
        elseif ($Uri -match 'scoreboards' -and $published) { '7th Grade Class 2A  State Tournament' }
        else { '<html>No data</html>' }
    [pscustomobject]@{ StatusCode = 200; Content = $content }
}
'@ | Set-Content -Encoding UTF8 (Join-Path $root '2026\IesaRequest.ps1')
    @'
param($Year, $SiteRoot, $SeasonDates)
Add-Content -LiteralPath (Join-Path $SiteRoot 'start.log') ("$Year|" + $SeasonDates.gamesFrom + '|' + $SeasonDates.endDate)
'@ | Set-Content -Encoding UTF8 (Join-Path $root 'Start-IesaSeason.ps1')
    return $root
}

function Invoke-Setup([string]$root, [string]$today) {
    $outputFile = Join-Path $root 'github-output.txt'
    $env:GITHUB_OUTPUT = $outputFile
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -Command "try { & '$root\Sync-IesaSeason.ps1' -SiteRoot '$root' -Today '$today' *>&1 | Out-String } catch { `$_ | Out-String }"
    } finally { Remove-Item Env:\GITHUB_OUTPUT }
    [pscustomobject]@{
        Output = ($output -join "`n")
        Requests = @(Get-Content -LiteralPath (Join-Path $root 'requests.log') -ErrorAction SilentlyContinue)
        Started = @(Get-Content -LiteralPath (Join-Path $root 'start.log') -ErrorAction SilentlyContinue)
        Created = (Test-Path $outputFile) -and (Get-Content -Raw $outputFile) -match 'created=true'
    }
}

$sites = @()
try {
    Write-Host 'Before the Final Entry Deadline nothing happens'
    $sites += $root = New-SetupSite -published
    $run = Invoke-Setup $root '2027-07-31'
    Assert-True ($run.Output -match 'already set up') "the live season is still current ($($run.Output.Trim()))"
    Assert-Equal 0 $run.Requests.Count 'no IESA requests'
    Assert-Equal 0 $run.Started.Count 'no season created'

    Write-Host 'After the deadline, waits until IESA publishes the season'
    $sites += $root = New-SetupSite
    $run = Invoke-Setup $root '2027-08-01'
    Assert-True ($run.Output -match 'Waiting for IESA to publish') "waits for assignments and scoreboard ($($run.Output.Trim()))"
    Assert-Equal 4 $run.Requests.Count 'calendar, two assignment pages and the scoreboard'
    Assert-Equal 0 $run.Started.Count 'no season created yet'
    Assert-True (!$run.Created) 'no created=true for the workflow'

    Write-Host 'Once published, the next season is created with the calendar''s dates'
    $sites += $root = New-SetupSite -published
    $run = Invoke-Setup $root '2027-08-03'
    Assert-Equal 1 $run.Started.Count 'Start-IesaSeason run once'
    Assert-Equal '2027|2027-09-25|2027-12-19' ($run.Started | Select-Object -First 1) 'for 2027, games from Sept. 25, refreshes through Dec. 19'
    Assert-True $run.Created 'created=true written for the workflow'

    Write-Host 'A season already created is left alone'
    $sites += $root = New-SetupSite -liveYear 2027 -published
    $run = Invoke-Setup $root '2027-10-15'
    Assert-True ($run.Output -match 'already set up') 'nothing to do'
    Assert-Equal 0 $run.Requests.Count 'no IESA requests'
} finally {
    foreach ($site in $sites) { Remove-Item -Recurse -Force -LiteralPath $site -ErrorAction SilentlyContinue }
}
Get-TestResult
