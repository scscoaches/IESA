param(
    [string]$SitePath = (Get-Location).Path,
    [string]$OutputPath = $SitePath,
    [int]$Year = 2026,
    [ValidateSet('A', 'AA', '1A', '2A', '3A', '4A')][string]$ClassName = '2A',
    [string[]]$Grades = @('7th', '8th')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'IesaRequest.ps1')
if ($Year -lt 2002 -or $Year -gt 2100 -or (($Year -le 2005) -ne ($ClassName -in @('A', 'AA')))) {
    throw "Invalid IESA year/class: $Year $ClassName"
}
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
    $left = (($first -replace '(?i)\s+\(Co-?op\)$|\s+UGC$|(?<=Michael)''s$', '') -replace '\s+', ' ').Trim()
    $right = (($second -replace '(?i)\s+\(Co-?op\)$|\s+UGC$|(?<=Michael)''s$', '') -replace '\s+', ' ').Trim()
    if ($Year -eq 2002 -and $ClassName -eq 'A') {
        $left = $left -replace '(?i)^Ogden PVO South$', 'Ogden'
        $right = $right -replace '(?i)^Ogden PVO South$', 'Ogden'
    }
    return [string]::Equals($left, $right, [StringComparison]::OrdinalIgnoreCase)
}

function Get-CanonicalName([string]$name, [object[]]$candidates, [string]$context) {
    $matches = @($candidates | Where-Object { Same-Name $name $_ })
    if ($matches.Count -ne 1) {
        throw "Unresolved or ambiguous IESA school '$name' in $context (expected one roster match)"
    }
    return [string]$matches[0]
}

# IESA occasionally prefixes a school with its town on one page only
# ("Metamora Germantown Hills" / "Germantown Hills"). Used only as a fallback
# when no exact match exists, and only a single candidate is accepted.
function Similar-Name([string]$first, [string]$second) {
    if (Same-Name $first $second) { return $true }
    if (!$first -or !$second) { return $false }
    $a = (($first -replace '(?i)\s+\(Co-?op\)$', '') -replace '\s+', ' ').Trim()
    $b = (($second -replace '(?i)\s+\(Co-?op\)$', '') -replace '\s+', ' ').Trim()
    # "Mansfield Blue Ridge JHS" / "Mansfield Blue Ridge IJHS"
    $suffix = '(?i)\s+(?:IJHS|JHS|IJH|JH|MS|GS|ES|UGC)$'
    if (($a -replace $suffix, '') -ieq ($b -replace $suffix, '')) { return $true }
    $short, $long = if ($a.Length -le $b.Length) { $a, $b } else { $b, $a }
    return @($short -split ' ').Count -ge 2 -and
        $long.EndsWith(" $short", [StringComparison]::OrdinalIgnoreCase)
}

