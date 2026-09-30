param(
    [string]$SitePath = (Get-Location).Path,
    [string]$OutputPath = $SitePath,
    [int]$Year = 2026,
    [string[]]$Grades = @('7th', '8th')
)

$ErrorActionPreference = 'Stop'
if ($Year -lt 2006 -or $Year -gt 2100) { throw "Invalid IESA year: $Year" }
if (!(Test-Path -LiteralPath $SitePath -PathType Container)) {
    throw "Site directory does not exist: $SitePath"
}
foreach ($grade in $Grades) {
    if ($grade -notin @('7th', '8th')) { throw "Unsupported grade: $grade" }
}
if (!(Test-Path -LiteralPath $OutputPath -PathType Container)) {
    throw "Output directory does not exist: $OutputPath"
}

function Get-Text([string]$html) {
    $withoutMarkup = [regex]::Replace($html, '(?is)<[^>]+>', ' ')
    return ([System.Net.WebUtility]::HtmlDecode($withoutMarkup) -replace '\s+', ' ').Trim()
}

function Get-Name([string]$html) {
    $name = Get-Text $html
    if ($name -notmatch '^[\p{L}\p{N}][\p{L}\p{N}\s.,''()&/\-]+$' -or
        $name -match '^(?:Winner|Loser)\s+(?:Sectional|Game)\b' -or
        $name.Length -gt 110) { return $null }
    return $name
}

function Same-Name([string]$first, [string]$second) {
    if (!$first -or !$second) { return $false }
    $left = (($first -replace '\s+\(Co-op\)$', '') -replace '\s+', ' ').Trim()
    $right = (($second -replace '\s+\(Co-op\)$', '') -replace '\s+', ' ').Trim()
    return [string]::Equals($left, $right, [StringComparison]::OrdinalIgnoreCase)
}

function Get-CanonicalName([string]$name, [object[]]$candidates, [string]$context) {
    $matches = @($candidates | Where-Object { Same-Name $name $_ })
    if ($matches.Count -ne 1) {
        throw "Unresolved or ambiguous IESA school '$name' in $context (expected one roster match)"
    }
    return [string]$matches[0]
}

