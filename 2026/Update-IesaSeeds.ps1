param(
    [int]$Year = 2026,
    [ValidateSet('1A', '2A', '3A', '4A')][string]$ClassName = '2A',
    [string]$SitePath = (Get-Location).Path,
    [string]$OutputPath = $SitePath,
    [string[]]$Grades = @('7th', '8th'),
    [switch]$AllowBracketParticipants
)

$ErrorActionPreference = 'Stop'
if ($Year -lt 2006 -or $Year -gt 2100) { throw "Invalid IESA year: $Year" }
if (!(Test-Path -LiteralPath $SitePath -PathType Container)) { throw "Missing site directory: $SitePath" }
if (!(Test-Path -LiteralPath $OutputPath -PathType Container)) { throw "Missing output directory: $OutputPath" }
foreach ($grade in $Grades) {
    if ($grade -notin @('7th', '8th')) { throw "Unsupported grade: $grade" }
}

function Get-Text([string]$html) {
    ([System.Net.WebUtility]::HtmlDecode([regex]::Replace($html, '(?is)<[^>]+>', '')) -replace '\s+', ' ').Trim()
}

function Get-Key([string]$name) {
    (($name -replace '\s+\(Co-op\)$', '' -replace '\s+', ' ').Trim()).ToLowerInvariant()
}

