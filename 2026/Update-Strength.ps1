param(
    [string]$SitePath = "C:\inetpub\personalroot\IESA\2026",
    # The live season (default: live-season.json at the site root).
    [int]$Year,
    [switch]$Force
)
if (!$Year) { $Year = [int](Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "live-season.json") | ConvertFrom-Json).year }

# Weekly, unofficial strength of schedule for each bracket team. Runs on Saturday
# (Central time, because GitHub runners use UTC) or when the last run is over
# eight days old or the bracket teams changed; other refreshes skip it.
#   Class strength: every opponent's IESA class (1A-4A) from the four regional
#   assignment pages per grade, so it works before most games are scored.
#   Opponent results: the IESA record of each opponent a bracket team has
#   already played, excluding games against that team.
# rating = 0.6 x opponents' win % (pulled toward .500 by four phantom games so a
# short schedule cannot dominate) + 0.4 x class weight (1A = 0 ... 4A = 1).
$ErrorActionPreference = "Stop"
$central = [TimeZoneInfo]::ConvertTime((Get-Date), [TimeZoneInfo]::FindSystemTimeZoneById("Central Standard Time"))
$classes = "1A", "2A", "3A", "4A"

function Get-PlainText([string]$html) {
    ([Net.WebUtility]::HtmlDecode([regex]::Replace($html, "<[^>]+>", "")) -replace "\s+", " ").Trim()
}

function Get-Key([string]$name) {
    (($name -replace '(?i)\((?:Host Info|Host|Co-?op|NON-COMPETITOR)\)', '') -replace '\s+', ' ').Trim().ToLowerInvariant()
}

