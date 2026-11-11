param(
    # The live season's folder; defaults to <site>\<year> from live-season.json.
    [string]$SitePath,
    [int]$RetentionDays = 7,
    [double]$MinimumHoursBetweenRuns = 2,
    [switch]$Force,
    # Refresh only these classes (for example -Classes 1A). Scheduled runs omit it.
    [ValidateSet("1A", "2A", "3A", "4A")][string[]]$Classes
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
if (!$SitePath) { $SitePath = Join-Path $siteRoot "$SeasonYear" }
$includes2A = !$Classes -or $Classes -contains $FollowedClass

# Season dates are Illinois dates; the GitHub Actions runner clock is UTC.
$today = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, "Central Standard Time").Date
if ($today -gt $endDate) {
    throw "The $SeasonYear season is complete; the scheduled score refresh ended after $($endDate.ToString('MMMM d'))."
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
if (!$paused -and !$Force -and $includes2A -and $lastRun -and ((Get-Date) - $lastRun).TotalHours -lt $MinimumHoursBetweenRuns) {
    $paused = "Scores were refreshed at $($lastRun.ToString('yyyy-MM-dd HH:mm')); skipping IESA until $MinimumHoursBetweenRuns hours have passed (use -Force to override)."
}
if ($paused) {
    Write-Warning $paused
    if ($includes2A) { Update-StreamLinks }
    return
}

$directoryPage = Invoke-IesaPage "https://www.iesa.org/activities/members.asp"
$directory = @{}
foreach ($match in [regex]::Matches($directoryPage.Content, "(?is)<a href='memberdetail\.asp\?SchoolID=(\d+)'[^>]*>(.*?)</a>")) {
    $schoolName = ([regex]::Replace($match.Groups[2].Value, "<[^>]+>", "") -replace "\s+", " ").Trim().ToLowerInvariant()
    $directory[$schoolName] = $match.Groups[1].Value
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

# Schools that lost a regional or sectional game have finished their season;
# their IESA page only changes if a late regular-season score is posted, which
# the next morning's full check picks up. State qualifiers stay on the list.
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
    }
    return $out
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
$refreshedClasses = @()
# Seeds and postseason results are checked for every class on every run (about
# 8 IESA pages per class), so 1A/3A/4A brackets do not lag until the next morning.
$postseasonClasses = @()
foreach ($liveClass in $liveClasses) {
$ClassName = $liveClass.Name
$ClassPath = $liveClass.Path
if (!$liveClass.EveryRun -and !$Force) {
    $doneToday = @("7th", "8th" | Where-Object {
        $cachePath = Join-Path $ClassPath "scores-$_.json"
        (Test-Path -LiteralPath $cachePath) -and
            (Get-Content -Raw -LiteralPath $cachePath | ConvertFrom-Json).fullSweepDate -eq $today.ToString("yyyy-MM-dd")
    }).Count -eq 2
    if ($doneToday) { $postseasonClasses += $liveClass; continue }
}
if (Get-IesaPause) { break }
# Each class is its own job for the per-run request cap (about 190-220 schools).
$global:IesaGuard.Count = 0
$refreshedClasses += $liveClass
$postseasonClasses += $liveClass
foreach ($grade in "7th", "8th") {
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

    # Go easy on IESA: the first run of each Central day reads every school. Later
    # runs that day skip only schools knocked out of the postseason and reuse
    # this morning's page for them. Schools may enter a game with its final score
    # without ever listing it as PENDING, so every other school is re-read.
    $todayKey = $today.ToString("yyyy-MM-dd")
    $fullSweep = $Force -or !$previousSweep -or $previousSweep -ne $todayKey -or !$previousTeams.Count
    $eliminated = if ($fullSweep) { @{} } else { Get-EliminatedTeams $grade }
    $fetched = 0
    $reused = 0

    $rosterChanges = @()
    if (!$fullSweep -and $previousCache.PSObject.Properties["rosterChanges"]) {
        $rosterChanges = @($previousCache.rosterChanges)
    }
    try {
        if ($fullSweep) { $rosterChanges = @(Get-RosterChanges $grade) }
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
        if (!$fullSweep -and $previousTeams.ContainsKey($team) -and $eliminated.ContainsKey((Get-TeamKey $team))) {
            $teams[$team] = $previousTeams[$team]
            $reused++
            continue
        }
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
    Write-Output ("{0} {1}: {2} - read {3} school pages, reused {4} unchanged since today's full check." -f
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

if ($includes2A) { Update-StreamLinks }
$pausedNow = Get-IesaPause
if ($pausedNow) {
    Write-Warning "Skipping strength of schedule, seeds and bracket. $pausedNow"
    return
}
# Strength of schedule rebuilds itself per class on Saturdays (or when missing or
# stale), and is unofficial. Records already cached for other classes are reused.
foreach ($liveClass in $refreshedClasses) {
    try {
        & (Join-Path $PSScriptRoot "Update-Strength.ps1") -SitePath $liveClass.Path -Year $SeasonYear
    } catch {
        Write-Warning "Class $($liveClass.Name) strength of schedule refresh failed: $($_.Exception.Message)"
    }
}

$seedRefreshError = $null
if ($today -ge $seedsFrom) {
    foreach ($liveClass in $postseasonClasses) {
        try {
            & (Join-Path $PSScriptRoot "Update-IesaSeeds.ps1") -SitePath $liveClass.Path -ClassName $liveClass.Name -Year $SeasonYear
        } catch {
            if ($liveClass.EveryRun) { $seedRefreshError = $_ }
            Write-Warning "Class $($liveClass.Name) regional seed refresh failed: $($_.Exception.Message)"
        }
    }
}
if ($today -ge $bracketFrom) {
    foreach ($liveClass in $postseasonClasses) {
        try {
            & (Join-Path $PSScriptRoot "Update-IesaBracket.ps1") -SitePath $liveClass.Path -ClassName $liveClass.Name -Year $SeasonYear
        } catch {
            # Class 2A's bracket failure still fails the run, as before.
            if ($liveClass.EveryRun) { throw }
            Write-Warning "Class $($liveClass.Name) bracket refresh failed: $($_.Exception.Message)"
        }
    }

    # State results decide top-four placement, so refresh the year menu's
    # trophies from IESA's state tournament history once the finals are being
    # played, then the team index that maps schools to classes. This is
    # presentation only, and must never fail a score refresh.
    try {
        $siteRoot = Split-Path -Parent $PSScriptRoot
        $placementsScript = Join-Path $siteRoot "Build-IesaPlacements.ps1"
        if (Test-Path $placementsScript) {
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
if ($seedRefreshError) { throw $seedRefreshError }