function Get-Roster([string]$grade) {
    $dataPath = Join-Path $SitePath "$grade\data.json"
    if (Test-Path -LiteralPath $dataPath) {
        $data = Get-Content -Raw -LiteralPath $dataPath | ConvertFrom-Json
        if ($data.year -ne $Year -or $data.className -ne $ClassName -or $data.regionals.Count -ne 16) {
            throw "Invalid $grade regional assignment data at $dataPath"
        }
        $roster = @($data.regionals | ForEach-Object {
            if (@($_.teams).Count -lt 2) { throw "Empty $grade regional roster" }
            ,@($_.teams)
        })
        return ,$roster
    }
    $script = Get-Content -Raw -LiteralPath (Join-Path $SitePath "$grade\data.js")
    $expression = if ($grade -eq '7th') {
        '(?s)\bvar\s+teams\s*=\s*\[(.*?)\]\s*;\s*return\s+teams\.map'
    } else {
        '(?s)\bvar\s+d\s*=\s*\[(.*?)\]\s*,\s*h\s*='
    }
    $match = [regex]::Match($script, $expression)
    if (!$match.Success) { throw "Unable to parse $grade roster" }
    $groups = @([regex]::Matches($match.Groups[1].Value, '(?s)\[([^\[\]]*)\]'))
    if ($groups.Count -ne 16) { throw "$grade roster has $($groups.Count) regionals, expected 16" }
    $roster = @()
    foreach ($group in $groups) {
        $names = @([regex]::Matches($group.Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        if (!$names.Count) { throw "Empty $grade roster regional" }
        $roster += ,$names
    }
    return ,$roster
}

function Get-Game([object[]]$entries, [bool]$bye = $false) {
    $names = @($entries | ForEach-Object { $_.name })
    $scores = @($entries | ForEach-Object { $_.score })
    $winner = $null
    if ($bye) {
        $winner = $names[0]
    } elseif ($null -ne $scores[0] -and $null -ne $scores[1] -and $scores[0] -ne $scores[1]) {
        $winner = $names[([int]($scores[1] -gt $scores[0]))]
    }
    [pscustomobject]@{ teams = $names; scores = $scores; winner = $winner; bye = $bye }
}

function Get-StageEntry([object]$entry, [hashtable]$names) {
    if ($entry.name -match '^Winner Game \d+$') {
        if ($null -ne $entry.score) { throw "placeholder $($entry.name) has a score" }
        return [pscustomobject]@{ name = $null; score = $null }
    }
    $key = Get-Key $entry.name
    if (!$names.ContainsKey($key)) { throw "unknown published bracket school $($entry.name)" }
    return [pscustomobject]@{ name = $names[$key]; score = $entry.score }
}

function Get-Rounds([object[]]$rows, [hashtable]$names) {
    if ($rows.Count -notin @(4, 8)) { throw "unexpected $($rows.Count)-slot bracket" }
    $first = @()
    foreach ($row in $rows) {
        $entry = $row[0]
        if ($entry.name -eq 'BYE') {
            $first += [pscustomobject]@{ name = $null; score = $null }
        } else {
            $key = Get-Key ($entry.name -replace '\s+\(\d+(?:st|nd|rd|th) Seed\)$', '')
            if (!$names.ContainsKey($key)) { throw "unrecognized first-round team $($entry.name)" }
            $first += [pscustomobject]@{ name = $names[$key]; score = $entry.score }
        }
    }
    $round1 = @()
    if ($rows.Count -eq 4) {
        foreach ($team in $first) {
            $round1 += Get-Game @(
                [pscustomobject]@{ name = $team.name; score = $null },
                [pscustomobject]@{ name = $null; score = $null }
            ) $true
        }
        $round2 = @(
            (Get-Game @($first[0], $first[1])),
            (Get-Game @($first[2], $first[3]))
        )
        $pair = @()
        foreach ($position in @(1, 2)) {
            if ($rows[$position].Count -lt 2) { throw "missing finalist at slot $position" }
            $pair += Get-StageEntry $rows[$position][1] $names
        }
        $round3 = @(Get-Game $pair)
        for ($i = 0; $i -lt 2; $i++) {
            if ($null -ne $round2[$i].winner -and $null -ne $round3[0].teams[$i] -and
                $round2[$i].winner -ne $round3[0].teams[$i]) {
                throw "semifinal winner does not advance"
            }
        }
        return ,@($round1, $round2, $round3)
    }
    for ($i = 0; $i -lt 8; $i += 2) {
        $pair = @($first[$i], $first[$i + 1])
        if ($null -eq $pair[0].name -or ($null -eq $pair[1].name -and $null -eq $pair[0].name)) {
            throw "invalid BYE position in first round"
        }
        $round1 += Get-Game $pair ($null -eq $pair[1].name)
    }
    $round2 = @()
    foreach ($positions in @(@(1, 2), @(5, 6))) {
        $pair = @()
        foreach ($position in $positions) {
            if ($rows[$position].Count -lt 2) { throw "missing semifinal entry at slot $position" }
            $pair += Get-StageEntry $rows[$position][1] $names
        }
        $round2 += Get-Game $pair
    }
    $pair = @()
    foreach ($position in @(3, 4)) {
        if ($rows[$position].Count -lt 2) { throw "missing final entry at slot $position" }
        $pair += Get-StageEntry $rows[$position][1] $names
    }
    $round3 = @(Get-Game $pair)
    for ($i = 0; $i -lt 4; $i++) {
        $next = $round2[[int][math]::Floor($i / 2)].teams[$i % 2]
        if ($null -ne $round1[$i].winner -and $null -ne $next -and $round1[$i].winner -ne $next) {
            throw "first-round winner does not advance"
        }
    }
    for ($i = 0; $i -lt 2; $i++) {
        if ($null -ne $round2[$i].winner -and $null -ne $round3[0].teams[$i] -and
            $round2[$i].winner -ne $round3[0].teams[$i]) {
            throw "semifinal winner does not advance"
        }
    }
    return ,@($round1, $round2, $round3)
}

$captures = @{}
$failures = @()
foreach ($grade in $Grades) {
    $level = $grade.Substring(0, 1)
    $url = "https://www.iesa.org/activities/gbk/brackets_Regional_$level.asp?Year=$Year&Class=$level-$ClassName"
    try {
        $hasRoster = (Test-Path -LiteralPath (Join-Path $SitePath "$grade\data.json") -PathType Leaf) -or
            (Split-Path $SitePath -Leaf) -eq "$Year"
        $roster = if ($hasRoster -and !$AllowBracketParticipants) { Get-Roster $grade } else { $null }
        $html = (Invoke-WebRequest -UseBasicParsing -Uri $url).Content
        $headings = @([regex]::Matches($html, "(?is)<td\s+class=['""]TableSubtitle['""]>\s*Class $level-$ClassName Regional (\d+)\s*</td>"))
        if ($headings.Count -ne 16) { throw "expected 16 regional headings, got $($headings.Count)" }
        $brackets = [ordered]@{}
        for ($r = 0; $r -lt 16; $r++) {
            $number = $r + 1
            if ([int]$headings[$r].Groups[1].Value -ne $number) { throw "missing or duplicate regional $number" }
            $end = if ($r -lt 15) { $headings[$r + 1].Index } else { $html.Length }
            $section = $html.Substring($headings[$r].Index, $end - $headings[$r].Index)
            $hostMatch = [regex]::Match($section, '(?is)(?:Regional Host|Host):\s*</b>\s*(.*?)</td>')
            if (!$hostMatch.Success) {
                $hostMatch = [regex]::Match($section, '(?is)(?:Regional Host|Host):\s*([^<]+)</td>')
            }
            $regionalHost = if ($hostMatch.Success) { Get-Text $hostMatch.Groups[1].Value } else { $null }
            $rows = @()
            $gameInfo = @()
            foreach ($row in [regex]::Matches($section, '(?is)<tr\b[^>]*>(.*?)</tr>')) {
                $info = [regex]::Match($row.Groups[1].Value,
                    "(?is)<td\b[^>]*class=['""]Info['""][^>]*>(.*?)</td>")
                if ($info.Success) { $gameInfo += (Get-Text $info.Groups[1].Value) }
                $schools = @()
                foreach ($cell in [regex]::Matches($row.Groups[1].Value, '(?is)<td\b[^>]*class=[''"](?:Bracket-School|ListData)[''"][^>]*>(.*?)</td>\s*(?:<td\b[^>]*class=[''"]Bracket-Score[''"][^>]*>(.*?)</td>)?')) {
                    $name = Get-Text $cell.Groups[1].Value
                    $scoreText = Get-Text $cell.Groups[2].Value
                    if ($scoreText -and $scoreText -notmatch '^\d+$') { throw "regional ${number}: malformed score $scoreText" }
                    $score = if ($scoreText) { [int]$scoreText } else { $null }
                    $schools += [pscustomobject]@{ name = $name; score = $score }
                }
                if ($schools.Count) { $rows += ,$schools }
            }
            if (!$rows.Count) { throw "regional ${number}: missing bracket schools" }
            $seeds = @()
            $labels = @()
            foreach ($row in $rows) {
                $first = $row[0].name
                if ($first -match '^(.+?)\s+\((\d+)(?:st|nd|rd|th) Seed\)$') {
                    $seeds += [pscustomobject]@{ seed = [int]$Matches[2]; team = $Matches[1] }
                } elseif ($first -ne 'BYE') {
                    $labels += $first
                }
            }
            $source = "$url&Regional=$number"
            if (!$seeds.Count) {
                if (@($labels | Where-Object { $_ -notmatch '^\d+(?:st|nd|rd|th) Seed$|^Winner Game \d+$' }).Count) {
                    throw "regional ${number}: unseeded school names instead of template placeholders"
                }
                $brackets["$number"] = [pscustomobject]@{
                    seeds = @(); rounds = @(); sourceUrl = $source; host = $regionalHost
                }
                continue
            }
            if ($rows.Count -notin @(4, 8)) {
                throw "regional ${number}: unexpected $($rows.Count)-slot bracket"
            }
            $byeCount = @($rows | Where-Object { $_[0].name -eq 'BYE' }).Count
            $missingFirstSeed = $Year -eq 2008 -and $ClassName -eq '1A' -and
                $grade -eq '8th' -and $number -eq 10 -and $rows[0][0].name -eq '1st Seed' -and
                $seeds.Count -eq 5 -and $byeCount -eq 2 -and $labels.Count -eq 1 -and
                $labels[0] -eq '1st Seed'
            if ($seeds.Count + $byeCount + [int]$missingFirstSeed -ne $rows.Count) {
                throw "regional ${number}: seed/BYE count does not match bracket slots"
            }
            if ($labels.Count -and !$missingFirstSeed) {
                throw "regional ${number}: mixed seeded and placeholder slots: $($labels -join ', ')"
            }
            $byName = @{}
            $bySeed = @{}
            foreach ($seed in $seeds) {
                $key = Get-Key $seed.team
                if (!$key -or $byName.ContainsKey($key) -or $bySeed.ContainsKey($seed.seed)) {
                    throw "regional ${number}: duplicate or blank seed/team"
                }
                if ($roster) {
                    $matches = @($roster[$r] | Where-Object { (Get-Key $_) -eq $key })
                    if ($matches.Count -eq 1) {
                        $seed.team = $matches[0]
                    } elseif ($matches.Count -gt 1 -or !$AllowBracketParticipants) {
                        throw "regional ${number}: $($seed.team) has $($matches.Count) roster matches"
                    }
                }
                $byName[$key] = $seed.team
                $bySeed[$seed.seed] = $true
            }
            for ($i = $(if ($missingFirstSeed) { 2 } else { 1 });
                $i -le $seeds.Count + [int]$missingFirstSeed; $i++) {
                if (!$bySeed.ContainsKey($i)) { throw "regional ${number}: nonsequential seeds (missing $i)" }
            }
            if ($roster -and !$AllowBracketParticipants -and $seeds.Count -ne $roster[$r].Count) {
                throw "regional ${number}: $($seeds.Count) seeded schools but $($roster[$r].Count) roster schools"
            }
            $orderedSeeds = @($seeds | Sort-Object seed)
            $rounds = @()
            if (!$missingFirstSeed) {
                try { $rounds = Get-Rounds $rows $byName }
                catch {
                    if ($_.Exception.Message -match '^unknown published bracket school ') { throw }
                    Write-Warning "$grade regional ${number}: rounds omitted: $($_.Exception.Message)"
                }
            }
            if ($rounds.Count -eq 3) {
                $positions = if ($rows.Count -eq 8) {
                    @(@(0, 0), @(1, 0), @(0, 1), @(2, 0),
                        @(0, 2), @(1, 1), @(0, 3))
                } else {
                    @(@(1, 0), @(2, 0), @(1, 1))
                }
                if ($gameInfo.Count -ne $positions.Count -and
                    @($gameInfo | Where-Object { $_ -match '\b(?:FORFEIT|OT)\b' }).Count) {
                    throw "regional ${number}: cannot align annotated game info rows"
                }
                for ($i = 0; $i -lt $positions.Count -and $gameInfo.Count -eq $positions.Count; $i++) {
                    $annotation = if ($gameInfo[$i] -match '\bFORFEIT\b') { 'FORFEIT' }
                        elseif ($gameInfo[$i] -match '\bOT\b') { 'OT' } else { $null }
                    if ($annotation) {
                        $position = $positions[$i]
                        $rounds[$position[0]][$position[1]] |
                            Add-Member -NotePropertyName annotation -NotePropertyValue $annotation
                    }
                }
            }
            $brackets["$number"] = [pscustomobject]@{
                seeds = $orderedSeeds; rounds = $rounds; sourceUrl = $source
                host = $regionalHost; missingSeed = $(if ($missingFirstSeed) { 1 } else { $null })
            }
        }
        $captures[$grade] = [pscustomobject]@{
            updatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm')
            year = $Year
            grade = $grade
            regionalBrackets = $brackets
        }
        Write-Host "$grade`: parsed 16 regionals; $(@($brackets.Values | Where-Object { $_.seeds.Count }).Count) seeded"
    } catch {
        $failure = "Unable to refresh $grade from $url; existing $grade capture untouched: $($_.Exception.Message)"
        Write-Warning $failure
        $failures += $failure
    }
}

foreach ($grade in $Grades) {
    if (!$captures.ContainsKey($grade)) { continue }
    $json = $captures[$grade] | ConvertTo-Json -Depth 10
    $json | Set-Content -LiteralPath (Join-Path $OutputPath "regional-seeds-$grade.json") -Encoding UTF8
    ("window.iesaRegionalSeedCache = " + $json + ";") |
        Set-Content -LiteralPath (Join-Path $OutputPath "regional-seeds-$grade.js") -Encoding UTF8
}
if ($failures.Count) { throw ($failures -join [Environment]::NewLine) }