function Get-RegionalRosters([string]$grade) {
    $path = Join-Path (Join-Path $SitePath $grade) 'data.js'
    $script = Get-Content -LiteralPath $path -Raw
    $pattern = if ($grade -eq '7th') {
        '(?s)\bvar\s+teams\s*=\s*\[(.*?)\]\s*;\s*return\s+teams\.map'
    } else {
        '(?s)\bvar\s+d\s*=\s*\[(.*?)\]\s*,\s*h\s*='
    }
    $array = [regex]::Match($script, $pattern)
    if (!$array.Success) { throw "Cannot read regional rosters from $path" }
    $groups = [regex]::Matches($array.Groups[1].Value, '(?s)\[(.*?)\]')
    if ($groups.Count -ne 16) { throw "Expected 16 regional rosters in $path" }
    $rosters = @{}
    for ($i = 0; $i -lt 16; $i++) {
        $names = @([regex]::Matches($groups[$i].Groups[1].Value, '"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value })
        if ($names.Count -lt 2) { throw "Empty regional roster $($i + 1) in $path" }
        $rosters["$($i + 1)"] = $names
    }
    return $rosters
}

function Get-Result([string]$html, [string]$url) {
    $result = [regex]::Match($html, '(?is)^\s*<(?:b|strong)>\s*(.*?)\s*</(?:b|strong)>\s*def\.\s*(.*?)\s*,\s*(\d+)\s*-\s*(\d+)\s*(?:<(?:b|strong)>\s*(?:\d*OT)\s*</(?:b|strong)>)?\s*$')
    if (!$result.Success) {
        if ((Get-Text $html) -match '\bdef\.\b|\bdef\.' ) { throw "Unrecognized result at $url" }
        return $null
    }
    $winner = Get-Name $result.Groups[1].Value
    $loser = Get-Name $result.Groups[2].Value
    if (!$winner -or !$loser -or (Same-Name $winner $loser)) {
        throw "Invalid result names ('$winner' / '$loser') at $url"
    }
    if ([int]$result.Groups[3].Value -le [int]$result.Groups[4].Value) {
        throw "Winner's score is not higher at $url"
    }
    return [pscustomobject]@{
        winner = $winner
        loser = $loser
        score = "$($result.Groups[3].Value)-$($result.Groups[4].Value)"
        sourceUrl = $url
    }
}

function Get-OfficialPage([string]$url, [string]$marker) {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $url
    if ($response.StatusCode -ne 200 -or $response.Content -notmatch [regex]::Escape($marker)) {
        throw "Unexpected official page at $url"
    }
    return [string]$response.Content
}

function Get-SectionBlocks([string]$html, [string]$pending, [string]$url) {
    $heading = "(?is)<td\s+class=['""]TableSubtitle['""][^>]*>\s*Sectional\s+(\d+)\b"
    $matches = [regex]::Matches($html, $heading)
    if ($matches.Count -eq 0 -and $html.Contains($pending)) { return @() }
    if ($matches.Count -ne 8) { throw "Expected eight sectionals at $url; found $($matches.Count)" }
    $blocks = @()
    for ($i = 0; $i -lt 8; $i++) {
        $number = [int]$matches[$i].Groups[1].Value
        if ($number -ne $i + 1) { throw "Unexpected sectional number at $url" }
        $end = if ($i -lt 7) { $matches[$i + 1].Index } else { $html.Length }
        $blocks += $html.Substring($matches[$i].Index, $end - $matches[$i].Index)
    }
    return ,$blocks
}

function Read-Regionals([string]$html, [string]$url, [hashtable]$rosters) {
    $results = @{}
    $blocks = Get-SectionBlocks $html 'Sectional Qualifiers are pending.' $url
    for ($s = 0; $s -lt $blocks.Count; $s++) {
        $rows = [regex]::Matches($blocks[$s],
            "(?is)<td\s+class=['""]Links['""][^>]*>\s*<a\s+href=['""][^'""]*Regional=(\d+)[^'""]*['""][^>]*>.*?</a>\s*</td>\s*<td\s+class=['""]ListData['""][^>]*>(.*?)</td>")
        if ($rows.Count -ne 2) { throw "Expected two regional links in sectional $($s + 1) at $url" }
        foreach ($row in $rows) {
            $number = [int]$row.Groups[1].Value
            if ($number -notin @((2 * $s + 1), (2 * $s + 2))) {
                throw "Regional number does not match sectional at $url"
            }
            $result = Get-Result $row.Groups[2].Value $url
            if ($null -ne $result) {
                if ($null -ne $rosters) {
                    $result.winner = Get-CanonicalName $result.winner $rosters["$number"] "Regional $number"
                    $result.loser = Get-CanonicalName $result.loser $rosters["$number"] "Regional $number"
                    if ($result.winner -eq $result.loser) { throw "Duplicate regional teams at $url" }
                }
                $results["$number"] = $result
            }
        }
    }
    return $results
}

function Read-Sectionals([string]$html, [string]$url, [hashtable]$regionals) {
    $results = @{}
    $blocks = Get-SectionBlocks $html 'State Qualifiers are pending.' $url
    for ($s = 0; $s -lt $blocks.Count; $s++) {
        $cells = [regex]::Matches($blocks[$s], "(?is)<td\s+class=['""]ListData['""][^>]*>(.*?)</td>")
        if ($cells.Count -ne 1) { throw "Expected one result cell in sectional $($s + 1) at $url" }
        $result = Get-Result $cells[0].Groups[1].Value $url
        if ($null -eq $result) { continue }
        $a = $regionals["$(2 * $s + 1)"]
        $b = $regionals["$(2 * $s + 2)"]
        if ($null -eq $a -or $null -eq $b -or
            !((Same-Name $result.winner $a.winner) -and (Same-Name $result.loser $b.winner)) -and
            !((Same-Name $result.winner $b.winner) -and (Same-Name $result.loser $a.winner))) {
            throw "Sectional $($s + 1) does not match its regional winners at $url"
        }
        $result.winner = Get-CanonicalName $result.winner @($a.winner, $b.winner) "Sectional $($s + 1)"
        $result.loser = Get-CanonicalName $result.loser @($a.winner, $b.winner) "Sectional $($s + 1)"
        $results["$($s + 1)"] = $result
    }
    return $results
}

function Read-Scoreboard([string]$html, [int]$gradeNumber, [string]$url, [hashtable]$sectionals) {
    $heading = "$gradeNumber" + 'th Grade Class 2A  State Tournament'
    $start = $html.IndexOf($heading, [StringComparison]::OrdinalIgnoreCase)
    if ($start -lt 0) { throw "Missing $heading at $url" }
    $next = [regex]::Match($html.Substring($start + $heading.Length),
        "(?is)<td\s+class=['""]Score-Meet['""][^>]*>")
    $end = if ($next.Success) { $start + $heading.Length + $next.Index } else { $html.Length }
    $scope = $html.Substring($start, $end - $start)
    $games = @{}
    $matchups = @{}
    $rows = [regex]::Matches($scope,
        "(?is)<tr>\s*<td\s+class=['""]ScoreData['""][^>]*>(.*?)</td>\s*<td\s+class=['""]ScoreData-Score['""][^>]*>(.*?)</td>\s*<td\s+class=['""]ScoreData-Row['""][^>]*>(.*?)</td>\s*</tr>")
    if ($rows.Count -ne 8) { throw "Expected eight state games at $url; found $($rows.Count)" }
    foreach ($row in $rows) {
        $position = [regex]::Match($row.Groups[3].Value, '(?i)\bPosition=(\d+)')
        if ($position.Success) {
            $p = [int]$position.Groups[1].Value
        } else {
            # Unplayed games have no INFO link; their order in the official table is 8 through 1.
            $p = 8 - $games.Count
        }
        if ($p -lt 1 -or $p -gt 8 -or $games.ContainsKey("$p")) {
            throw "Duplicate or invalid state position at $url"
        }
        $schools = [regex]::Matches($row.Groups[1].Value,
            "(?is)<td\s+class=['""]ScoreData-BracketSchool['""][^>]*>(.*?)</td>")
        if ($schools.Count -ne 2) { throw "Expected two schools at position $p in $url" }
        $teams = @()
        $victors = @()
        $sectionNumbers = @()
        foreach ($school in $schools) {
            $text = Get-Text $school.Groups[1].Value
            $placeholder = [regex]::Match($text, '^Winner Sectional (\d+)$', 'IgnoreCase')
            $sectionNumbers += $(if ($placeholder.Success) { [int]$placeholder.Groups[1].Value } else { $null })
            $victors += [bool]($school.Groups[1].Value -match '(?i)\balt\s*=\s*[''"]Victor[''"]')
            $teams += $(if ($placeholder.Success -or $text -match '^(Winner|Loser)\s+Game\b') {
                    $null
                } else {
                    Get-Name $school.Groups[1].Value
                })
            if ($text -and !$placeholder.Success -and !$teams[-1] -and $text -notmatch '^(Winner|Loser)\s+Game\b') {
                throw "Unexpected school at position $p in $url"
            }
        }
        if ($p -ge 5) {
            $game = 9 - $p
            $numbers = @()
            for ($i = 0; $i -lt 2; $i++) {
                if ($sectionNumbers[$i]) {
                    $numbers += $sectionNumbers[$i]
                } elseif ($teams[$i]) {
                    $found = @(1..8 | Where-Object {
                        $sectionals.ContainsKey("$_") -and (Same-Name $teams[$i] $sectionals["$_"].winner)
                    })
                    if ($found.Count -ne 1) { throw "Cannot identify sectional for $($teams[$i]) at $url" }
                    $numbers += [int]$found[0]
                }
            }
            if ($numbers.Count -eq 2) {
                if ($numbers[0] -lt 1 -or $numbers[0] -gt 8 -or
                    $numbers[1] -lt 1 -or $numbers[1] -gt 8 -or
                    $numbers[0] -eq $numbers[1]) { throw "Invalid sectional pairing at $url" }
                $matchups["$game"] = $numbers
            }
        }
        $scoreMarkup = $row.Groups[2].Value
        $scoreMatch = [regex]::Match($scoreMarkup, '^\s*(\d+)\s*<br\s*/?>\s*(\d+)\s*$', 'IgnoreCase')
        $finished = (Get-Text $row.Groups[3].Value) -match '^F\s+INFO\b'
        $winner = $null
        $loser = $null
        $scores = @($null, $null)
        if ($finished) {
            if (!$scoreMatch.Success -or !$teams[0] -or !$teams[1] -or
                (Same-Name $teams[0] $teams[1]) -or
                [int]$scoreMatch.Groups[1].Value -eq [int]$scoreMatch.Groups[2].Value -or
                ($victors[0] -eq $victors[1])) { throw "Inconsistent completed game at position $p in $url" }
            $scores = @([int]$scoreMatch.Groups[1].Value, [int]$scoreMatch.Groups[2].Value)
            $winningIndex = if ($scores[0] -gt $scores[1]) { 0 } else { 1 }
            if (!$victors[$winningIndex]) { throw "Victor icon disagrees with score at position $p in $url" }
            $winner = $teams[$winningIndex]
            $loser = $teams[1 - $winningIndex]
        } elseif ($scoreMatch.Success -or $victors[0] -or $victors[1]) {
            throw "Unfinished game has score or Victor at position $p in $url"
        }
        $games["$p"] = [pscustomobject]@{
            teams = @($teams)
            scores = @($scores)
            winner = $winner
            loser = $loser
            sourceUrl = $url
        }
    }
    foreach ($p in 8..1) {
        $game = $games["$p"]
        $prior = @()
        if ($p -ge 5 -and $matchups.ContainsKey("$(9 - $p)")) {
            $prior = @($matchups["$(9 - $p)"] | ForEach-Object { $sectionals["$_"] })
        } elseif ($p -eq 4) {
            $prior = @($games['8'], $games['7'])
        } elseif ($p -eq 3) {
            $prior = @($games['6'], $games['5'])
        } elseif ($p -eq 2) {
            $prior = @($games['4'], $games['3'])
        } elseif ($p -eq 1) {
            $prior = @($games['4'], $games['3'])
        }
        if ($p -eq 2 -and $prior.Count -eq 2) {
            foreach ($i in 0..1) {
                if ($prior[$i].loser -and $game.teams[$i] -and
                    !(Same-Name $game.teams[$i] $prior[$i].loser)) {
                    throw "Third-place participant disagrees with semifinal at $url"
                }
            }
        } elseif ($prior.Count -eq 2) {
            foreach ($i in 0..1) {
                if ($prior[$i].winner -and $game.teams[$i] -and
                    !(Same-Name $game.teams[$i] $prior[$i].winner)) {
                    throw "State participant disagrees with prior round at $url"
                }
            }
        }
        if ($p -ge 5 -and $game.winner -and $prior.Count -ne 2) {
            throw "Completed quarterfinal lacks a verified sectional pairing at $url"
        }
        if ($prior.Count -eq 2) {
            for ($i = 0; $i -lt 2; $i++) {
                $expected = if ($p -eq 2) { $prior[$i].loser } else { $prior[$i].winner }
                if ($expected -and $game.teams[$i]) {
                    $game.teams[$i] = $expected
                }
            }
            if ($game.winner) {
                $winnerIndex = if (Same-Name $game.winner $game.teams[0]) { 0 } else { 1 }
                $game.winner = $game.teams[$winnerIndex]
                $game.loser = $game.teams[1 - $winnerIndex]
            }
        }
    }
    $numberedGames = @{}
    foreach ($p in 1..8) { $numberedGames["$(9 - $p)"] = $games["$p"] }
    return [pscustomobject]@{ games = $numberedGames; matchups = $matchups }
}

# Collect every requested grade before writing anything, so a failed fetch cannot replace caches.
$captures = @{}
foreach ($grade in $Grades) {
    $number = [int]$grade.Substring(0, 1)
    $class = "$number-2A"
    $base = 'https://www.iesa.org/activities/gbk/'
    $regionalUrl = "${base}qualifiers_Sectional.asp?Year=$Year&Class=$class"
    $sectionalUrl = "${base}qualifiers_State.asp?Year=$Year&Class=$class"
    $stateUrl = "${base}scoreboards/index.asp?Year=$Year&Class=$class"
    $regionalHtml = Get-OfficialPage $regionalUrl "$Year Class $class Regional Champions/Sectional Matchups"
    $sectionalHtml = Get-OfficialPage $sectionalUrl "$Year Class $class Sectional Champions/State Qualifiers"
    $stateHtml = Get-OfficialPage $stateUrl "$($number)th Grade Class 2A  State Tournament"
    $rosters = if ($Year -eq 2026) { Get-RegionalRosters $grade } else { $null }
    $regionals = Read-Regionals $regionalHtml $regionalUrl $rosters
    $sectionals = Read-Sectionals $sectionalHtml $sectionalUrl $regionals
    $state = Read-Scoreboard $stateHtml $number $stateUrl $sectionals
    $captures[$grade] = [pscustomobject]@{
        updatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        year = $Year
        grade = $grade
        regionals = $regionals
        sectionals = $sectionals
        quarterfinalMatchups = $state.matchups
        games = $state.games
    }
}

foreach ($grade in $Grades) {
    $json = $captures[$grade] | ConvertTo-Json -Depth 8
    $json | Set-Content -LiteralPath (Join-Path $OutputPath "bracket-$grade.json") -Encoding UTF8
    ("window.iesaBracketCache = " + $json + ";") |
        Set-Content -LiteralPath (Join-Path $OutputPath "bracket-$grade.js") -Encoding UTF8
    Write-Output "Updated $grade $Year bracket: $($captures[$grade].regionals.Count) regionals, $($captures[$grade].sectionals.Count) sectionals."
}
