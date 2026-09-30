param(
    [string]$SitePath = "C:\inetpub\personalroot\IESA\2026"
)

$ErrorActionPreference = "Stop"
$directoryPage = Invoke-WebRequest -UseBasicParsing "https://www.iesa.org/activities/members.asp"
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

foreach ($grade in "7th", "8th") {
    $gradeLevel = $grade.Substring(0, 1)
    $teams = @{}
    $updatedGames = @()
    $previousTeams = @{}
    $previousCaptureAt = $null
    $previousPath = Join-Path $SitePath "scores-$grade.json"
    if (Test-Path -LiteralPath $previousPath) {
        $previousCache = Get-Content -Raw -LiteralPath $previousPath | ConvertFrom-Json
        $previousCaptureAt = $previousCache.updatedAt
        foreach ($property in $previousCache.teams.PSObject.Properties) {
            $previousTeams[$property.Name] = $property.Value
        }
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
            $page = Invoke-WebRequest -UseBasicParsing $sourceUrl
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
        }
    }
    $cache = [pscustomobject]@{
        updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm")
        previousCaptureAt = $previousCaptureAt
        teams = $teams
        updatedGames = @($updatedGames | Sort-Object team, opponent)
    }
    $json = $cache | ConvertTo-Json -Depth 6
    $json | Set-Content -Encoding UTF8 (Join-Path $SitePath "scores-$grade.json")
    ("window.iesaScoreCache = " + $json + ";") | Set-Content -Encoding UTF8 (Join-Path $SitePath "scores-$grade.js")
}

$today = (Get-Date).Date
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
