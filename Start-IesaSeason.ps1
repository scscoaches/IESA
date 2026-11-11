#requires -Version 5.1
<#
.SYNOPSIS
    Rolls the site over to a new live season.

.DESCRIPTION
    1. Archives the current live season (from live-season.json): rebuilds each of
       its classes as an archive from IESA's final results and marks the season
       archived in seasons.json. Its hand-maintained pages are replaced by the
       archive template. Skip with -SkipArchive (for example if already done).
    2. Builds every class of the new season with Build-IesaSeason.ps1 -Live,
       the followed class first so it keeps the <year>\<grade>\ address.
    3. Writes live-season.json, which the refresh scripts and the GitHub Actions
       workflow read for the year, the followed class and the season's dates.
    4. Re-renders all pages (bumping the site version) and rebuilds teams.json.

    Run it once IESA has published the new season's regional assignments and
    state scoreboard (usually early November). Each class costs about 13 IESA
    requests to build. Review the dates afterwards: seeds normally appear about
    the second week of November, regionals the third.

.EXAMPLE
    .\Start-IesaSeason.ps1 -Year 2027 -SeedsFrom 2027-11-11 -BracketFrom 2027-11-20 -EndDate 2027-12-17
#>
param(
    [Parameter(Mandatory)][ValidateRange(2027, 2100)][int]$Year,
    [Parameter(Mandatory)][string]$SeedsFrom,
    [Parameter(Mandatory)][string]$BracketFrom,
    [Parameter(Mandatory)][string]$EndDate,
    # The class refreshed three times a day; the others are read once a day.
    [ValidateSet('1A', '2A', '3A', '4A')][string]$FollowedClass,
    [ValidateSet('1A', '2A', '3A', '4A')][string[]]$Classes = @('1A', '2A', '3A', '4A'),
    [switch]$SkipArchive,
    [string]$SiteRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'IesaSitePages.ps1')

foreach ($date in $SeedsFrom, $BracketFrom, $EndDate) {
    $null = [datetime]::ParseExact($date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
}
$configPath = Join-Path $SiteRoot 'live-season.json'
$current = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if (!$FollowedClass) { $FollowedClass = $current.followedClass }
if ($FollowedClass -notin $Classes) { throw "The followed class $FollowedClass must be one of -Classes." }
if ([int]$current.year -ge $Year) { throw "The live season is already $($current.year)." }
$builder = Join-Path $PSScriptRoot 'Build-IesaSeason.ps1'

# 1. Archive the season that just finished.
$previous = [int]$current.year
if (!$SkipArchive) {
    $entry = Read-IesaCatalogue $SiteRoot | Where-Object { $_.year -eq $previous } | Select-Object -First 1
    if ($entry -and !$entry.archived) {
        $previousClasses = if ($entry.PSObject.Properties['classes']) { @($entry.classes) } else { @($entry.className) }
        # The first class keeps <year>\<grade>\, so build it first.
        foreach ($className in @($entry.className) + @($previousClasses | Where-Object { $_ -ne $entry.className })) {
            Write-Host "Archiving $previous Class $className..."
            & $builder -Year $previous -ClassName $className -OutputRoot $SiteRoot
        }
        $seasons = @(Read-IesaCatalogue $SiteRoot)
        ($seasons | Where-Object { $_.year -eq $previous }).archived = $true
        Write-IesaCatalogue $SiteRoot $seasons
    }
}

# 2. Build the new season's classes, followed class first.
foreach ($className in @($FollowedClass) + @($Classes | Where-Object { $_ -ne $FollowedClass })) {
    Write-Host "Building $Year Class $className..."
    & $builder -Year $Year -ClassName $className -OutputRoot $SiteRoot -Live
}

# 3. Point the refresh scripts and the workflow at the new season.
$config = [ordered]@{
    year = $Year
    followedClass = $FollowedClass
    seedsFrom = $SeedsFrom
    bracketFrom = $BracketFrom
    endDate = $EndDate
}
Write-IesaText $configPath (($config | ConvertTo-Json) + "`n")

# 4. Stamp every page and index the new season's schools.
& (Join-Path $PSScriptRoot 'Update-IesaPageShells.ps1') -SiteRoot $SiteRoot
& (Join-Path $PSScriptRoot 'Build-IesaTeamIndex.ps1') -SiteRoot $SiteRoot
Write-Host "Live season is now $Year (Class $FollowedClass every run; others daily). Commit and push to publish."
Write-Host "Last season's final run disabled the 'Update IESA scores' workflow: re-enable it in the Actions tab (or: gh workflow enable update-scores.yml)."