function Get-Regionals([string]$grade) {
    # Classes built with Build-IesaSeason.ps1 -Live keep their rosters in data.json.
    $json = Join-Path $SitePath "$grade\data.json"
    if (Test-Path -LiteralPath $json) {
        foreach ($regional in (Get-Content -Raw -LiteralPath $json | ConvertFrom-Json).regionals) { , @($regional.teams) }
        return
    }
    $script = Get-Content -Raw (Join-Path $SitePath "$grade\data.js")
    $match = if ($grade -eq "7th") {
        [regex]::Match($script, "(?s)\bvar\s+teams\s*=\s*\[(.*?)\]\s*;\s*return\s+teams\.map")
    } else {
        [regex]::Match($script, "(?s)\bvar\s+d\s*=\s*\[(.*?)\]\s*,\s*h\s*=")
    }
    if (!$match.Success) { throw "Unable to read regional teams from $grade\data.js." }
    foreach ($group in [regex]::Matches($match.Groups[1].Value, '\[([^\[\]]*)\]')) {
        , @([regex]::Matches($group.Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    }
}

# Rows read "A def. B" (decided) or "A vs. B" (pending), seen from one school's page.
function Get-Results([string]$ownKey, $games) {
    foreach ($game in $games) {
        $parts = [regex]::Split($game.opponent, '\s+def\.\s+', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($game.score) -or $game.score -eq "PENDING") { continue }
        $winner = Get-Key $parts[0]; $loser = Get-Key $parts[1]
        if ($winner -eq $ownKey) { [pscustomobject]@{ opponent = $loser; won = $true } }
        elseif ($loser -eq $ownKey) { [pscustomobject]@{ opponent = $winner; won = $false } }
    }
}

function Get-OpponentKeys([string]$ownKey, $games) {
    foreach ($game in $games) {
        $parts = [regex]::Split($game.opponent, '\s+(?:def\.|vs\.)\s+', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($parts.Count -ne 2) { continue }
        $keys = $parts | ForEach-Object { Get-Key $_ }
        $other = if ($keys[0] -eq $ownKey) { $keys[1] } elseif ($keys[1] -eq $ownKey) { $keys[0] } else { $null }
        # Placeholder rows such as "Sand Valley Tournament - TBD" are not opponents.
        if ($other -and $other -notmatch 'tournament|\btbd\b') {
            [pscustomobject]@{ key = $other; decided = !([string]::IsNullOrWhiteSpace($game.score) -or $game.score -eq "PENDING") }
        }
    }
}

$grades = "7th", "8th"
# The class of the pages in $SitePath (Class 2A unless built with -Live).
$className = "2A"
$classData = Join-Path $SitePath "7th\data.json"
if (Test-Path -LiteralPath $classData) { $className = (Get-Content -Raw -LiteralPath $classData | ConvertFrom-Json).className }
$ownClassNumber = [int]$className.Substring(0, 1)
$prior = @{}
$due = [bool]$Force
foreach ($grade in $grades) {
    $path = Join-Path $SitePath "strength-$grade.json"
    $cache = Get-Content -Raw (Join-Path $SitePath "scores-$grade.json") | ConvertFrom-Json
    $teamList = (@($cache.teams.PSObject.Properties.Name) | Sort-Object) -join "|"
    if (!(Test-Path -LiteralPath $path)) { $due = $true; continue }
    try {
        $prior[$grade] = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        $last = [datetime]::ParseExact($prior[$grade].updatedAt, "yyyy-MM-dd HH:mm", [Globalization.CultureInfo]::InvariantCulture)
        if (($central.DayOfWeek -eq "Saturday" -and $last.Date -ne $central.Date) -or ($central - $last).TotalDays -ge 8 -or
            (($prior[$grade].teamList -join "|") -ne $teamList)) { $due = $true }
    } catch {
        $due = $true
    }
}
if (!$due) { return }
. (Join-Path $PSScriptRoot "IesaRequest.ps1")
# The rebuild reads several hundred opponent pages, so it gets its own per-run
# request budget instead of sharing the score refresh's. Spacing and the
# failure pause still apply.
$global:IesaGuard.Count = 0
$paused = Get-IesaPause
if ($paused) {
    Write-Warning "Strength of schedule not rebuilt. $paused"
    return
}

$directoryPage = (Invoke-IesaPage "https://www.iesa.org/activities/members.asp").Content
$directory = @{}
foreach ($match in [regex]::Matches($directoryPage, "(?is)<a href='memberdetail\.asp\?SchoolID=(\d+)'[^>]*>(.*?)</a>")) {
    $directory[(Get-Key (Get-PlainText $match.Groups[2].Value))] = $match.Groups[1].Value
}

$classOf = @{}
foreach ($grade in $grades) {
    $map = @{}
    foreach ($class in $classes) {
        $url = "https://www.iesa.org/activities/gbk/assignments_Regional.asp?Year=$Year&Class=$($grade.Substring(0, 1))-$class"
        $html = (Invoke-IesaPage $url).Content
        foreach ($cell in [regex]::Matches($html, "(?is)<td\s+class=['""]ListData['""][^>]*>(.*?)</td>")) {
            foreach ($line in [regex]::Split($cell.Groups[1].Value, '(?i)<br\s*/?>')) {
                $key = Get-Key (Get-PlainText $line)
                if ($key) { $map[$key] = $class }
            }
        }
    }
    $classOf[$grade] = $map
}

foreach ($grade in $grades) {
    $otherGrade = if ($grade -eq "7th") { "8th" } else { "7th" }
    $cache = Get-Content -Raw (Join-Path $SitePath "scores-$grade.json") | ConvertFrom-Json
    $bracket = @{}
    foreach ($property in $cache.teams.PSObject.Properties) {
        $bracket[(Get-Key ($property.Name -replace '\s*\(Co-?op\)$', ''))] = $property
    }
    $priorOpponents = @{}
    if ($prior.ContainsKey($grade)) {
        foreach ($property in $prior[$grade].opponents.PSObject.Properties) { $priorOpponents[$property.Name] = $property.Value }
    }

    # Records for bracket teams come from the score cache; other opponents that a
    # bracket team has already played are read from their own IESA page.
    $records = @{}
    foreach ($key in $bracket.Keys) { $records[$key] = @(Get-Results $key $bracket[$key].Value.games) }
    $played = @{}
    foreach ($key in $bracket.Keys) {
        Get-OpponentKeys $key $bracket[$key].Value.games | Where-Object { $_.decided -and !$bracket.ContainsKey($_.key) } |
            ForEach-Object { $played[$_.key] = $true }
    }
    # Opponents in another class of this season already have their games in that class's
    # score cache, so only schools outside every cache cost an IESA request.
    $known = @{}
    foreach ($folder in @($PSScriptRoot) + @("1A", "2A", "3A", "4A" | ForEach-Object { Join-Path $PSScriptRoot $_ })) {
        $other = Join-Path $folder "scores-$grade.json"
        if (!(Test-Path -LiteralPath $other) -or (Resolve-Path $folder).Path -eq (Resolve-Path $SitePath).Path) { continue }
        foreach ($property in (Get-Content -Raw -LiteralPath $other | ConvertFrom-Json).teams.PSObject.Properties) {
            $known[(Get-Key ($property.Name -replace '\s*\(Co-?op\)$', ''))] = $property.Value.games
        }
    }
    $reusedRecords = 0
    foreach ($key in @($played.Keys)) {
        if ($known.ContainsKey($key)) {
            $records[$key] = @(Get-Results $key $known[$key])
            $played.Remove($key)
            $reusedRecords++
        }
    }
    Write-Output "$className $grade strength: $reusedRecords opponent records reused from other classes, $($played.Count) read from IESA."
    foreach ($key in $played.Keys) {
        if (!$directory.ContainsKey($key)) { continue }
        $url = "https://www.iesa.org/activities/memberStats.asp?SchoolID=$($directory[$key])&ActivityCode=GBK&GradeLevel=$($grade.Substring(0, 1))"
        if (Get-IesaPause) { break }
        try {
            $html = (Invoke-IesaPage $url).Content
            $games = foreach ($row in [regex]::Matches($html, "(?is)<td class='ListData'>(.*?)</td>\s*<td class='ListData-R'>(.*?)</td>")) {
                [pscustomobject]@{ opponent = Get-PlainText $row.Groups[1].Value; score = (Get-PlainText $row.Groups[2].Value).ToUpperInvariant() }
            }
            $records[$key] = @(Get-Results $key $games)
        } catch {
            Write-Warning "Unable to read $grade record for ${key}: $($_.Exception.Message)"
            $old = $priorOpponents[$key]
            if ($old -and $null -ne $old.results) {
                $records[$key] = @($old.results | ForEach-Object { [pscustomobject]@{ opponent = $_.o; won = [bool]$_.w } })
            }
        }
    }
    $pausedNow = Get-IesaPause
    if ($pausedNow) {
        Write-Warning "$grade strength of schedule not saved. $pausedNow"
        continue
    }

    $opponents = [ordered]@{}
    $allKeys = @($records.Keys) + @($bracket.Keys | ForEach-Object { Get-OpponentKeys $_ $bracket[$_].Value.games } | ForEach-Object { $_.key })
    foreach ($key in ($allKeys | Sort-Object -Unique)) {
        $class = $classOf[$grade][$key]
        if (!$class) { $class = $classOf[$otherGrade][$key] }
        $results = $records[$key]
        $entry = [ordered]@{ class = $class }
        if ($null -ne $results) {
            $entry.wins = @($results | Where-Object { $_.won }).Count
            $entry.losses = @($results | Where-Object { !$_.won }).Count
            # Only results against bracket teams are needed to remove a team's own games.
            $entry.results = @($results | Where-Object { $bracket.ContainsKey($_.opponent) } |
                ForEach-Object { [pscustomobject]@{ o = $_.opponent; w = [int]$_.won } })
        }
        $opponents[$key] = [pscustomobject]$entry
    }

    $teams = [ordered]@{}
    $regionals = @(Get-Regionals $grade)
    for ($r = 0; $r -lt $regionals.Count; $r++) {
        $rows = foreach ($team in $regionals[$r]) {
            $key = Get-Key ($team -replace '\s*\(Co-?op\)$', '')
            if (!$bracket.ContainsKey($key)) { continue }
            $schedule = @(Get-OpponentKeys $key $bracket[$key].Value.games)
            $mix = [ordered]@{ "1A" = 0; "2A" = 0; "3A" = 0; "4A" = 0; other = 0 }
            $classTotal = 0; $classCount = 0
            foreach ($game in $schedule) {
                $class = $opponents[$game.key].class
                if ($class) { $mix[$class]++; $classTotal += [int]$class.Substring(0, 1); $classCount++ } else { $mix.other++ }
            }
            $owpTotal = 0.0; $owpGames = 0; $quality = 0; $biggerWins = 0; $biggerLosses = 0
            foreach ($result in $records[$key]) {
                $opponent = $opponents[$result.opponent]
                if ($opponent.class -and [int]$opponent.class.Substring(0, 1) -gt $ownClassNumber) { if ($result.won) { $biggerWins++ } else { $biggerLosses++ } }
                if ($null -eq $opponent.wins) { continue }
                $mine = @($opponent.results | Where-Object { $_.o -eq $key })
                $wins = $opponent.wins - @($mine | Where-Object { $_.w }).Count
                $losses = $opponent.losses - @($mine | Where-Object { !$_.w }).Count
                if ($wins + $losses -eq 0) { continue }
                $pct = $wins / ($wins + $losses)
                $owpTotal += $pct; $owpGames++
                if ($result.won -and $pct -gt 0.5) { $quality++ }
            }
            $owp = if ($owpGames) { $owpTotal / $owpGames } else { $null }
            $adjusted = ($owpTotal + 0.5 * 4) / ($owpGames + 4)
            $classAverage = if ($classCount) { $classTotal / $classCount } else { $null }
            $classScale = if ($classCount) { ($classAverage - 1) / 3 } else { 1 / 3 }
            [pscustomobject]@{
                team = $bracket[$key].Name
                rating = [math]::Round(0.6 * $adjusted + 0.4 * $classScale, 4)
                opponentsWinPct = if ($null -ne $owp) { [math]::Round($owp, 3) } else { $null }
                ratedGames = $owpGames
                classAverage = if ($null -ne $classAverage) { [math]::Round($classAverage, 2) } else { $null }
                mix = [pscustomobject]$mix
                vsBigger = [pscustomobject]@{ wins = $biggerWins; losses = $biggerLosses }
                qualityWins = $quality
            }
        }
        $ranked = @($rows | Sort-Object @{ e = "rating"; Descending = $true }, team)
        for ($i = 0; $i -lt $ranked.Count; $i++) {
            $row = $ranked[$i]
            $teams[$row.team] = [pscustomobject][ordered]@{
                regional = $r + 1; rank = $i + 1; of = $ranked.Count
                rating = $row.rating; opponentsWinPct = $row.opponentsWinPct; ratedGames = $row.ratedGames
                classAverage = $row.classAverage; mix = $row.mix; vsBigger = $row.vsBigger; qualityWins = $row.qualityWins
            }
        }
    }

    $json = [pscustomobject]@{
        updatedAt = $central.ToString("yyyy-MM-dd HH:mm")
        teamList = @($cache.teams.PSObject.Properties.Name | Sort-Object)
        teams = $teams
        opponents = $opponents
    } | ConvertTo-Json -Depth 6
    $path = Join-Path $SitePath "strength-$grade.json"
    $json | Set-Content -Encoding UTF8 -LiteralPath "$path.tmp"
    Move-Item -LiteralPath "$path.tmp" -Destination $path -Force
}
