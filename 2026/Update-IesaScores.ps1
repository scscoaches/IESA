param(
    [string]$SitePath = "C:\inetpub\personalroot\IESA\2026",
    [int]$RetentionDays = 7
)

$ErrorActionPreference = "Stop"
$today = (Get-Date).Date
if ($today -gt [datetime]::new(2026, 12, 18)) {
    throw "The 2026 season is complete; the scheduled score refresh ended after December 18."
}
$directoryPage = Invoke-WebRequest -UseBasicParsing "https://www.iesa.org/activities/members.asp" -TimeoutSec 30
$directory = @{}
foreach ($match in [regex]::Matches($directoryPage.Content, "(?is)<a href='memberdetail\.asp\?SchoolID=(\d+)'[^>]*>(.*?)</a>")) {
    $schoolName = ([regex]::Replace($match.Groups[2].Value, "<[^>]+>", "") -replace "\s+", " ").Trim().ToLowerInvariant()
    $directory[$schoolName] = $match.Groups[1].Value
}

function Get-Teams([string]$grade) {
    $script = Get-Content -Raw (Join-Path $SitePath "$grade\data.js")
    $match = if ($grade -eq "7th") {
        [regex]::Match($script, "(?s)\bvar\s+teams\s*=\s*\[(.*?)\]\s*;\s*return\s+teams\.map")
    } else {
        [regex]::Match($script, "(?s)\bvar\s+d\s*=\s*\[(.*?)\]\s*,\s*h\s*=")
    }
    if (!$match.Success) {
        throw "Unable to read regional teams from $grade\data.js."
    }
    [regex]::Matches($match.Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
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

foreach ($grade in "7th", "8th") {
    $gradeLevel = $grade.Substring(0, 1)
    $teams = @{}
    $updatedGames = @()
    $previousTeams = @{}
    $previousCaptureAt = $null
    $previousChanges = @()
    $runTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    $previousPath = Join-Path $SitePath "scores-$grade.json"
    if (Test-Path -LiteralPath $previousPath) {
        $previousCache = Get-Content -Raw -LiteralPath $previousPath | ConvertFrom-Json
        $previousCaptureAt = $previousCache.updatedAt
        foreach ($property in $previousCache.teams.PSObject.Properties) {
            $previousTeams[$property.Name] = $property.Value
        }
        $previousChanges = @($previousCache.updatedGames)
    }

    foreach ($team in Get-Teams $grade) {
        $lookup = ($team -replace "\s+\(Co-op\)", "").Trim().ToLowerInvariant()
        if (!$directory.ContainsKey($lookup)) {
            Write-Warning "No IESA member match found for $team."
            continue
        }
        $schoolId = $directory[$lookup]
        $sourceUrl = "https://www.iesa.org/activities/memberStats.asp?SchoolID=$schoolId&ActivityCode=GBK&GradeLevel=$gradeLevel"
        try {
            $page = Invoke-WebRequest -UseBasicParsing $sourceUrl -TimeoutSec 30
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
                if ($previousScore -ne $game.score) {
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
        } finally {
            Start-Sleep -Seconds 2
        }
    }
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $rollingChanges = @(Merge-ChangeWindow $previousChanges $updatedGames $cutoff $previousCaptureAt)
    $cache = [pscustomobject]@{
        updatedAt = $runTimestamp
        previousCaptureAt = $previousCaptureAt
        retainedSince = $cutoff.ToString("yyyy-MM-dd HH:mm")
        retainedDays = $RetentionDays
        teams = $teams
        updatedGames = $rollingChanges
    }
    $json = $cache | ConvertTo-Json -Depth 6
    Write-AtomicFile (Join-Path $SitePath "scores-$grade.json") $json
    Write-AtomicFile (Join-Path $SitePath "scores-$grade.js") ("window.iesaScoreCache = " + $json + ";")
}

$seedRefreshError = $null
if ($today -ge [datetime]::new(2026, 11, 12)) {
    try {
        & (Join-Path $PSScriptRoot "Update-IesaSeeds.ps1") -SitePath $SitePath
    } catch {
        $seedRefreshError = $_
        Write-Warning "Regional seed refresh failed: $($_.Exception.Message)"
    }
}
if ($today -ge [datetime]::new(2026, 11, 21)) {
    & (Join-Path $PSScriptRoot "Update-IesaBracket.ps1") -SitePath $SitePath
}
if ($seedRefreshError) { throw $seedRefreshError }
