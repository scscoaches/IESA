#requires -Version 5.1
<#
.SYNOPSIS
    Records the top four finishers of every IESA girls basketball state tournament.

.DESCRIPTION
    The season drop-down lists close to fifty years, which makes the handful of
    seasons worth revisiting impossible to spot. This reads IESA's official
    State Tournament Winners history and writes placements.json, which
    season-selector.js and my-team.js use to mark the years in which the
    visitor's chosen team finished in the top four with a trophy.

    The history page (activities/gbk/winners.asp) lists the champion, runner-up,
    third and fourth place school for every class and year since 1979. Every
    class is stored, so any school's finishes can be found in the browser.

    Nothing is written unless every class page is read and validated, so an
    outage or layout change can never replace good placements with fewer.

    IESA updates the history after the state finals, so a current-season finish
    appears once IESA publishes it.
#>
param(
    [string]$SiteRoot = "C:\inetpub\personalroot\IESA"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "2026\IesaRequest.ps1")

$historyUrl = "https://www.iesa.org/activities/gbk/winners.asp"

# Each class IESA has used, the years it covers, the grade page on this site it
# belongs to and the class name the site uses. Before 1986 one tournament
# combined both grades, and 1986-1989 had one class per grade.
$classes = @(
    @{ Code = "Single"; Grade = "combined"; ClassName = $null; First = 1979; Last = 1985 }
    @{ Code = "7";      Grade = "7th";      ClassName = $null; First = 1986; Last = 1989 }
    @{ Code = "8";      Grade = "8th";      ClassName = $null; First = 1986; Last = 1989 }
    @{ Code = "7A";     Grade = "7th";      ClassName = "A";   First = 1990; Last = 2005 }
    @{ Code = "7AA";    Grade = "7th";      ClassName = "AA";  First = 1990; Last = 2005 }
    @{ Code = "8A";     Grade = "8th";      ClassName = "A";   First = 1990; Last = 2005 }
    @{ Code = "8AA";    Grade = "8th";      ClassName = "AA";  First = 1990; Last = 2005 }
    @{ Code = "7-1A";   Grade = "7th";      ClassName = "1A";  First = 2006; Last = $null }
    @{ Code = "7-2A";   Grade = "7th";      ClassName = "2A";  First = 2006; Last = $null }
    @{ Code = "7-3A";   Grade = "7th";      ClassName = "3A";  First = 2006; Last = $null }
    @{ Code = "7-4A";   Grade = "7th";      ClassName = "4A";  First = 2006; Last = $null }
    @{ Code = "8-1A";   Grade = "8th";      ClassName = "1A";  First = 2006; Last = $null }
    @{ Code = "8-2A";   Grade = "8th";      ClassName = "2A";  First = 2006; Last = $null }
    @{ Code = "8-3A";   Grade = "8th";      ClassName = "3A";  First = 2006; Last = $null }
    @{ Code = "8-4A";   Grade = "8th";      ClassName = "4A";  First = 2006; Last = $null }
)

function Get-CellText([string]$html) {
    [System.Net.WebUtility]::HtmlDecode(($html -replace '<[^>]+>', '')).Trim() -replace '\s+', ' '
}

function Get-ClassHistory($class) {
    $url = "${historyUrl}?Class=$([uri]::EscapeDataString($class.Code))"
    $page = Invoke-IesaPage $url
    $html = [string]$page.Content
    if ($page.StatusCode -ne 200 -or $html -notmatch 'State Tournament Winners') {
        throw "Unexpected IESA page at $url"
    }
    # The page silently falls back to its default class for an unknown code.
    $subtitle = [regex]::Match($html, "(?is)<td\s+class=['""]TableSubtitle['""][^>]*>(.*?)</td>")
    $label = Get-CellText $subtitle.Groups[1].Value
    $expected = switch ($class.Code) {
        "Single" { "1979-1985" }
        "7" { "7th Grade: 1986-1989" }
        "8" { "8th Grade: 1986-1989" }
        default { "Class $($class.Code): $($class.First)-" }
    }
    if (!$subtitle.Success -or !$label.StartsWith($expected)) {
        throw "IESA returned '$label' instead of class $($class.Code) at $url"
    }
    if ($html -notmatch '(?is)<th>\s*Champion\s*</th>.*?<th>\s*Runner Up\s*</th>.*?<th>\s*Third Place\s*</th>.*?<th>\s*Fourth Place\s*</th>') {
        throw "Class $($class.Code) history no longer has champion through fourth place columns at $url"
    }

    $rows = @(foreach ($row in [regex]::Matches($html, "(?is)<tr>\s*(<td\s+class=['""]Label['""].*?)</tr>")) {
        $cells = @([regex]::Matches($row.Groups[1].Value, "(?is)<td[^>]*>(.*?)</td>") |
            ForEach-Object { Get-CellText $_.Groups[1].Value })
        if ($cells.Count -ne 7 -or $cells[0] -notmatch '^\d{4}$') {
            throw "Unreadable class $($class.Code) history row: $($cells -join ' | ')"
        }
        $year = [int]$cells[0]
        if ($year -lt $class.First -or ($class.Last -and $year -gt $class.Last)) {
            throw "Class $($class.Code) history lists $year, outside $($class.First)-$($class.Last)"
        }
        [pscustomobject]@{ Year = $year; Places = @($cells[1], $cells[4], $cells[5], $cells[6]) }
    })
    if (!$rows.Count) { throw "Class $($class.Code) history at $url has no seasons." }
    if (@($rows.Year | Sort-Object -Unique).Count -ne $rows.Count) {
        throw "Class $($class.Code) history lists a season more than once."
    }
    [pscustomobject]@{ Url = $url; Rows = $rows }
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($class in $classes) {
    $history = Get-ClassHistory $class
    foreach ($row in $history.Rows) {
        $results.Add([pscustomobject][ordered]@{
            year = $row.Year
            grade = $class.Grade
            className = $class.ClassName
            code = $class.Code
            places = @($row.Places | ForEach-Object { if ($_) { $_ } else { $null } })
            source = $history.Url
        })
    }
}

$output = [ordered]@{
    source = $historyUrl
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    results = @($results | Sort-Object @{ Expression = 'year'; Descending = $true }, grade, code)
}

$destination = Join-Path $SiteRoot "placements.json"
$temporary = "$destination.tmp"
[System.IO.File]::WriteAllText($temporary, ($output | ConvertTo-Json -Depth 5 -Compress),
    [System.Text.UTF8Encoding]::new($false))
Move-Item -Force $temporary $destination

Write-Host "Recorded $($results.Count) state tournaments from IESA's history ($($classes.Count) classes)."
