param(
    # Defaults to every state-only year of this site's sport (sport.json firstYear..earlyLast).
    [ValidateRange(1930, 2010)][int[]]$Years,
    [string]$OutputRoot = $PSScriptRoot,
    [ValidateSet('A', 'AA')][string]$ClassName = 'A',
    [switch]$CatalogueOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '2026\IesaRequest.ps1')
. (Join-Path $PSScriptRoot 'IesaSitePages.ps1')
# Eras differ by sport (sport.json): one combined 7th/8th bracket through combinedLast,
# grade brackets without classes through gradeOnlyLast, then Class A and AA.
$combinedLast = [int]$IesaSport.combinedLast
$gradeOnlyLast = [int]$IesaSport.gradeOnlyLast
if (!$Years) { $Years = [int]$IesaSport.firstYear..[int]$IesaSport.earlyLast }
if ($ClassName -eq 'AA' -and @($Years | Where-Object { $_ -le $gradeOnlyLast }).Count) {
    throw "Class AA began in $($gradeOnlyLast + 1)."
}
if (!(Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    throw "Output root does not exist: $OutputRoot"
}

function Get-Text([string]$markup) {
    ([System.Net.WebUtility]::HtmlDecode([regex]::Replace($markup, '(?is)<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
}

function Get-Page([string]$url, [string]$expected) {
    $response = Invoke-IesaPage $url
    if ($response.StatusCode -ne 200 -or $response.Content -notmatch [regex]::Escape($expected)) {
        throw "Unexpected IESA page: $url"
    }
    [string]$response.Content
}

function Get-StateGames([string]$html, [int]$year, [string]$code) {
    $champion = [regex]::Match($html, "(?is)<td\s+class=['""]Score-Champ['""][^>]*>(.*?)</td>")
    $meet = [regex]::Match($html, "(?is)<td\s+class=['""]Score-Meet['""][^>]*>(.*?)</td>")
    if (!$champion.Success -or !$meet.Success) { throw "$year $code has no state championship" }
    # The last heading only ends the championship block; later years call it "Final Win/Loss Records".
    $headings = @([regex]::Matches($html, "(?is)<td\s+class=['""]Score-Subtitle['""][^>]*>\s*(First Round|Quarterfinals|Semifinals|Third Place|State Championship|Final Results|Final Win/Loss Records)\s*</td>"))
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
        if ($line -notmatch '(?i)^(.+?)\s*vs\.\s+(.+)$') {
            throw "$year $code unexpected sectional pairing: $line"
        }
        # IESA occasionally appends a game result after a school's record
        # ("Joliet Washington (15-0) Minooka def. Wilmington Stevens 40-39").
        $teams = @($Matches[1].Trim(), $Matches[2].Trim()) | ForEach-Object { $_ -replace '^(.+?\(\d+-\d+\))\s+\S.*$', '$1' }
        $pairings += [ordered]@{ teams = @($teams) }
    }
    return $pairings
}

if (!$CatalogueOnly) {
foreach ($year in $Years) {
    $grades = if ($year -le $combinedLast) { @('combined') } else { @('7th', '8th') }
    foreach ($grade in $grades) {
        $code = if ($grade -eq 'combined') { '' } elseif ($year -le $gradeOnlyLast) {
            if ($grade -eq '7th') { '7' } else { '8' }
        } elseif ($grade -eq '7th') { "7$ClassName" } else { "8$ClassName" }
        $url = "$IesaSportUrl/index.asp?Year=$year"
        if ($code) { $url += "&Class=$code" }
        $html = Get-Page $url 'ScoreData-BracketSchool'
        $state = Get-StateGames $html $year $code
        $label = if ($grade -eq 'combined') { 'Combined 7th/8th' } elseif ($year -le $gradeOnlyLast) {
            "$grade Grade"
        } else { "$grade Grade Class $ClassName" }
        $expectedMeet = if ($grade -eq 'combined') { 'State Tournament' } elseif ($year -le $gradeOnlyLast) {
            "Class $(if ($grade -eq '7th') { '7' } else { '8' }) State Tournament"
        } else { "Class $(if ($grade -eq '7th') { '7' } else { '8' })$ClassName State Tournament" }
        if ((Get-Text ([regex]::Match($html, "(?is)<td\s+class=['""]Score-Meet['""][^>]*>(.*?)</td>").Groups[1].Value)) -notmatch
            "^$([regex]::Escape($expectedMeet))\b") {
            throw "$year $grade returned the wrong state tournament"
        }
        $pairings = @()
        $pairingUrl = $null
        if ([int]$IesaSport.earlyPairingsFrom -and $year -ge [int]$IesaSport.earlyPairingsFrom) {
            $pairingUrl = "$IesaSportUrl/qualifiers_Sectional.asp?Year=$year&Class=$code"
            $pairings = @(Get-SectionalPairings (Get-Page $pairingUrl 'Champion') $year $code)
        }
        $data = [ordered]@{
            year = $year
            grade = $grade
            label = $label
            className = if ($year -gt $gradeOnlyLast) { $ClassName } else { $null }
            source = $url
            venue = $state.venue
            champion = $state.champion
            rounds = $state.rounds
            sectionals = $pairings
            sectionalSource = $pairingUrl
        }
        $folder = Join-Path (Join-Path $OutputRoot (Get-IesaClassFolder $OutputRoot $year $ClassName)) $grade
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        $json = ConvertTo-Json -InputObject $data -Depth 15 -Compress
        [System.IO.File]::WriteAllText((Join-Path $folder 'data.js'), "window.earlyTournamentData = $json;`n",
            [System.Text.UTF8Encoding]::new($false))
        Write-Output "$year $grade : $($state.champion)"
    }
    if ($ClassName -eq 'AA') { Add-IesaCatalogueClass $OutputRoot $year 'AA' }
    Write-IesaClassPages $OutputRoot $year $(if ($year -gt $gradeOnlyLast) { $ClassName } else { '' })
}
}

$cataloguePath = Join-Path $OutputRoot 'seasons.json'
if ($ClassName -eq 'A' -and (Test-Path -LiteralPath $cataloguePath)) {
    foreach ($year in $Years) {
        $grades = if ($year -le $combinedLast) { @('combined') } else { @('7th', '8th') }
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
    $previous = @(Get-Content -LiteralPath $cataloguePath -Raw | ConvertFrom-Json | ForEach-Object { $_ })
    foreach ($year in $Years) {
        $old = $previous | Where-Object { $_.year -eq $year -and $_.PSObject.Properties['classes'] } | Select-Object -First 1
        $catalogue += [pscustomobject]@{
            year = $year
            className = if ($year -le $gradeOnlyLast) { $null } else { 'A' }
            gradeMode = if ($year -le $combinedLast) { 'combined' } else { 'separate' }
            archived = $true
        }
        if ($old) { $catalogue[-1] | Add-Member -NotePropertyName classes -NotePropertyValue @($old.classes) }
    }
    $catalogue = @($catalogue | Sort-Object year -Descending)
    [System.IO.File]::WriteAllText($cataloguePath, (ConvertTo-Json -InputObject $catalogue -Depth 5) + "`n",
        [System.Text.UTF8Encoding]::new($false))
}
