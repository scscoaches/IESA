#requires -Version 5.1
<#
.SYNOPSIS
    Creates the next live season automatically once IESA has opened it.

.DESCRIPTION
    Run daily (the season-setup GitHub Actions workflow runs it each morning in
    August-October). It makes no IESA request when the live season is already
    the current one. Otherwise it reads IESA's girls basketball calendar and,
    from that season's "Final Entry Deadline", checks whether IESA has published
    the followed class's regional assignments (both grades) and state scoreboard.
    Until then it waits and tries again the next day (3 requests). Once they are
    published it runs Start-IesaSeason.ps1 with the calendar's dates: the
    finished season is archived and every class of the new one is built with its
    regionals, sectionals and state pairings. It writes created=true to the
    GitHub Actions step output.

    The new season's dates in live-season.json come from the calendar: scores
    are tracked from "Games may begin", each grade's official seeds from its
    "Online Ranking" date and its results from its first regional date, and
    refreshes stop when every final is played, or the day before "Season must end".
#>
param(
    [string]$SiteRoot = $PSScriptRoot,
    # For tests: the Central date to act as today (yyyy-MM-dd).
    [string]$Today
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '2026\IesaRequest.ps1')
. (Join-Path $PSScriptRoot 'IesaCalendar.ps1')

$now = if ($Today) { [datetime]::ParseExact($Today, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } else {
    [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Central Standard Time').Date
}
$live = Get-Content -Raw -LiteralPath (Join-Path $SiteRoot 'live-season.json') | ConvertFrom-Json
# A season is played in the fall; its entries close in August.
$target = if ($now.Month -ge 8) { $now.Year } else { $now.Year - 1 }
if ([int]$live.year -ge $target) {
    Write-Output "The $($live.year) season is already set up; nothing to do."
    return
}

$calendar = Get-IesaCalendar ([string](Invoke-IesaPage $IesaCalendarUrl).Content)
$dates = Get-IesaSeasonDates $calendar $target
$opens = [datetime]::ParseExact($dates.createFrom, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
if ($now -lt $opens) {
    Write-Output "The $target season is created after IESA's Final Entry Deadline ($($opens.ToString('MMMM d, yyyy')))."
    return
}

# Build-IesaSeason refuses a season until its assignments and scoreboard exist,
# so check the followed class first rather than archiving and failing halfway.
$followed = [string]$live.followedClass
$missing = @()
foreach ($level in '7', '8') {
    $url = "https://www.iesa.org/activities/gbk/assignments_Regional.asp?Year=$target&Class=$level-$followed"
    $regionals = [regex]::Matches([string](Invoke-IesaPage $url).Content, "(?is)<td\s+class=['""]TableSubtitle2['""][^>]*>\s*Regional\s+\d+\s*</td>").Count
    if ($regionals -lt 16) { $missing += "$($level)th grade Class $followed regional assignments ($regionals of 16 regionals)" }
}
$scoreboardUrl = "https://www.iesa.org/activities/gbk/scoreboards/index.asp?Year=$target&Class=7-$followed"
if ([string](Invoke-IesaPage $scoreboardUrl).Content -notmatch "7th Grade Class $followed\s+State Tournament") {
    $missing += "the 7th grade Class $followed state scoreboard"
}
if ($missing.Count) {
    Write-Output "Waiting for IESA to publish $($missing -join ' and ') for $target; will check again tomorrow."
    return
}

Write-Output "Creating the $target season (replacing $($live.year))."
& (Join-Path $PSScriptRoot 'Start-IesaSeason.ps1') -Year $target -SiteRoot $SiteRoot -SeasonDates $dates
if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value 'created=true' }
Write-Output "The $target season is live."