function Get-RegionalRosters([string]$grade) {
    $dataPath = Join-Path (Join-Path $SitePath $grade) 'data.json'
    if (Test-Path -LiteralPath $dataPath) {
        $data = Get-Content -Raw -LiteralPath $dataPath | ConvertFrom-Json
        $expected = if ($Year -le 2005) { 32 } else { 16 }
        if ($data.year -ne $Year -or $data.className -ne $ClassName -or $data.regionals.Count -ne $expected) {
            throw "Invalid $grade regional assignment data at $dataPath"
        }
        $rosters = @{}
        for ($i = 0; $i -lt $expected; $i++) {
            $names = @($data.regionals[$i].teams)
            if ($names.Count -lt 2 -and !$data.regionals[$i].PSObject.Properties['canceled']) {
                throw "Empty regional roster $($i + 1) at $dataPath"
            }
            $rosters["$($i + 1)"] = $names
        }
        return $rosters
    }
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
    $markup = [System.Net.WebUtility]::HtmlDecode($html)
    $suffix = '\s*def\.\s*(?<loser>.*?)\s*,?\s*(?:(?<winScore>\d+)\s*-\s*(?<loseScore>\d+)|(?<partialScore>\d+\s*-)|(?<missing>-))\s*(?:<(?:b|strong)>\s*(?:\d+\s*)?OT\s*</(?:b|strong)>|\(+(?:\d+\s*)?OT\)+)?\s*$'
    $result = [regex]::Match($markup,
        '(?is)^\s*<(?:b|strong)>\s*(?<winner>.*?)\s*</(?:b|strong)>' + $suffix)
    if (!$result.Success) {
        $result = [regex]::Match($markup, '(?is)^\s*(?<winner>[^<]+?)' + $suffix)
    }
    $unscored = $false
    if (!$result.Success -and $Year -le 2008) {
        $result = [regex]::Match($markup,
            '(?is)^\s*<(?:b|strong)>\s*(?<winner>.*?)\s*</(?:b|strong)>\s*def\.\s*(?<loser>[^<,]+?)\s*$')
        if (!$result.Success) { $result = [regex]::Match($markup,
            '(?is)^\s*(?<winner>[^<]+?)\s+def\.\s*(?<loser>[^<,]+?)\s*$')
        }
        $unscored = $result.Success
    }
    if (!$result.Success) {
        if ((Get-Text $html) -match '\bdef\.\b|\bdef\.' ) { throw "Unrecognized result at $url" }
        return $null
    }
    $winner = Get-Name $result.Groups['winner'].Value
    $loser = Get-Name $result.Groups['loser'].Value
    if (!$winner -or !$loser -or (Same-Name $winner $loser)) {
        throw "Invalid result names ('$winner' / '$loser') at $url"
    }
    if (!$unscored -and !$result.Groups['missing'].Success -and
        !$result.Groups['partialScore'].Success -and
        [int]$result.Groups['winScore'].Value -le [int]$result.Groups['loseScore'].Value) {
        throw "Winner's score is not higher at $url"
    }
    return [pscustomobject]@{
        winner = $winner
        loser = $loser
        score = if ($unscored -or $result.Groups['missing'].Success -or
            $result.Groups['partialScore'].Success) { $null } else {
            "$($result.Groups['winScore'].Value)-$($result.Groups['loseScore'].Value)"
        }
        sourceUrl = $url
    }
}

function Get-OfficialPage([string]$url, [string]$marker) {
    $response = Invoke-IesaPage $url
    if ($response.StatusCode -ne 200 -or $response.Content -notmatch [regex]::Escape($marker)) {
        throw "Unexpected official page at $url"
    }
    return [string]$response.Content
}

function Get-SectionBlocks([string]$html, [string]$pending, [string]$url) {
    $heading = "(?is)<td\s+class=['""]TableSubtitle['""][^>]*>\s*(?:<b>\s*)?Sectional\s+(\d+)\b"
    $expected = if ($Year -le 2005) { 16 } else { 8 }
    $matches = [regex]::Matches($html, $heading)
    if ($matches.Count -eq 0 -and $html.Contains($pending)) { return @() }
    if ($matches.Count -ne $expected) { throw "Expected $expected sectionals at $url; found $($matches.Count)" }
    $blocks = @()
    for ($i = 0; $i -lt $expected; $i++) {
        $number = [int]$matches[$i].Groups[1].Value
        if ($number -ne $i + 1) { throw "Unexpected sectional number at $url" }
        $end = if ($i -lt $expected - 1) { $matches[$i + 1].Index } else { $html.Length }
        $blocks += $html.Substring($matches[$i].Index, $end - $matches[$i].Index)
    }
    return ,$blocks
}

# The regional final as drawn on IESA's published regional bracket, if captured.
function Get-PublishedRegionalFinal([string]$grade, [int]$number) {
    $path = Join-Path $SitePath "regional-seeds-$grade.json"
    if (!(Test-Path -LiteralPath $path)) { return $null }
    $bracket = (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json).regionalBrackets."$number"
    $rounds = @($bracket.rounds)
    if ($rounds.Count -ne 3) { return $null }
    $final = @($rounds[2])[0]
    if (!$final -or !$final.winner -or @($final.teams).Count -ne 2 -or @($final.scores).Count -ne 2 -or
        $null -eq $final.scores[0] -or $null -eq $final.scores[1]) { return $null }
    return $final
}

