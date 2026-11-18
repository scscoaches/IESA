#requires -Version 5.1
<#
.SYNOPSIS
    Totals every school's all-time postseason record for all-time.html.

.DESCRIPTION
    Reads only local files, never IESA: placements.json (official state
    finishes, every year IESA lists), teams.json (school names and aliases),
    seasons.json and each archived or live class's data:
      - bracket-<grade>.json: regional and sectional finals, state games;
      - regional-seeds-<grade>.json: every regional game (seeded years);
      - <grade>\data.js of state-only archives: state games.
    Writes all-time.json. For each school and grade (7th, 8th, combined, or
    "other" for divisions with no grade page, such as the boys' Heavyweight
    tournaments) it records, in this order:
      titles, runner-up, third, fourth, state trips, state wins, state losses,
      sectional titles, regional titles, playoff wins, playoff losses,
      last title year (0 for none), first state trip year (0 for none).
    Run it after publishing a season, Build-IesaPlacements.ps1 and
    Build-IesaTeamIndex.ps1. Update-IesaScores.ps1 runs it with them.
#>
param([string]$SiteRoot = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'IesaSitePages.ps1')

function Get-TeamKey([string]$name) {
    # Must match key() in 2026\my-team.js and Build-IesaTeamIndex.ps1.
    $value = $name -replace '\s*\(\d+-\d+\)\s*$', '' -replace '(?i)\s*\(Co-?op\)\s*$', ''
    $value = $value.ToLowerInvariant() -replace "['\u2019]s\b", '' -replace '\.', '' -replace '-', ' '
    ($value -replace '\s+', ' ').Trim()
}

