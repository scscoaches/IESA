#requires -Version 5.1
<#
.SYNOPSIS
    Lists every school on the site and the class it played in each season.

.DESCRIPTION
    Writes teams.json, which my-team.js uses for the "My team" picker and
    season-selector.js uses to open the class the chosen team played in when
    the visitor changes year. Reads only local files: archived page data, the
    live season's score caches and placements.json. Run it after publishing
    a season or class and after Build-IesaPlacements.ps1.

    Names are grouped by Get-TeamKey, the same rule my-team.js uses, so a
    "(Co-op)" suffix does not split one school into two.
#>
param([string]$SiteRoot = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'IesaSitePages.ps1')

function Get-TeamKey([string]$name) {
    # Must match key() in 2026\my-team.js. Spelling variants of one school
    # ("St. Michael's"/"St. Michael", "Colfax-Ridgeview"/"Colfax Ridgeview")
    # share a key; the most recent spelling is displayed.
    $value = $name -replace '\s*\(\d+-\d+\)\s*$', '' -replace '(?i)\s*\(Co-?op\)\s*$', ''
    $value = $value.ToLowerInvariant() -replace "['\u2019]s\b", '' -replace '\.', '' -replace '-', ' '
    ($value -replace '\s+', ' ').Trim()
}

# IESA lists some schools with and without their town on different pages or
# in different years. Each alias maps to the key of the name IESA uses now.
# Only confirmed same-school pairs belong here: "Pleasant Hill" (Pike County)
# and "Peoria Pleasant Hill" are different schools, as are the St. Joseph schools.
$aliasOf = @{
    'west lincoln broadwell' = 'lincoln west lincoln broadwell'
    'chester east lincoln' = 'lincoln chester east lincoln'
    'metamora germantown hills' = 'germantown hills'
}

$display = @{}
$seasons = [ordered]@{}
$aliasesSeen = @{}

function Add-Team([int]$year, [string]$grade, [string]$className, [string]$name) {
    # 1999-2001 sectional pairings print a W-L record after the school.
    $name = ($name -replace '\s*\(\d+-\d+\)\s*$', '').Trim()
    if (!$name -or $name -match '^(?i)(TBD|Bye)$') { return }
    $key = Get-TeamKey $name
    if (!$key) { return }
    $plain = ($name -replace '(?i)\s*\(Co-?op\)\s*$', '').Trim()
    if ($aliasOf.ContainsKey($key)) {
        $aliasesSeen[$key] = $aliasOf[$key]
        $key = $aliasOf[$key]
        $aliasName = $plain
        $plain = $null
    }
    if ($plain -and (!$display.ContainsKey($key) -or $year -gt $display[$key].Year)) {
        $display[$key] = @{ Name = $plain; Year = $year }
    } elseif (!$display.ContainsKey($key)) {
        # Only the alias has been seen so far; a current-name entry replaces it.
        $display[$key] = @{ Name = $aliasName; Year = 0 }
    }
    if (!$grade) { return }
    $classKey = if ($className) { $className } else { '-' }
    if (!$seasons.Contains("$year")) { $seasons["$year"] = @{} }
    if (!$seasons["$year"].ContainsKey($grade)) { $seasons["$year"][$grade] = @{} }
    if (!$seasons["$year"][$grade].ContainsKey($classKey)) {
        $seasons["$year"][$grade][$classKey] = New-Object System.Collections.Generic.HashSet[string]
    }
    [void]$seasons["$year"][$grade][$classKey].Add($key)
}

foreach ($season in Read-IesaCatalogue $SiteRoot) {
    $year = [int]$season.year
    $classes = if ($season.PSObject.Properties['classes']) { @($season.classes) } elseif ($season.className) { @($season.className) } else { @('') }
    foreach ($className in $classes) {
        $folder = Join-Path $SiteRoot $(if ($className) { Get-IesaClassFolder $SiteRoot $year $className } else { "$year" })
        foreach ($grade in 'combined', '7th', '8th') {
            $gradeFolder = Join-Path $folder $grade
            if ($year -ge 2026) {
                $cache = Join-Path (Join-Path $SiteRoot "$year") "scores-$grade.json"
                if (Test-Path -LiteralPath $cache) {
                    $teams = (Get-Content -Raw -LiteralPath $cache | ConvertFrom-Json).teams
                    foreach ($name in $teams.PSObject.Properties.Name) { Add-Team $year $grade $className $name }
                }
                continue
            }
            $dataScript = Join-Path $gradeFolder 'data.js'
            if (!(Test-Path -LiteralPath $dataScript)) { continue }
            $data = Read-IesaPageData $dataScript
            if ($data.PSObject.Properties['rounds']) {
                foreach ($round in $data.rounds.PSObject.Properties) {
                    foreach ($game in @($round.Value)) {
                        foreach ($name in @($game.teams)) { Add-Team $year $grade $className $name }
                    }
                }
                foreach ($pairing in @($data.sectionals)) {
                    foreach ($name in @($pairing.teams)) { Add-Team $year $grade $className $name }
                }
            } else {
                foreach ($regional in @($data.regionals)) {
                    foreach ($name in @($regional.teams)) { Add-Team $year $grade $className $name }
                }
            }
        }
    }
}

