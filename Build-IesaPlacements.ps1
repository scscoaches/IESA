#requires -Version 5.1
<#
.SYNOPSIS
    Records every season in which the followed school finished in the top four.

.DESCRIPTION
    The season drop-down lists close to fifty years, which makes the handful of
    seasons worth revisiting impossible to spot. This scans the archived
    brackets and writes placements.json, which season-selector.js uses to mark
    those years with a dot.

    Placement is derived from the two final games rather than stored anywhere by
    IESA: the championship winner and loser are first and second, and the third
    place game's winner and loser are third and fourth. Seasons use one of two
    layouts - an eight team bracket numbers the third place game 7 and the title
    game 8, and a sixteen team bracket numbers them 15 and 16 - matching the
    numbering app.js uses to draw them. The shape is read from the bracket's own
    game numbers so that a live season, whose data.js is executable JavaScript
    rather than JSON, is still covered. Seasons before 1998 have no bracket file
    and keep their results inline on the page instead.

    Re-run this after a season finishes.
#>
param(
    [string]$SiteRoot = "C:\inetpub\personalroot\IESA",
    [string]$Team = "Springfield Christian"
)

$ErrorActionPreference = "Stop"

function Read-JsonFile([string]$path) {
    Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
}

# Archive pages ship data as a JavaScript assignment; the value itself is JSON.
function Read-DataScript([string]$path) {
    $text = Get-Content -Raw -Encoding UTF8 $path
    $start = $text.IndexOf("{")
    $end = $text.LastIndexOf("}")
    if ($start -lt 0 -or $end -le $start) { return $null }
    try { $text.Substring($start, $end - $start + 1) | ConvertFrom-Json } catch { $null }
}

function Get-Opponent($game) {
    if (!$game) { return $null }
    $game.teams | Where-Object { $_ -ne $game.winner } | Select-Object -First 1
}

$seasons = [ordered]@{}

foreach ($yearDir in Get-ChildItem -Directory $SiteRoot |
    Where-Object { $_.Name -match '^\d{4}$' } | Sort-Object Name) {
    $year = $yearDir.Name

    foreach ($grade in @("7th", "8th", "combined")) {
        $folder = Join-Path $yearDir.FullName $grade
        if (!(Test-Path $folder)) { continue }

        $places = @{}
        $bracketPath = Join-Path $yearDir.FullName "bracket-$grade.json"

        if (Test-Path $bracketPath) {
            # 1998 onward: results live in a sibling bracket file. The bracket's
            # own game numbers reveal its shape, so the page data is not needed -
            # which matters because a live season's data.js is executable
            # JavaScript rather than JSON.
            $games = (Read-JsonFile $bracketPath).games
            if (!$games) { continue }
            $numbers = $games.PSObject.Properties.Name
            $hasFirstRound = $numbers -contains "16"
            $titleNumber = if ($hasFirstRound) { "16" } else { "8" }
            $thirdNumber = if ($hasFirstRound) { "15" } else { "7" }
            $title = $games.$titleNumber
            $third = $games.$thirdNumber
            if ($title) { $places[1] = $title.winner; $places[2] = $title.loser }
            if ($third) { $places[3] = $third.winner; $places[4] = $third.loser }
        } else {
            # 1979-1997: the whole state bracket is inline on the page.
            $dataJson = Join-Path $folder "data.json"
            $dataScript = Join-Path $folder "data.js"
            $data = if (Test-Path $dataJson) { Read-JsonFile $dataJson }
                    elseif (Test-Path $dataScript) { Read-DataScript $dataScript }
                    else { $null }
            if (!$data -or !($data.PSObject.Properties.Name -contains "rounds") -or !$data.rounds) {
                continue
            }
            $title = @($data.rounds."State Championship")[0]
            $third = @($data.rounds."Third Place")[0]
            if ($title) { $places[1] = $title.winner; $places[2] = Get-Opponent $title }
            if ($third) { $places[3] = $third.winner; $places[4] = Get-Opponent $third }
        }

        foreach ($place in 1..4) {
            if ($places[$place] -eq $Team) {
                if (!$seasons.Contains($year)) { $seasons[$year] = [ordered]@{} }
                $seasons[$year][$grade] = $place
                break
            }
        }
    }
}

$output = [ordered]@{
    team = $Team
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    seasons = $seasons
}

$destination = Join-Path $SiteRoot "placements.json"
$temporary = "$destination.tmp"
$output | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $temporary
Move-Item -Force $temporary $destination

$total = ($seasons.Keys | ForEach-Object { $seasons[$_].Keys.Count } | Measure-Object -Sum).Sum
Write-Host "Recorded $total top-four finish(es) for $Team across $($seasons.Keys.Count) season(s)."
foreach ($year in $seasons.Keys) {
    foreach ($grade in $seasons[$year].Keys) {
        Write-Host ("  {0} {1}: place {2}" -f $year, $grade, $seasons[$year][$grade])
    }
}
