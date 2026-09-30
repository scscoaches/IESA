param(
    [ValidateRange(1979, 2001)][int[]]$Years = (1979..2001),
    [string]$OutputRoot = $PSScriptRoot,
    [switch]$CatalogueOnly
)

$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    throw "Output root does not exist: $OutputRoot"
}

function Get-Text([string]$markup) {
    ([System.Net.WebUtility]::HtmlDecode([regex]::Replace($markup, '(?is)<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
}

function Get-Page([string]$url, [string]$expected) {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 30
    if ($response.StatusCode -ne 200 -or $response.Content -notmatch [regex]::Escape($expected)) {
        throw "Unexpected IESA page: $url"
    }
    [string]$response.Content
}

function Get-StateGames([string]$html, [int]$year, [string]$code) {
    $champion = [regex]::Match($html, "(?is)<td\s+class=['""]Score-Champ['""][^>]*>(.*?)</td>")
    $meet = [regex]::Match($html, "(?is)<td\s+class=['""]Score-Meet['""][^>]*>(.*?)</td>")
    if (!$champion.Success -or !$meet.Success) { throw "$year $code has no state championship" }
    $headings = @([regex]::Matches($html, "(?is)<td\s+class=['""]Score-Subtitle['""][^>]*>\s*(First Round|Quarterfinals|Semifinals|Third Place|State Championship|Final Results)\s*</td>"))
    $expectedHeadings = if ($headings[0].Groups[1].Value -eq 'First Round') {
        @('First Round', 'Quarterfinals', 'Semifinals', 'Third Place', 'State Championship', 'Final Results')
    } else {
        @('Quarterfinals', 'Semifinals', 'Third Place', 'State Championship', 'Final Results')
    }
    if ($headings.Count -ne $expectedHeadings.Count) { throw "$year $code has unexpected state rounds" }
    $games = [ordered]@{}
    $roundCounts = if ($expectedHeadings.Count -eq 6) { @(8, 4, 2, 1, 1) } else { @(4, 2, 1, 1) }
    for ($round = 0; $round -lt $roundCounts.Count; $round++) {
        if ($headings[$round].Groups[1].Value -ne $expectedHeadings[$round]) {
            throw "$year $code has an unexpected round order"
        }
        $block = $html.Substring($headings[$round].Index, $headings[$round + 1].Index - $headings[$round].Index)
        $rows = @([regex]::Matches($block,
            "(?is)<td\s+class=['""]ScoreData['""]\s+nowrap>(.*?)<td\s+class=['""]ScoreData-Score['""]>(.*?)</td>\s*<td\s+class=['""]ScoreData-Row['""][^>]*>(.*?)</td>"))
        if ($rows.Count -ne $roundCounts[$round]) {
            throw "$year $code $($expectedHeadings[$round]) has $($rows.Count) games, expected $($roundCounts[$round])"
        }
        $parsed = @()
        foreach ($row in $rows) {
            $schools = @([regex]::Matches($row.Groups[1].Value,
                "(?is)<td\s+class=['""]ScoreData-BracketSchool['""][^>]*>(.*?)</td>"))
            $scores = @([regex]::Split($row.Groups[2].Value, '(?i)<br\s*/?>') | ForEach-Object { Get-Text $_ })
            if ($schools.Count -ne 2 -or $scores.Count -ne 2) {
                throw "$year $code has a state game without two schools and scores"
            }
            $teams = @($schools | ForEach-Object { Get-Text $_.Groups[1].Value })
            $victors = @(0..1 | Where-Object { $schools[$_].Groups[1].Value -match "(?i)alt=['""]Victor['""]" })
            $numeric = @($scores | Where-Object { $_ -match '^\d+$' })
            if ($teams -contains '' -or $victors.Count -ne 1 -or $numeric.Count -ne 2 -or
                [int]$scores[$victors[0]] -le [int]$scores[1 - $victors[0]]) {
                throw "$year $code has an unverified state result: $($teams -join ' / ') $($scores -join ' / ')"
            }
            $parsed += [ordered]@{
                teams = $teams
                scores = @($scores | ForEach-Object { [int]$_ })
                winner = $teams[$victors[0]]
                note = (Get-Text $row.Groups[3].Value) -replace '^(?i)F\s*', ''
            }
        }
        $games[$expectedHeadings[$round]] = $parsed
    }
    $championLines = @([regex]::Split($champion.Groups[1].Value, '(?i)<br\s*/?>') | ForEach-Object { Get-Text $_ })
    if ($championLines.Count -ne 2 -or $championLines[1] -ne $games['State Championship'][0].winner) {
        throw "$year $code champion does not agree with the championship game"
    }
    return [ordered]@{
        venue = ((Get-Text $meet.Groups[1].Value) -replace '^.*?@\s*', '').Trim()
        champion = $championLines[1]
        rounds = $games
    }
}

function Get-SectionalPairings([string]$html, [int]$year, [string]$code) {
    $cells = @([regex]::Matches($html, "(?is)<td\s+class=['""]Champion['""][^>]*>(.*?)</td>"))
    if ($cells.Count -ne 16) { throw "$year $code expected 16 published sectional pairings" }
    $pairings = @()
    foreach ($cell in $cells) {
        $line = Get-Text $cell.Groups[1].Value
        if ($line -notmatch '(?i)^(.+?)\s+vs\.\s+(.+)$') {
            throw "$year $code unexpected sectional pairing: $line"
        }
        $pairings += [ordered]@{ teams = @($Matches[1].Trim(), $Matches[2].Trim()) }
    }
    return $pairings
}

$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'archive-state-template.html') -Raw
if (!$CatalogueOnly) {
foreach ($year in $Years) {
    $grades = if ($year -le 1985) { @('combined') } else { @('7th', '8th') }
    foreach ($grade in $grades) {
        $code = if ($grade -eq 'combined') { '' } elseif ($year -le 1989) {
            if ($grade -eq '7th') { '7' } else { '8' }
        } elseif ($grade -eq '7th') { '7A' } else { '8A' }
        $url = "https://www.iesa.org/activities/gbk/index.asp?Year=$year"
        if ($code) { $url += "&Class=$code" }
        $html = Get-Page $url 'ScoreData-BracketSchool'
        $state = Get-StateGames $html $year $code
        $label = if ($grade -eq 'combined') { 'Combined 7th/8th' } elseif ($year -le 1989) {
            "$grade Grade"
        } else { "$grade Grade Class A" }
        $expectedMeet = if ($grade -eq 'combined') { 'State Tournament' } elseif ($year -le 1989) {
            "Class $(if ($grade -eq '7th') { '7' } else { '8' }) State Tournament"
        } else { "Class $(if ($grade -eq '7th') { '7' } else { '8' })A State Tournament" }
        if ((Get-Text ([regex]::Match($html, "(?is)<td\s+class=['""]Score-Meet['""][^>]*>(.*?)</td>").Groups[1].Value)) -notmatch
            "^$([regex]::Escape($expectedMeet))\b") {
            throw "$year $grade returned the wrong state tournament"
        }
        $pairings = @()
        $pairingUrl = $null
        if ($year -ge 1999) {
            $pairingUrl = "https://www.iesa.org/activities/gbk/qualifiers_Sectional.asp?Year=$year&Class=$code"
            $pairings = @(Get-SectionalPairings (Get-Page $pairingUrl 'Champion') $year $code)
        }
        $data = [ordered]@{
            year = $year
            grade = $grade
            label = $label
            source = $url
            venue = $state.venue
            champion = $state.champion
            rounds = $state.rounds
            sectionals = $pairings
            sectionalSource = $pairingUrl
        }
        $folder = Join-Path (Join-Path $OutputRoot $year) $grade
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        $json = ConvertTo-Json -InputObject $data -Depth 15 -Compress
        [System.IO.File]::WriteAllText((Join-Path $folder 'data.js'), "window.earlyTournamentData = $json;`n",
            [System.Text.UTF8Encoding]::new($false))
        $markup = $template.Replace('{{YEAR}}', [string]$year).Replace('{{LABEL}}', $label).
            Replace('{{GRADE}}', $grade)
        [System.IO.File]::WriteAllText((Join-Path $folder 'index.html'), $markup, [System.Text.UTF8Encoding]::new($false))
        Write-Output "$year $grade : $($state.champion)"
    }
    $landing = if ($year -le 1985) {
        "<a href='combined/index.html'>Combined 7th/8th tournament</a>"
    } else { "<a href='7th/index.html'>7th Grade</a> &nbsp; <a href='8th/index.html'>8th Grade</a>" }
    $heading = if ($year -le 1985) { "$year Combined 7th/8th State Tournament" } elseif ($year -le 1989) {
        "$year Girls Basketball State Tournaments"
    } else { "$year Class A Girls Basketball State Tournaments" }
    $index = "<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>$heading</title></head><body><main><h1>$heading</h1><p>$landing</p><p><a href='../index.html'>All seasons</a></p></main></body></html>`n"
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $OutputRoot $year) 'index.html'),
        $index, [System.Text.UTF8Encoding]::new($false))
}
}

$cataloguePath = Join-Path $OutputRoot 'seasons.json'
if (Test-Path -LiteralPath $cataloguePath) {
    foreach ($year in $Years) {
        $grades = if ($year -le 1985) { @('combined') } else { @('7th', '8th') }
        foreach ($grade in $grades) {
            if (!(Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $OutputRoot $year) $grade) 'data.js'))) {
                throw "Cannot list $year $grade without a published state archive"
            }
        }
    }
    $catalogue = @()
    foreach ($entry in (Get-Content -LiteralPath $cataloguePath -Raw | ConvertFrom-Json)) {
        if ($entry.year -notin $Years) { $catalogue += $entry }
    }
    foreach ($year in $Years) {
        $catalogue += [pscustomobject]@{
            year = $year
            className = if ($year -le 1989) { $null } else { 'A' }
            gradeMode = if ($year -le 1985) { 'combined' } else { 'separate' }
            archived = $true
        }
    }
    $catalogue = @($catalogue | Sort-Object year -Descending)
    [System.IO.File]::WriteAllText($cataloguePath, (ConvertTo-Json -InputObject $catalogue -Depth 5) + "`n",
        [System.Text.UTF8Encoding]::new($false))
}