# A school that only appears in the state history is still selectable, and its
# finish also tells us its class that season.
$placementsPath = Join-Path $SiteRoot 'placements.json'
if (Test-Path -LiteralPath $placementsPath) {
    foreach ($result in (Get-Content -Raw -LiteralPath $placementsPath | ConvertFrom-Json).results) {
        foreach ($name in @($result.places)) {
            Add-Team ([int]$result.year) $result.grade $result.className $name
        }
    }
}

# Names that differ only by a school-type suffix ("Taylorville" / "Taylorville
# JHS", "Mansfield Blue Ridge JHS" / "IJHS") are one school, unless two of them
# appear in the same 2002+ roster. Earlier state archives are not checked:
# their sectional pairings use short names beside the bracket's full ones.
function Get-BaseKey([string]$key) { ($key -replace '\s+(ijhs|jhs|ijh|jh|ms|gs|es|ugc)$', '').Trim() }
foreach ($group in @($display.Keys | Group-Object { Get-BaseKey $_ } | Where-Object { $_.Count -gt 1 -and $_.Name })) {
    $members = @($group.Group)
    $together = $false
    foreach ($year in @($seasons.Keys | Where-Object { [int]$_ -ge 2002 })) {
        foreach ($grade in $seasons[$year].Values) {
            foreach ($set in $grade.Values) {
                if (@($members | Where-Object { $set.Contains($_) }).Count -gt 1) { $together = $true }
            }
        }
    }
    if ($together) { continue }
    $canonical = @($members | Sort-Object { $display[$_].Year }, { $display[$_].Name.Length } -Descending)[0]
    foreach ($member in $members) {
        if ($member -eq $canonical) { continue }
        $aliasesSeen[$member] = $canonical
        foreach ($grade in @($seasons.Values | ForEach-Object { $_.Values })) {
            foreach ($set in $grade.Values) {
                if ($set.Remove($member)) { [void]$set.Add($canonical) }
            }
        }
        $display.Remove($member)
    }
}

$keys = @($display.Keys | Sort-Object { $display[$_].Name })
$index = @{}
for ($i = 0; $i -lt $keys.Count; $i++) { $index[$keys[$i]] = $i }
$seasonOutput = [ordered]@{}
foreach ($year in @($seasons.Keys | Sort-Object { [int]$_ } -Descending)) {
    $grades = [ordered]@{}
    foreach ($grade in @($seasons[$year].Keys | Sort-Object)) {
        $classOutput = [ordered]@{}
        foreach ($className in @($seasons[$year][$grade].Keys | Sort-Object)) {
            $classOutput[$className] = @($seasons[$year][$grade][$className] | ForEach-Object { $index[$_] } | Sort-Object)
        }
        $grades[$grade] = $classOutput
    }
    $seasonOutput[$year] = $grades
}

$aliasOutput = [ordered]@{}
foreach ($alias in @($aliasesSeen.Keys | Sort-Object)) { $aliasOutput[$alias] = $index[$aliasesSeen[$alias]] }

$output = [ordered]@{
    generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    names = @($keys | ForEach-Object { $display[$_].Name })
    aliases = $aliasOutput
    seasons = $seasonOutput
}
$destination = Join-Path $SiteRoot 'teams.json'
[System.IO.File]::WriteAllText("$destination.tmp", ($output | ConvertTo-Json -Depth 6 -Compress),
    [System.Text.UTF8Encoding]::new($false))
Move-Item -Force "$destination.tmp" $destination
Write-Host "Indexed $($keys.Count) schools across $($seasonOutput.Count) seasons."