function Read-Json([string]$path) {
    if (!(Test-Path -LiteralPath $path)) { return $null }
    Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

# School names: teams.json's current name for every key and alias.
$teams = Read-Json (Join-Path $SiteRoot 'teams.json')
$display = @{}
if ($teams) {
    for ($i = 0; $i -lt @($teams.names).Count; $i++) { $display[(Get-TeamKey $teams.names[$i])] = $teams.names[$i] }
    foreach ($alias in $teams.aliases.PSObject.Properties) { $display[$alias.Name] = $teams.names[[int]$alias.Value] }
}

# school name -> grade -> 13 counters (see .DESCRIPTION).
$stats = @{}
function Get-Row([string]$team, [string]$grade) {
    if (!$team) { return $null }
    $key = Get-TeamKey $team
    if (!$key) { return $null }
    $name = if ($display.ContainsKey($key)) { $display[$key] } else { ($team -replace '\s*\(\d+-\d+\)\s*$', '').Trim() }
    if (!$stats.ContainsKey($name)) { $stats[$name] = @{} }
    if (!$stats[$name].ContainsKey($grade)) { $stats[$name][$grade] = [int[]]::new(13) }
    return , $stats[$name][$grade]
}
function Add-Game([string]$winner, [string]$loser, [string]$grade, [int]$winIndex, [int]$lossIndex) {
    if (!$winner -or !$loser) { return }
    $w = Get-Row $winner $grade; $l = Get-Row $loser $grade
    $w[$winIndex]++; $l[$lossIndex]++
}
# One trip per school, grade and year (boys' ungraded divisions ran alongside the grades).
$tripSeen = @{}
function Add-Trip([string]$team, [string]$grade, [int]$year, [string]$division = '') {
    if (!$team) { return }
    $key = Get-TeamKey $team
    if ($tripSeen.ContainsKey("$year|$key|$grade|$division")) { return }
    $tripSeen["$year|$key|$grade|$division"] = $true
    $row = Get-Row $team $grade
    $row[4]++
    if (!$row[12] -or $year -lt $row[12]) { $row[12] = $year }
}

# Official state finishes.
$placements = Read-Json (Join-Path $SiteRoot 'placements.json')
foreach ($result in @($placements.results)) {
    $grade = if ($result.grade) { [string]$result.grade } else { 'other' }
    for ($place = 0; $place -lt 4; $place++) {
        $team = @($result.places)[$place]
        if (!$team) { continue }
        $row = Get-Row $team $grade
        $row[$place]++
        if ($place -eq 0 -and [int]$result.year -gt $row[11]) { $row[11] = [int]$result.year }
    }
}

# Every published class's postseason games.
$seasonCount = 0
foreach ($season in Read-IesaCatalogue $SiteRoot) {
    $year = [int]$season.year
    $classes = if ($season.PSObject.Properties['classes']) { @($season.classes) } elseif ($season.className) { @($season.className) } else { @('') }
    foreach ($className in $classes) {
        $folder = Join-Path $SiteRoot (Get-IesaClassFolder $SiteRoot $year $className)
        foreach ($grade in 'combined', '7th', '8th') {
            $bracket = Read-Json (Join-Path $folder "bracket-$grade.json")
            if ($bracket) {
                $seeds = Read-Json (Join-Path $folder "regional-seeds-$grade.json")
                $seeded = @{}
                if ($seeds) {
                    foreach ($regional in $seeds.regionalBrackets.PSObject.Properties) {
                        $games = @($regional.Value.rounds | ForEach-Object { $_ } | Where-Object { $_ -and !$_.bye -and $_.winner })
                        if (!$games.Count) { continue }
                        $seeded[$regional.Name] = $true
                        foreach ($game in $games) {
                            $loser = @($game.teams | Where-Object { $_ -and $_ -ne $game.winner })[0]
                            Add-Game $game.winner $loser $grade 9 10
                        }
                    }
                }
                foreach ($regional in $bracket.regionals.PSObject.Properties) {
                    $final = $regional.Value
                    if (!$final.winner) { continue }
                    (Get-Row $final.winner $grade)[8]++
                    # The regional final is already among the seeded games when published.
                    if (!$seeded.ContainsKey($regional.Name)) { Add-Game $final.winner $final.loser $grade 9 10 }
                }
                foreach ($sectional in $bracket.sectionals.PSObject.Properties) {
                    $final = $sectional.Value
                    if (!$final.winner) { continue }
                    (Get-Row $final.winner $grade)[7]++
                    Add-Game $final.winner $final.loser $grade 9 10
                }
                foreach ($game in $bracket.games.PSObject.Properties) {
                    foreach ($team in @($game.Value.teams)) { Add-Trip $team $grade $year }
                    if ($game.Value.winner -and $game.Value.loser) {
                        Add-Game $game.Value.winner $game.Value.loser $grade 5 6
                        Add-Game $game.Value.winner $game.Value.loser $grade 9 10
                    }
                }
                $seasonCount++
                continue
            }
            $dataPath = Join-Path (Join-Path $folder $grade) 'data.js'
            if (!(Test-Path -LiteralPath $dataPath)) { continue }
            $text = Get-Content -Raw -LiteralPath $dataPath
            if ($text -notmatch 'earlyTournamentData') { continue }
            $early = Read-IesaPageData $dataPath
            foreach ($round in $early.rounds.PSObject.Properties) {
                foreach ($game in @($round.Value)) {
                    foreach ($team in @($game.teams)) { Add-Trip $team $grade $year }
                    $loser = @($game.teams | Where-Object { $_ -ne $game.winner })[0]
                    Add-Game $game.winner $loser $grade 5 6
                    Add-Game $game.winner $loser $grade 9 10
                }
            }
            $seasonCount++
        }
    }
}

# A trophy is a state trip too, including years without published games.
foreach ($result in @($placements.results)) {
    $grade = if ($result.grade) { [string]$result.grade } else { 'other' }
    # Ungraded boys' divisions (Heavyweight, Lightweight...) are separate tournaments.
    $division = if ($result.grade) { '' } else { [string]$result.code }
    foreach ($team in @($result.places)) { Add-Trip $team $grade ([int]$result.year) $division }
}

$schools = @($stats.Keys | Sort-Object | ForEach-Object {
    $grades = [ordered]@{}
    foreach ($grade in @($stats[$_].Keys | Sort-Object)) { $grades[$grade] = $stats[$_][$grade] }
    [ordered]@{ name = $_; g = $grades }
})
$years = @(Read-IesaCatalogue $SiteRoot | ForEach-Object { [int]$_.year }) + @($placements.results | ForEach-Object { [int]$_.year })
$output = [ordered]@{
    generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    firstYear = ($years | Measure-Object -Minimum).Minimum
    lastYear = ($years | Measure-Object -Maximum).Maximum
    columns = @('titles', 'second', 'third', 'fourth', 'stateTrips', 'stateWins', 'stateLosses',
        'sectionalTitles', 'regionalTitles', 'playoffWins', 'playoffLosses', 'lastTitle', 'firstTrip')
    schools = $schools
}
$destination = Join-Path $SiteRoot 'all-time.json'
Write-IesaText "$destination.tmp" ((ConvertTo-Json -InputObject $output -Depth 6 -Compress) + "`n")
Move-Item -Force "$destination.tmp" $destination
Write-Host "All-time stats for $($schools.Count) schools from $seasonCount season brackets and $(@($placements.results).Count) state tournaments."