function Read-Regionals([string]$html, [string]$url, [hashtable]$rosters) {
    $results = @{}
    $records = @{}
    $blocks = Get-SectionBlocks $html 'Sectional Qualifiers are pending.' $url
    for ($s = 0; $s -lt $blocks.Count; $s++) {
        $rows = [regex]::Matches($blocks[$s],
            "(?is)<td\s+class=['""]Links['""][^>]*>\s*(?:<a\s+href=['""][^'""]*(?:Regional=|#Regional_)(?<linked>\d+)[^'""]*['""][^>]*>.*?</a>|Regional\s+(?<plain>\d+))\s*</td>\s*<td\s+class=['""]ListData['""][^>]*>(?<result>.*?)</td>")
        if ($rows.Count -gt 2 -or ($Year -ge 2006 -and $rows.Count -ne 2)) {
            throw "Expected regional results in sectional $($s + 1) at $url"
        }
        foreach ($row in $rows) {
            $number = [int]$(if ($row.Groups['linked'].Success) { $row.Groups['linked'].Value } else { $row.Groups['plain'].Value })
            if ($number -notin @((2 * $s + 1), (2 * $s + 2))) {
                throw "Regional number does not match sectional at $url"
            }
            if ($Year -eq 2008 -and $ClassName -eq '1A' -and $number -eq 10 -and
                (Get-Text $row.Groups['result'].Value) -match '^def\.\s+Atwood-Hammond\s*,\s*28-20$') {
                continue
            }
            $resultText = Get-Text $row.Groups['result'].Value
            $blank = [regex]::Match($resultText, '^def\.\s+(?<loser>.+?)\s*,\s*(?<win>\d+)\s*-\s*(?<lose>\d+)$')
            if ($blank.Success) {
                # IESA occasionally prints a regional final without its winner. The
                # published regional bracket names it; use that only when the
                # bracket's final has the same loser and score.
                $final = Get-PublishedRegionalFinal $grade $number
                $winnerIndex = if ($final) { [array]::IndexOf(@($final.teams), $final.winner) } else { -1 }
                if ($winnerIndex -lt 0 -or !(Same-Name $final.teams[1 - $winnerIndex] $blank.Groups['loser'].Value) -or
                    [int]$final.scores[$winnerIndex] -ne [int]$blank.Groups['win'].Value -or
                    [int]$final.scores[1 - $winnerIndex] -ne [int]$blank.Groups['lose'].Value) {
                    continue
                }
                $result = [pscustomobject]@{
                    winner = $final.winner; loser = $final.teams[1 - $winnerIndex]
                    score = "$($blank.Groups['win'].Value)-$($blank.Groups['lose'].Value)"; sourceUrl = $url
                }
            } else {
                try { $result = Get-Result $row.Groups['result'].Value $url }
                catch { throw "Regional $number at $url`: $($_.Exception.Message) [$resultText]" }
            }
            if ($null -ne $result) {
                if ($null -ne $rosters) {
                    $result.winner = Get-CanonicalName $result.winner $rosters["$number"] "Regional $number"
                    $result.loser = Get-CanonicalName $result.loser $rosters["$number"] "Regional $number"
                    if ($result.winner -eq $result.loser) { throw "Duplicate regional teams at $url" }
                }
                $results["$number"] = $result
            }
        }
        $pairing = [regex]::Match($blocks[$s],
            "(?is)<td\s+class=['""]Champion['""][^>]*>(.*?)</td>")
        if ($pairing.Success) {
            $names = [regex]::Split((Get-Text $pairing.Groups[1].Value),
                '\s+vs\.?(?:\s+|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($names.Count -eq 2) {
                if ($Year -le 2005) {
                    for ($i = 0; $i -lt 2; $i++) {
                        $number = 2 * $s + $i + 1
                        if ($results.ContainsKey("$number")) { continue }
                        $candidate = Get-Name ($names[$i] -replace '\s*\(\d+-\d+\)$', '')
                        if (!$candidate -or !$rosters) {
                            throw "Missing Regional $number winner in Sectional $($s + 1) at $url"
                        }
                        $winner = Get-CanonicalName $candidate $rosters["$number"] "Sectional $($s + 1) pairing"
                        $results["$number"] = [pscustomobject]@{
                            winner = $winner; loser = $null; score = $null
                            sourceUrl = $url; qualifierOnly = $true
                        }
                    }
                }
                for ($i = 0; $i -lt 2; $i++) {
                    $number = 2 * $s + $i + 1
                    $record = [regex]::Match($names[$i], '^(.*?)\s*\((\d+)-(\d+)\)\s*$')
                    if (!$record.Success) { continue }
                    $team = Get-Name $record.Groups[1].Value
                    if (!$team) { throw "Invalid sectional pairing team in Sectional $($s + 1) at $url" }
                    if ($null -ne $rosters) {
                        $team = Get-CanonicalName $team $rosters["$number"] "Sectional $($s + 1) pairing"
                    }
                    if ($results.ContainsKey("$number") -and
                        !(Same-Name $team $results["$number"].winner)) {
                        throw "Sectional pairing does not match Regional $number winner at $url"
                    }
                    $records["$number"] = [pscustomobject]@{
                        team = $team
                        record = "$($record.Groups[2].Value)-$($record.Groups[3].Value)"
                        sourceUrl = $url
                    }
                }
            }
        }
    }
    return [pscustomobject]@{ results = $results; records = $records }
}

