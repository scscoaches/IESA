param(
    # The live season's folder; defaults to <site>\<year> from live-season.json.
    [string]$SitePath,
    [int]$RetentionDays = 7,
    [double]$MinimumHoursBetweenRuns = 2,
    [switch]$Force,
    # Refresh only these classes (for example -Classes 1A). Scheduled runs omit it.
    [ValidateSet("1A", "2A", "3A", "4A")][string[]]$Classes,
    # The postseason 9 PM weekday run: re-read only schools still playing, in
    # every class, then the seeds and brackets. No strength of schedule, watch
    # links or roster check.
    [switch]$Evening,
    # Only the official seeds and bracket results: no school pages, watch links or
    # strength of schedule. Seeds are read even before a grade's seedsFrom date,
    # for when IESA publishes early; results still wait for bracketFrom.
    [switch]$BracketsOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "IesaRequest.ps1")
# Everything season-specific lives in live-season.json at the site root, so a new
# season needs no script edits (see Start-IesaSeason.ps1).
$siteRoot = Split-Path -Parent $PSScriptRoot
$liveSeason = Get-Content -Raw -LiteralPath (Join-Path $siteRoot "live-season.json") | ConvertFrom-Json
$SeasonYear = [int]$liveSeason.year
$FollowedClass = [string]$liveSeason.followedClass
function Get-SeasonDate([string]$value) { [datetime]::ParseExact($value, "yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture) }
$seedsFrom = Get-SeasonDate $liveSeason.seedsFrom
$bracketFrom = Get-SeasonDate $liveSeason.bracketFrom
$endDate = Get-SeasonDate $liveSeason.endDate
# Grades have their own ranking (official seeds) and regional dates on IESA's
# calendar; seasons configured before that use the shared dates above.
function Get-GradeDate([string]$grade, [string]$name, [datetime]$fallback) {
    $grades = $liveSeason.PSObject.Properties["grades"]
    if ($grades -and $grades.Value.$grade -and $grades.Value.$grade.$name) { return Get-SeasonDate $grades.Value.$grade.$name }
    return $fallback
}
if (!$SitePath) { $SitePath = Join-Path $siteRoot "$SeasonYear" }
$includes2A = !$Classes -or $Classes -contains $FollowedClass

# Season dates are Illinois dates; the GitHub Actions runner clock is UTC.
$today = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, "Central Standard Time").Date
if ($today -gt $endDate) {
    throw "The $SeasonYear season is complete; the scheduled score refresh ended after $($endDate.ToString('MMMM d'))."
}
# Nothing is played before IESA's "Games may begin" date, so nothing is requested.
if ($liveSeason.PSObject.Properties["gamesFrom"] -and $liveSeason.gamesFrom -and $today -lt (Get-SeasonDate $liveSeason.gamesFrom)) {
    Write-Output "The $SeasonYear season's games may begin $((Get-SeasonDate $liveSeason.gamesFrom).ToString('MMMM d')); nothing to check yet."
    return
}

# NFHS and Hudl watch links are a convenience beside the scores and must never fail a refresh.
function Update-StreamLinks {
    $seasonStart = [datetime]::new($SeasonYear, 8, 1)
    try {
        & (Join-Path $PSScriptRoot "Update-NfhsEvents.ps1") -SitePath $SitePath -SeasonStart $seasonStart
    } catch {
        Write-Warning "NFHS game refresh failed: $($_.Exception.Message)"
    }
    try {
        & (Join-Path $PSScriptRoot "Update-HudlEvents.ps1") -SitePath $SitePath -SeasonStart $seasonStart
    } catch {
        Write-Warning "Hudl game refresh failed: $($_.Exception.Message)"
    }
}

# Repeated runs (manual or test) within a few hours add IESA load for little gain.
# The followed class is the one refreshed every run, so its timestamps decide.
$primaryClass = ((Get-Content -Raw -LiteralPath (Join-Path $siteRoot "seasons.json") | ConvertFrom-Json | ForEach-Object { $_ }) |
    Where-Object { $_.year -eq $SeasonYear } | Select-Object -First 1).className
$followedPath = if ($FollowedClass -eq $primaryClass) { $SitePath } else { Join-Path $SitePath $FollowedClass }
$lastRun = $null
foreach ($grade in "7th", "8th") {
    try {
        $stamp = (Get-Content -Raw -LiteralPath (Join-Path $followedPath "scores-$grade.json") | ConvertFrom-Json).updatedAt
        $time = [datetime]::ParseExact($stamp, "yyyy-MM-dd HH:mm", [Globalization.CultureInfo]::InvariantCulture)
        if ($null -eq $lastRun -or $time -lt $lastRun) { $lastRun = $time }
    } catch { $lastRun = $null; break }
}
$paused = Get-IesaPause
if (!$paused -and !$Force -and !$BracketsOnly -and $includes2A -and $lastRun -and ((Get-Date) - $lastRun).TotalHours -lt $MinimumHoursBetweenRuns) {
    $paused = "Scores were refreshed at $($lastRun.ToString('yyyy-MM-dd HH:mm')); skipping IESA until $MinimumHoursBetweenRuns hours have passed (use -Force to override)."
}
if ($paused) {
    Write-Warning $paused
    if ($includes2A -and !$Evening -and !$BracketsOnly) { Update-StreamLinks }
    return
}

# The member directory maps school names to IESA ids. It is read only when a
# school page is actually needed (not at all once every tournament is over).
$directory = $null
function Get-SchoolDirectory {
    $page = Invoke-IesaPage "https://www.iesa.org/activities/members.asp"
    $map = @{}
    foreach ($match in [regex]::Matches($page.Content, "(?is)<a href='memberdetail\.asp\?SchoolID=(\d+)'[^>]*>(.*?)</a>")) {
        $schoolName = ([regex]::Replace($match.Groups[2].Value, "<[^>]+>", "") -replace "\s+", " ").Trim().ToLowerInvariant()
        $map[$schoolName] = $match.Groups[1].Value
    }
    return $map
}

function Get-Regionals([string]$grade) {
    # Classes built by Build-IesaSeason.ps1 -Live publish their rosters as JSON;
    # the hand-maintained Class 2A pages keep them in executable data.js.
    $json = Join-Path $ClassPath "$grade\data.json"
    if (Test-Path -LiteralPath $json) {
        foreach ($regional in (Get-Content -Raw -LiteralPath $json | ConvertFrom-Json).regionals) { , @($regional.teams) }
        return
    }
    $script = Get-Content -Raw (Join-Path $ClassPath "$grade\data.js")
    $match = if ($grade -eq "7th") {
        [regex]::Match($script, "(?s)\bvar\s+teams\s*=\s*\[(.*?)\]\s*;\s*return\s+teams\.map")
    } else {
        [regex]::Match($script, "(?s)\bvar\s+d\s*=\s*\[(.*?)\]\s*,\s*h\s*=")
    }
    if (!$match.Success) {
        throw "Unable to read regional teams from $grade\data.js."
    }
    foreach ($group in [regex]::Matches($match.Groups[1].Value, '\[([^\[\]]*)\]')) {
        , @([regex]::Matches($group.Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    }
}

function Get-Teams([string]$grade) {
    Get-Regionals $grade | ForEach-Object { $_ } | Select-Object -Unique
}

function Get-TeamKey([string]$name) {
    (($name -replace "(?i)\s+\(Co-?op\)$", "") -replace "\s+", " ").Trim().ToLowerInvariant()
}

# A school's season is over once it loses a regional, sectional or state
# quarterfinal game, or has played the state third-place or championship game
# (state games 1-4 are quarterfinals, 5-6 semifinals, 7 third place, 8 the
# final). Its IESA page is then never requested again; the last capture is kept.
function Get-EliminatedTeams([string]$grade) {
    $out = @{}
    $seedsPath = Join-Path $ClassPath "regional-seeds-$grade.json"
    if (Test-Path -LiteralPath $seedsPath) {
        $seeds = Get-Content -Raw -LiteralPath $seedsPath | ConvertFrom-Json
        foreach ($bracket in $seeds.regionalBrackets.PSObject.Properties) {
            foreach ($round in @($bracket.Value.rounds)) {
                foreach ($game in @($round)) {
                    if (!$game.winner -or $game.bye) { continue }
                    foreach ($name in @($game.teams)) {
                        if ($name -and $name -ne $game.winner) { $out[(Get-TeamKey $name)] = $true }
                    }
                }
            }
        }
    }
    $bracketPath = Join-Path $ClassPath "bracket-$grade.json"
    if (Test-Path -LiteralPath $bracketPath) {
        $capture = Get-Content -Raw -LiteralPath $bracketPath | ConvertFrom-Json
        foreach ($stage in "regionals", "sectionals") {
            foreach ($result in @($capture.$stage.PSObject.Properties)) {
                if ($result.Value.loser) { $out[(Get-TeamKey $result.Value.loser)] = $true }
            }
        }
        if ($capture.PSObject.Properties["games"] -and $capture.games) {
            foreach ($state in $capture.games.PSObject.Properties) {
                $game = $state.Value
                if (!$game.winner) { continue }
                $number = [int]$state.Name
                if ($number -le 4 -and $game.loser) { $out[(Get-TeamKey $game.loser)] = $true }
                if ($number -ge 7) {
                    foreach ($name in @($game.teams)) { if ($name) { $out[(Get-TeamKey $name)] = $true } }
                }
            }
        }
    }
    return $out
}

# A grade's tournament is over when the state third-place and championship games
# (7 and 8) both have winners; nothing in that grade is requested again.
function Test-GradeComplete([string]$path, [string]$grade) {
    $bracketPath = Join-Path $path "bracket-$grade.json"
    if (!(Test-Path -LiteralPath $bracketPath)) { return $false }
    $games = (Get-Content -Raw -LiteralPath $bracketPath | ConvertFrom-Json).games
    if (!$games) { return $false }
    foreach ($number in "7", "8") {
        $game = $games.PSObject.Properties[$number]
        if (!$game -or !$game.Value.winner) { return $false }
    }
    return $true
}

# Seeds pages only change until every regional final is played (or canceled).
function Test-RegionalsComplete([string]$path, [string]$grade) {
    $seedsPath = Join-Path $path "regional-seeds-$grade.json"
    if (!(Test-Path -LiteralPath $seedsPath)) { return $false }
    $brackets = @((Get-Content -Raw -LiteralPath $seedsPath | ConvertFrom-Json).regionalBrackets.PSObject.Properties)
    if (!$brackets.Count) { return $false }
    foreach ($bracket in $brackets) {
        if ($bracket.Value.canceled) { continue }
        $rounds = @($bracket.Value.rounds)
        if (!$rounds.Count) { return $false }
        $final = @($rounds[$rounds.Count - 1]) | Select-Object -Last 1
        if (!$final -or !$final.winner) { return $false }
    }
    return $true
}

# Rosters are fixed in data.js when the season is built, but IESA edits the
# assignment page when a school withdraws. Report drift so data.js can be fixed.
function Get-RosterChanges([string]$grade) {
    $classCode = $grade.Substring(0, 1) + "-$ClassName"
    $url = "https://www.iesa.org/activities/gbk/assignments_Regional.asp?Year=$SeasonYear&Class=$classCode"
    $html = (Invoke-IesaPage $url).Content
    $headers = @([regex]::Matches($html, "(?is)<td\s+class=['""]TableSubtitle2['""][^>]*>\s*Regional\s+(\d+)\s*</td>"))
    $local = @(Get-Regionals $grade)
    if ($headers.Count -ne $local.Count) {
        throw "$grade assignment page lists $($headers.Count) regionals; data.js has $($local.Count)."
    }
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $end = if ($i -lt $headers.Count - 1) { $headers[$i + 1].Index } else { $html.Length }
        $block = $html.Substring($headers[$i].Index, $end - $headers[$i].Index)
        $list = [regex]::Match($block, "(?is)<td\s+class=['""]ListData['""][^>]*>(.*?)</td>")
        if (!$list.Success) { throw "$grade Regional $($i + 1) has no team list on the assignment page." }
        $official = @(foreach ($line in [regex]::Split($list.Groups[1].Value, '(?i)<br\s*/?>')) {
            $name = (Get-PlainText $line) -replace '(?i)\(\s*(?:Host Info|Host)\s*\)', ''
            $name = ($name -replace '\s+', ' ').Trim()
            if ($name -and $name -notmatch '(?i)\(NON-COMPETITOR\)') { $name }
        })
        $added = @($official | Where-Object { $_ -notin $local[$i] })
        $removed = @($local[$i] | Where-Object { $_ -notin $official })
        if ($added.Count -or $removed.Count) {
            [pscustomobject]@{ regional = $i + 1; added = $added; removed = $removed; sourceUrl = $url }
        }
    }
}

function Get-PlainText([string]$html) {
    ([System.Net.WebUtility]::HtmlDecode([regex]::Replace($html, "<[^>]+>", "")) -replace "\s+", " ").Trim()
}

function Normalize-Matchup([string]$matchup) {
    $names = [regex]::Split($matchup.Trim(), "\s+(?:vs\.?|def\.)\s+", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($names.Count -ne 2) { return $matchup.Trim().ToLowerInvariant() }
    (($names | ForEach-Object { ($_ -replace "\s+", " ").Trim().ToLowerInvariant() } | Sort-Object) -join "|")
}

# The site is visited irregularly, so a single run's delta is not a useful view.
# Carry prior changes forward and expire them by age, keeping one row per game:
# the earliest observed "previous" value and the most recent score.
function Merge-ChangeWindow($priorChanges, $newChanges, [datetime]$cutoff, [string]$legacyStamp) {
    $merged = [ordered]@{}
    foreach ($change in @($priorChanges) + @($newChanges)) {
        if ($null -eq $change) { continue }
        $stamp = $change.firstSeenAt
        if (-not $stamp) { $stamp = $legacyStamp }
        $seenAt = [datetime]::MinValue
        if ([datetime]::TryParse($stamp, [ref]$seenAt)) {
            if ($seenAt -lt $cutoff) { continue }
        } else {
            continue
        }
        $key = $change.team + "|" + (Normalize-Matchup $change.opponent)
        if ($merged.Contains($key)) {
            $existing = $merged[$key]
            if ($existing.score -eq $change.score) { continue }
            $merged[$key] = [pscustomobject]@{
                team = $change.team
                opponent = $change.opponent
                previous = $existing.previous
                score = $change.score
                firstSeenAt = $existing.firstSeenAt
                latestAt = $stamp
                sourceUrl = $change.sourceUrl
            }
        } else {
            $merged[$key] = [pscustomobject]@{
                team = $change.team
                opponent = $change.opponent
                previous = $change.previous
                score = $change.score
                firstSeenAt = $stamp
                latestAt = $stamp
                sourceUrl = $change.sourceUrl
            }
        }
    }
    @($merged.Values | Sort-Object @{ e = "latestAt"; Descending = $true }, team, opponent)
}

# The site handler reads these caches while visitors browse. Writing in place would
# expose a truncated file for the duration of the write, so swap a finished copy in.
function Write-AtomicFile([string]$path, [string]$content) {
    $temporary = "$path.tmp"
    $content | Set-Content -Encoding UTF8 -LiteralPath $temporary
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

# The followed class (live-season.json; Class 2A in 2026) is re-read on every run;
# the season's other classes once a day, on their first run of the Central day,
# to keep IESA load down. The season's first class lives in <year>\, the others
# in <year>\<class>\ (see IesaSitePages.ps1).
$catalogueSeason = (Get-Content -Raw -LiteralPath (Join-Path $siteRoot "seasons.json") | ConvertFrom-Json | ForEach-Object { $_ }) |
    Where-Object { $_.year -eq $SeasonYear } | Select-Object -First 1
$seasonClasses = if ($catalogueSeason.PSObject.Properties["classes"]) { @($catalogueSeason.classes) } else { @($catalogueSeason.className) }
$liveClasses = @(foreach ($name in $seasonClasses) {
    $path = if ($name -eq $catalogueSeason.className) { $SitePath } else { Join-Path $SitePath $name }
    if ((Test-Path -LiteralPath (Join-Path $path "7th\data.json")) -or (Test-Path -LiteralPath (Join-Path $path "7th\data.js"))) {
        [pscustomobject]@{ Name = $name; Path = $path; EveryRun = $name -eq $FollowedClass }
    }
}) | Sort-Object { !$_.EveryRun }
if ($Classes) { $liveClasses = @($liveClasses | Where-Object { $_.Name -in $Classes }) }
foreach ($liveClass in $liveClasses) {
    $open = @("7th", "8th" | Where-Object { !(Test-GradeComplete $liveClass.Path $_) })
    $liveClass | Add-Member -NotePropertyName OpenGrades -NotePropertyValue $open
}
# Once every state final has been played there is nothing left to check: make no
# IESA request at all, and tell the workflow so it can switch its schedule off.
function Write-TournamentsComplete {
    Write-Output "Every $SeasonYear state tournament is complete; no further IESA requests are needed."
    if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "complete=true" }
}
if (!@($liveClasses | Where-Object { $_.OpenGrades.Count }).Count) {
    Write-TournamentsComplete
    return
}
$refreshedClasses = @()
# Seeds and postseason results are checked for every class on every run (about
# 8 IESA pages per class), so 1A/3A/4A brackets do not lag until the next morning.
$postseasonClasses = @()
foreach ($liveClass in $liveClasses) {
$ClassName = $liveClass.Name
$ClassPath = $liveClass.Path
if (!$liveClass.OpenGrades.Count) { continue }
if ($BracketsOnly) { $postseasonClasses += $liveClass; continue }
# The evening run reads every class's remaining schools, however often it ran today.
if (!$liveClass.EveryRun -and !$Force -and !$Evening) {
    $doneToday = @($liveClass.OpenGrades | Where-Object {
        $cachePath = Join-Path $ClassPath "scores-$_.json"
        (Test-Path -LiteralPath $cachePath) -and
            (Get-Content -Raw -LiteralPath $cachePath | ConvertFrom-Json).fullSweepDate -eq $today.ToString("yyyy-MM-dd")
    }).Count -eq $liveClass.OpenGrades.Count
    if ($doneToday) { $postseasonClasses += $liveClass; continue }
}
if (Get-IesaPause) { break }
# Each class is its own job for the per-run request cap (about 190-220 schools).
$global:IesaGuard.Count = 0
$refreshedClasses += $liveClass
$postseasonClasses += $liveClass
foreach ($grade in $liveClass.OpenGrades) {
    $gradeLevel = $grade.Substring(0, 1)
    $teams = @{}
    $updatedGames = @()
    $previousTeams = @{}
    $previousCaptureAt = $null
    $previousChanges = @()
    $previousSweep = $null
    $previousCache = $null
    $runTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    $previousPath = Join-Path $ClassPath "scores-$grade.json"
    if (Test-Path -LiteralPath $previousPath) {
        $previousCache = Get-Content -Raw -LiteralPath $previousPath | ConvertFrom-Json
        $previousCaptureAt = $previousCache.updatedAt
        foreach ($property in $previousCache.teams.PSObject.Properties) {
            $previousTeams[$property.Name] = $property.Value
        }
        $previousChanges = @($previousCache.updatedGames)
        if ($previousCache.PSObject.Properties["fullSweepDate"]) { $previousSweep = $previousCache.fullSweepDate }
    }

    # Go easy on IESA: the first run of each Central day reads every school still
    # playing; later runs that day re-read the followed class (the evening run,
    # every class). A school knocked out of the postseason is never requested
    # again - its last capture is reused. Schools may enter a game with its final
    # score without ever listing it as PENDING, so every other school is re-read.
    $todayKey = $today.ToString("yyyy-MM-dd")
    $fullSweep = $Force -or !$previousSweep -or $previousSweep -ne $todayKey -or !$previousTeams.Count
    $eliminated = Get-EliminatedTeams $grade
    $fetched = 0
    $reused = 0

    $rosterChanges = @()
    if ($previousCache -and $previousCache.PSObject.Properties["rosterChanges"]) {
        $rosterChanges = @($previousCache.rosterChanges)
    }
    try {
        # Rosters are settled once the brackets begin.
        if ($fullSweep -and !$Evening -and $today -lt $bracketFrom) { $rosterChanges = @(Get-RosterChanges $grade) }
        foreach ($change in $rosterChanges) {
            $message = "$grade Regional $($change.regional) roster differs from IESA assignments." +
                $(if ($change.removed.Count) { " No longer listed: $($change.removed -join ', ')." } else { "" }) +
                $(if ($change.added.Count) { " Newly listed: $($change.added -join ', ')." } else { "" }) +
                $(if (!(Test-Path -LiteralPath (Join-Path $ClassPath "$grade\data.json"))) { " Update $grade\data.js." } else {
                    " Rebuild with .\Build-IesaSeason.ps1 -Year $SeasonYear -ClassName $ClassName -Live." })
            Write-Warning $message
            if ($env:GITHUB_ACTIONS) { Write-Output "::warning title=IESA roster change::$message" }
        }
    } catch {
        Write-Warning "Roster check for $grade failed: $($_.Exception.Message)"
    }

    foreach ($team in Get-Teams $grade) {
        if (Get-IesaPause) { break }
        if ($previousTeams.ContainsKey($team) -and $eliminated.ContainsKey((Get-TeamKey $team))) {
            $teams[$team] = $previousTeams[$team]
            $reused++
            continue
        }
        if ($null -eq $directory) { $directory = Get-SchoolDirectory }
        $lookup = ($team -replace "\s+\(Co-op\)", "").Trim().ToLowerInvariant()
        if (!$directory.ContainsKey($lookup)) {
            Write-Warning "No IESA member match found for $team."
            continue
        }
        $schoolId = $directory[$lookup]
        $sourceUrl = "https://www.iesa.org/activities/memberStats.asp?SchoolID=$schoolId&ActivityCode=GBK&GradeLevel=$gradeLevel"
        try {
            $fetched++
            $page = Invoke-IesaPage $sourceUrl
            $games = @()
            foreach ($match in [regex]::Matches($page.Content, "(?is)<td class='ListData'>(.*?)</td>\s*<td class='ListData-R'>(.*?)</td>")) {
                $games += [pscustomobject]@{ opponent = Get-PlainText $match.Groups[1].Value; score = (Get-PlainText $match.Groups[2].Value).ToUpperInvariant() }
            }
            $previousGames = @()
            if ($previousTeams.ContainsKey($team)) {
                $previousGames = @($previousTeams[$team].games)
            }
            $matchedPrevious = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($game in $games) {
                if ([string]::IsNullOrWhiteSpace($game.score) -or $game.score -eq "PENDING") { continue }
                $previousScore = $null
                for ($gameIndex = 0; $gameIndex -lt $previousGames.Count; $gameIndex++) {
                    if (!$matchedPrevious.Contains($gameIndex) -and (Normalize-Matchup $previousGames[$gameIndex].opponent) -eq (Normalize-Matchup $game.opponent)) {
                        $previousScore = $previousGames[$gameIndex].score
                        [void]$matchedPrevious.Add($gameIndex)
                        break
                    }
                }
                # A class's first capture is the baseline; reporting every game
                # already played as newly posted would flood "Score updates".
                if ($previousTeams.Count -and $previousScore -ne $game.score) {
                    $priorResult = if ($null -eq $previousScore) { "N/A" } else { $previousScore }
                    $updatedGames += [pscustomobject]@{
                        team = $team
                        opponent = $game.opponent
                        previous = $priorResult
                        score = $game.score
                        firstSeenAt = $runTimestamp
                        sourceUrl = $sourceUrl
                    }
                }
            }
            $teamName = [regex]::Escape((($team -replace "\s+\(Co-op\)", "")).Trim())
            $wins = @($games | Where-Object { $_.opponent -match ("^" + $teamName + ".*\sdef\.") }).Count
            $losses = @($games | Where-Object { $_.opponent -match ("\sdef\..*" + $teamName + "$") }).Count
            $teams[$team] = [pscustomobject]@{ sourceUrl = $sourceUrl; games = $games; record = [pscustomobject]@{ wins = $wins; losses = $losses; completed = $wins + $losses } }
        } catch {
            Write-Warning "Unable to refresh ${team}: $($_.Exception.Message)"
            # Keep the last good data for this school. Dropping it would 404 the team's
            # Update button and make the next run re-report every game as newly posted.
            if ($previousTeams.ContainsKey($team)) {
                $teams[$team] = $previousTeams[$team]
            }
        }
    }
    # IESA stopped answering partway through; keep the last good files untouched.
    $pausedNow = Get-IesaPause
    if ($pausedNow) {
        Write-Warning "$grade scores were not saved. $pausedNow"
        continue
    }
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $rollingChanges = @(Merge-ChangeWindow $previousChanges $updatedGames $cutoff $previousCaptureAt)
    Write-Output ("{0} {1}: {2} - read {3} school pages, reused {4} for schools already eliminated." -f
        $ClassName, $grade, $(if ($fullSweep) { "full daily check" } else { "partial check" }), $fetched, $reused)
    $cache = [pscustomobject]@{
        updatedAt = $runTimestamp
        previousCaptureAt = $previousCaptureAt
        fullSweepDate = if ($fullSweep) { $todayKey } else { $previousSweep }
        retainedSince = $cutoff.ToString("yyyy-MM-dd HH:mm")
        retainedDays = $RetentionDays
        teams = $teams
        updatedGames = $rollingChanges
        rosterChanges = $rosterChanges
    }
    $json = $cache | ConvertTo-Json -Depth 6
    Write-AtomicFile (Join-Path $ClassPath "scores-$grade.json") $json
    Write-AtomicFile (Join-Path $ClassPath "scores-$grade.js") ("window.iesaScoreCache = " + $json + ";")
}
}

if ($includes2A -and !$Evening -and !$BracketsOnly) { Update-StreamLinks }
$pausedNow = Get-IesaPause
if ($pausedNow) {
    Write-Warning "Skipping strength of schedule, seeds and bracket. $pausedNow"
    return
}
# Strength of schedule rebuilds itself per class on Saturdays (or when missing or
# stale), and is unofficial. Records already cached for other classes are reused.
# It reads every opponent's page, so it stops once the brackets begin.
foreach ($liveClass in $refreshedClasses) {
    if ($Evening -or $today -ge $bracketFrom) { break }
    try {
        & (Join-Path $PSScriptRoot "Update-Strength.ps1") -SitePath $liveClass.Path -Year $SeasonYear
    } catch {
        Write-Warning "Class $($liveClass.Name) strength of schedule refresh failed: $($_.Exception.Message)"
    }
}

$seedRefreshError = $null
if ($BracketsOnly -or $today -ge $seedsFrom) {
    foreach ($liveClass in $postseasonClasses) {
        # A grade's seeds are official after its "Online Ranking" date, and its
        # seed page stops changing once its regional finals are played.
        $grades = @($liveClass.OpenGrades | Where-Object {
            ($BracketsOnly -or $today -ge (Get-GradeDate $_ "seedsFrom" $seedsFrom)) -and !(Test-RegionalsComplete $liveClass.Path $_) })
        if (!$grades.Count) { continue }
        try {
            & (Join-Path $PSScriptRoot "Update-IesaSeeds.ps1") -SitePath $liveClass.Path -ClassName $liveClass.Name -Year $SeasonYear -Grades $grades
        } catch {
            if ($liveClass.EveryRun) { $seedRefreshError = $_ }
            Write-Warning "Class $($liveClass.Name) regional seed refresh failed: $($_.Exception.Message)"
        }
    }
}
if ($today -ge $bracketFrom) {
    foreach ($liveClass in $postseasonClasses) {
        # Each grade's results are read from its own first regional date.
        $grades = @($liveClass.OpenGrades | Where-Object { $today -ge (Get-GradeDate $_ "bracketFrom" $bracketFrom) })
        if (!$grades.Count) { continue }
        try {
            & (Join-Path $PSScriptRoot "Update-IesaBracket.ps1") -SitePath $liveClass.Path -ClassName $liveClass.Name -Year $SeasonYear -Grades $grades
        } catch {
            # Class 2A's bracket failure still fails the run, as before.
            if ($liveClass.EveryRun) { throw }
            Write-Warning "Class $($liveClass.Name) bracket refresh failed: $($_.Exception.Message)"
        }
    }

    # State results decide top-four placement, so once a state final has been
    # played refresh the year menu's trophies from IESA's state tournament
    # history (15 pages), at most once a day, then the team index that maps
    # schools to classes. Presentation only; it must never fail a score refresh.
    try {
        $siteRoot = Split-Path -Parent $PSScriptRoot
        $placementsPath = Join-Path $siteRoot "placements.json"
        $placementsDay = $null
        if (Test-Path -LiteralPath $placementsPath) {
            $placementsDay = [string](Get-Content -Raw -LiteralPath $placementsPath | ConvertFrom-Json).generatedAt
        }
        $finalsPlayed = @($liveClasses | Where-Object { (Test-GradeComplete $_.Path "7th") -or (Test-GradeComplete $_.Path "8th") }).Count
        $placementsScript = Join-Path $siteRoot "Build-IesaPlacements.ps1"
        if ($finalsPlayed -and !($placementsDay -and $placementsDay.StartsWith($today.ToString("yyyy-MM-dd"))) -and (Test-Path $placementsScript)) {
            & $placementsScript -SiteRoot $siteRoot | Out-Null
        }
        $teamIndexScript = Join-Path $siteRoot "Build-IesaTeamIndex.ps1"
        if (Test-Path $teamIndexScript) {
            & $teamIndexScript -SiteRoot $siteRoot | Out-Null
        }
    } catch {
        Write-Warning "Placement refresh failed: $($_.Exception.Message)"
    }
}
if (!@($liveClasses | Where-Object { (!(Test-GradeComplete $_.Path "7th")) -or (!(Test-GradeComplete $_.Path "8th")) }).Count) {
    Write-TournamentsComplete
}
if ($seedRefreshError) { throw $seedRefreshError }
