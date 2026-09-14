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
    $list = if ($grade -eq "7th") {
        [regex]::Match($script, "(?s)var teams=\[(.*?)\];return").Groups[1].Value
    } else {
        [regex]::Match($script, "(?s)var d=\[(.*?)\],h=").Groups[1].Value
    }
    [regex]::Matches($list, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
}

function Get-PlainText([string]$html) {
    ([System.Net.WebUtility]::HtmlDecode([regex]::Replace($html, "<[^>]+>", "")) -replace "\s+", " ").Trim()
}

foreach ($grade in "7th", "8th") {
    $gradeLevel = $grade.Substring(0, 1)
    $teams = @{}
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
            $teamName = [regex]::Escape((($team -replace "\s+\(Co-op\)", "")).Trim())
            $wins = @($games | Where-Object { $_.opponent -match ("^" + $teamName + ".*\sdef\.") }).Count
            $losses = @($games | Where-Object { $_.opponent -match ("\sdef\..*" + $teamName + "$") }).Count
            $teams[$team] = [pscustomobject]@{ sourceUrl = $sourceUrl; games = $games; record = [pscustomobject]@{ wins = $wins; losses = $losses; completed = $wins + $losses } }
        } catch {
            Write-Warning "Unable to refresh ${team}: $($_.Exception.Message)"
        }
    }
    $cache = [pscustomobject]@{ updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm"); teams = $teams }
    $json = $cache | ConvertTo-Json -Depth 6
    $json | Set-Content -Encoding UTF8 (Join-Path $SitePath "scores-$grade.json")
    ("window.iesaScoreCache = " + $json + ";") | Set-Content -Encoding UTF8 (Join-Path $SitePath "scores-$grade.js")
}