function Read-Sectionals([string]$html, [string]$url, [hashtable]$regionals) {
    $results = @{}
    $blocks = Get-SectionBlocks $html 'State Qualifiers are pending.' $url
    for ($s = 0; $s -lt $blocks.Count; $s++) {
        $cells = [regex]::Matches($blocks[$s], "(?is)<td\s+class=['""](?:ListData|Champion)['""][^>]*>(.*?)</td>")
        # "Regional 2/Sectional 1 Canceled": the state scoreboard places the survivor.
        if ($cells.Count -eq 0 -and (Get-Text $blocks[$s]) -match '(?i)\bcancell?ed\b') { continue }
        if ($cells.Count -ne 1) { throw "Expected one result cell in sectional $($s + 1) at $url" }
        $result = Get-Result $cells[0].Groups[1].Value $url
        if ($null -eq $result) {
            # A canceled regional sends the other regional's winner through
            # unopposed: "Southwood (Regional 4 Canceled. Southwood advances.)".
            $walkover = [regex]::Match((Get-Text $cells[0].Groups[1].Value),
                '(?i)^(?<team>.+?)\s*\(\s*Regional\s+(?<regional>\d+)\s+Cancell?ed\b[^)]*\)\s*$')
            if ($walkover.Success) {
                $present = @(@($regionals["$(2 * $s + 1)"], $regionals["$(2 * $s + 2)"]) | Where-Object { $_ })
                $team = Get-Name $walkover.Groups['team'].Value
                $results["$($s + 1)"] = [pscustomobject]@{
                    winner = Get-CanonicalName $team @($present | ForEach-Object { $_.winner }) "Sectional $($s + 1)"
                    loser = $null
                    score = $null
                    sourceUrl = $url
                    note = "Regional $($walkover.Groups['regional'].Value) canceled"
                }
            }
            continue
        }
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

function Read-Scoreboard([string]$html, [int]$gradeNumber, [string]$url,
    [hashtable]$sectionals, [hashtable]$regionals) {
    $legacy = $Year -le 2005
    # State names matched to a differently named sectional winner by town.
    $stateAliases = @{}
    $heading = if ($legacy) { "Class $($gradeNumber)$ClassName  State Tournament" } else {
        "$gradeNumber" + "th Grade Class $ClassName  State Tournament"
    }
    $start = $html.IndexOf($heading, [StringComparison]::OrdinalIgnoreCase)
    if ($start -lt 0) { throw "Missing $heading at $url" }
    # 2002-2005 scoreboards print Class A and then Class AA on one page.
    $next = [regex]::Match($html.Substring($start + $heading.Length),
        $(if ($legacy -and $ClassName -eq 'A') { "(?i)Class $($gradeNumber)AA\s+State Tournament" } else {
            "(?is)<td\s+class=['""]Score-Meet['""][^>]*>"
        }))
    $end = if ($next.Success) { $start + $heading.Length + $next.Index } else { $html.Length }
    $scope = $html.Substring($start, $end - $start)
    $games = @{}
    $matchups = @{}
    $rows = [regex]::Matches($scope,
        "(?is)<tr>\s*<td\s+class=['""]ScoreData['""][^>]*>(.*?)</td>\s*<td\s+class=['""]ScoreData-Score['""][^>]*>(.*?)</td>\s*<td\s+class=['""]ScoreData-Row['""][^>]*>(.*?)</td>\s*</tr>")
    $gameCount = if ($legacy) { 16 } else { 8 }
    if ($rows.Count -ne $gameCount) { throw "Expected $gameCount state games at $url; found $($rows.Count)" }
    foreach ($row in $rows) {
        $position = [regex]::Match($row.Groups[3].Value, '(?i)\bPosition=(\d+)')
        if ($position.Success) {
            $p = [int]$position.Groups[1].Value
        } else {
            # Unplayed games have no INFO link; their order in the official table is 8 through 1.
            $p = $gameCount - $games.Count
        }
        if ($p -lt 1 -or $p -gt $gameCount -or $games.ContainsKey("$p")) {
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
        if ($p -ge ($gameCount / 2 + 1)) {
            $game = $gameCount + 1 - $p
            $numbers = @($null, $null)
            for ($i = 0; $i -lt 2; $i++) {
                if ($sectionNumbers[$i]) {
                    $numbers[$i] = $sectionNumbers[$i]
                } elseif ($teams[$i]) {
                    $found = @(1..$(if ($legacy) { 16 } else { 8 }) | Where-Object {
                        $sectionals.ContainsKey("$_") -and (Same-Name $teams[$i] $sectionals["$_"].winner)
                    })
                    if (!$found.Count) {
                        $found = @(1..$(if ($legacy) { 16 } else { 8 }) | Where-Object {
                            $sectionals.ContainsKey("$_") -and (Similar-Name $teams[$i] $sectionals["$_"].winner)
                        })
                        if ($found.Count -gt 1) { $found = @() }
                    }
                    # Last resort: the scoreboard may name a district where the
                    # sectional page names its school ("Calumet City Dolton 149" /
                    # "Calumet City Dirksen"); accept only a unique same-town winner.
                    if (!$found.Count -and @($teams[$i] -split '\s+').Count -ge 3) {
                        $town = (@($teams[$i] -split '\s+')[0..1]) -join ' '
                        $found = @(1..$(if ($legacy) { 16 } else { 8 }) | Where-Object {
                            $sectionals.ContainsKey("$_") -and
                                $sectionals["$_"].winner -like "$town *"
                        })
                        if ($found.Count -gt 1) { $found = @() }
                        if ($found.Count -eq 1) { $stateAliases[$teams[$i]] = $sectionals["$($found[0])"].winner }
                    }
                    # A state qualifier whose sectional final IESA never published can
                    # still be placed: it won exactly one regional, and that regional's
                    # sectional has no result.
                    if (!$found.Count) {
                        $regional = @(1..$(if ($legacy) { 32 } else { 16 }) | Where-Object {
                            $regionals.ContainsKey("$_") -and
                                (Same-Name $teams[$i] $regionals["$_"].winner)
                        })
                        if ($regional.Count -eq 1) {
                            $sectionalId = [int][math]::Ceiling($regional[0] / 2)
                            $otherId = if ($regional[0] % 2) { $regional[0] + 1 } else { $regional[0] - 1 }
                            # The partner regional may be empty or canceled (2011-2018
                            # 7-3A Regional 1), leaving no opponent to record.
                            if ($sectionals.ContainsKey("$sectionalId")) {
                                throw "Conflicting state qualification for Sectional $sectionalId at $url"
                            }
                            $sectionals["$sectionalId"] = [pscustomobject]@{
                                winner = $regionals["$($regional[0])"].winner
                                loser = if ($regionals.ContainsKey("$otherId")) { $regionals["$otherId"].winner } else { $null }
                                score = $null
                                sourceUrl = $url
                                qualifierOnly = $true
                            }
                            $found = @($sectionalId)
                        }
                    }
                    if ($found.Count -ne 1) {
                        if ($Year -eq 2008 -and $gradeNumber -eq 8 -and $game -eq 2 -and
                            $found.Count -eq 0 -and $teams[$i] -eq 'Decatur St. Patrick') {
                            continue
                        }
                        throw "Cannot identify sectional for $($teams[$i]) at $url"
                    }
                    $numbers[$i] = [int]$found[0]
                }
            }
            if ($numbers[0] -and $numbers[1]) {
                if ($numbers[0] -lt 1 -or $numbers[0] -gt $(if ($legacy) { 16 } else { 8 }) -or
                    $numbers[1] -lt 1 -or $numbers[1] -gt $(if ($legacy) { 16 } else { 8 }) -or
                    $numbers[0] -eq $numbers[1]) { throw "Invalid sectional pairing at $url" }
                $matchups["$game"] = $numbers
            } elseif ($Year -eq 2008 -and $gradeNumber -eq 8 -and $game -eq 2 -and
                $teams -contains 'Decatur St. Patrick' -and
                @($numbers | Where-Object { $_ }).Count -eq 1) {
                $matchups["$game"] = $numbers
            }
        }
        $scoreMarkup = $row.Groups[2].Value
        $scoreMatch = [regex]::Match($scoreMarkup, '^\s*(\d+)\s*<br\s*/?>\s*(\d+)\s*$', 'IgnoreCase')
        $finished = (Get-Text $row.Groups[3].Value) -match '^F(?:\s|$)'
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
    foreach ($p in $gameCount..1) {
        $game = $games["$p"]
        $prior = @()
        if ($p -ge ($gameCount / 2 + 1) -and $matchups.ContainsKey("$($gameCount + 1 - $p)")) {
            $prior = @($matchups["$($gameCount + 1 - $p)"] | ForEach-Object {
                if ($null -ne $_) { $sectionals["$_"] } else { $null }
            })
        } elseif ($legacy -and $p -ge 5 -and $p -le 8) {
            $first = 16 - 2 * (8 - $p)
            $prior = @($games["$first"], $games["$($first - 1)"])
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
                    !(Similar-Name $game.teams[$i] $prior[$i].loser)) {
                    throw "Third-place participant disagrees with semifinal at $url"
                }
            }
        } elseif ($prior.Count -eq 2) {
            foreach ($i in 0..1) {
                if ($prior[$i].winner -and $game.teams[$i] -and
                    !(Similar-Name $game.teams[$i] $prior[$i].winner) -and
                    $stateAliases[$game.teams[$i]] -ne $prior[$i].winner) {
                    throw "State participant disagrees with prior round at $url"
                }
            }
        }
        if ($p -ge ($gameCount / 2 + 1) -and $game.winner -and $prior.Count -ne 2) {
            throw "Completed opening-round game lacks a verified sectional pairing at $url"
        }
        if ($prior.Count -eq 2) {
            for ($i = 0; $i -lt 2; $i++) {
                $expected = if ($null -eq $prior[$i]) { $null }
                    elseif ($p -eq 2) { $prior[$i].loser } else { $prior[$i].winner }
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
    foreach ($p in 1..$gameCount) { $numberedGames["$($gameCount + 1 - $p)"] = $games["$p"] }
    return [pscustomobject]@{ games = $numberedGames; matchups = $matchups }
}

# Collect every requested grade before writing anything, so a failed fetch cannot replace caches.
$captures = @{}
foreach ($grade in $Grades) {
    $number = [int]$grade.Substring(0, 1)
    $class = if ($Year -le 2005) { "$number$ClassName" } else { "$number-$ClassName" }
    $base = 'https://www.iesa.org/activities/gbk/'
    $regionalUrl = "${base}qualifiers_Sectional.asp?Year=$Year&Class=$class"
    $sectionalUrl = "${base}qualifiers_State.asp?Year=$Year&Class=$class"
    $stateUrl = "${base}scoreboards/index.asp?Year=$Year&Class=$class"
    $regionalHtml = Get-OfficialPage $regionalUrl "$Year Class $class Regional Champions/Sectional Matchups"
    $sectionalHtml = Get-OfficialPage $sectionalUrl "$Year Class $class Sectional Champions/State Qualifiers"
    $stateMarker = if ($Year -le 2005) { "Class $class  State Tournament" } else {
        "$($number)th Grade Class $ClassName  State Tournament"
    }
    $stateHtml = Get-OfficialPage $stateUrl $stateMarker
    $hasRoster = (Test-Path -LiteralPath (Join-Path $SitePath "$grade\data.json") -PathType Leaf) -or
        (Split-Path $SitePath -Leaf) -eq "$Year"
    $rosters = if ($hasRoster -and !($Year -eq 2004 -and $grade -eq '7th' -and $ClassName -eq 'A')) {
        Get-RegionalRosters $grade
    } else { $null }
    $regionalPairings = Read-Regionals $regionalHtml $regionalUrl $rosters
    $regionals = $regionalPairings.results
    $sectionals = Read-Sectionals $sectionalHtml $sectionalUrl $regionals
    $state = Read-Scoreboard $stateHtml $number $stateUrl $sectionals $regionals
    $captures[$grade] = [pscustomobject]@{
        updatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        year = $Year
        grade = $grade
        regionals = $regionals
        sectionalPairingRecords = $regionalPairings.records
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
