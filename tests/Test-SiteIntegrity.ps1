#requires -Version 5.1
# Static checks of the published site: catalogue, pages, version stamps and
# the data files the browser reads. No network.
. (Join-Path $PSScriptRoot 'IesaTestHelpers.ps1')
. (Join-Path $script:RepoRoot 'IesaSitePages.ps1')

$root = $script:RepoRoot
$seasons = @(Read-IesaCatalogue $root)
$live = Get-Content -Raw (Join-Path $root 'live-season.json') | ConvertFrom-Json
$siteVersion = Get-IesaSiteVersion $root

Write-Host 'Season catalogue'
Assert-Equal $seasons.Count @($seasons.year | Select-Object -Unique).Count 'one entry per year'
$bad = @($seasons | Where-Object {
    $classes = if ($_.PSObject.Properties['classes']) { @($_.classes) } else { @($_.className) }
    $allowed = if ($_.year -le 1989) { @($null) } elseif ($_.year -le 2005) { @('A', 'AA') } else { @('1A', '2A', '3A', '4A') }
    @($classes | Where-Object { $_ -notin $allowed }).Count -or ($_.className -notin $allowed)
})
Assert-Equal 0 $bad.Count "classes valid for each era ($(@($bad.year) -join ', '))"
$liveEntry = $seasons | Where-Object { $_.year -eq [int]$live.year }
Assert-True ($liveEntry -and !$liveEntry.archived) "live-season.json year $($live.year) is the catalogue's live season"
Assert-Equal 1 @($seasons | Where-Object { !$_.archived }).Count 'exactly one live season'
foreach ($date in $live.seedsFrom, $live.bracketFrom, $live.endDate) {
    $parsed = [datetime]::MinValue
    Assert-True ([datetime]::TryParseExact($date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$parsed)) "live-season date $date parses"
}

Write-Host 'Every listed class has its pages and data'
$missing = @()
foreach ($season in $seasons) {
    $classes = if ($season.PSObject.Properties['classes']) { @($season.classes) } elseif ($season.className) { @($season.className) } else { @('') }
    $grades = if ($season.year -le 1985) { @('combined') } else { @('7th', '8th') }
    foreach ($className in $classes) {
        $folder = Join-Path $root (Get-IesaClassFolder $root ([int]$season.year) $className)
        foreach ($grade in $grades) {
            foreach ($file in 'index.html', 'data.js') {
                if (!(Test-Path -LiteralPath (Join-Path $folder "$grade\$file"))) { $missing += "$($season.year) $className $grade\$file" }
            }
        }
    }
}
Assert-Equal 0 $missing.Count "no missing pages or data ($(@($missing | Select-Object -First 5) -join '; '))"

Write-Host 'Bracket pages'
$pages = @(Get-ChildItem -Directory -LiteralPath $root | Where-Object { $_.Name -match '^\d{4}$' } |
    ForEach-Object { Get-ChildItem -Recurse -Filter index.html -LiteralPath $_.FullName } |
    Where-Object { (Get-Content -Raw $_.FullName) -match 'season-selector\.js' })
Assert-True ($pages.Count -gt 200) "bracket pages found ($($pages.Count))"
$placeholders = @($pages | Where-Object { (Get-Content -Raw $_.FullName) -match '\{\{' })
Assert-Equal 0 $placeholders.Count 'no unreplaced template placeholders'
$stale = @($pages | Where-Object { (Get-Content -Raw $_.FullName) -notmatch "name=`"iesa-site-version`" content=`"$siteVersion`"" })
Assert-Equal 0 $stale.Count "every page stamped with site version $siteVersion ($(@($stale | Select-Object -First 3 | ForEach-Object { $_.FullName.Replace($root, '') }) -join '; '))"
foreach ($asset in 'styles\.css', 'app\.js', 'season-selector\.js', 'my-team\.js') {
    $versions = @($pages | ForEach-Object { [regex]::Match((Get-Content -Raw $_.FullName), "$asset\?v=\d+").Value } | Where-Object { $_ } | Select-Object -Unique)
    Assert-True ($versions.Count -le 1) "one $($asset -replace '\\', '') version across pages ($($versions -join ', '))"
}

Write-Host 'Data the browser reads'
$teams = Get-Content -Raw (Join-Path $root 'teams.json') | ConvertFrom-Json
Assert-Equal @($teams.names).Count @($teams.names | Select-Object -Unique).Count 'team names unique'
$badAlias = @($teams.aliases.PSObject.Properties | Where-Object { $_.Value -lt 0 -or $_.Value -ge @($teams.names).Count })
Assert-Equal 0 $badAlias.Count 'team aliases point at real schools'
Assert-True (@($teams.names | Where-Object { $_ -match '\(\d+-\d+\)|\s{2}' }).Count -eq 0) 'no records or double spaces in team names'
$placements = Get-Content -Raw (Join-Path $root 'placements.json') | ConvertFrom-Json
Assert-True (@($placements.results).Count -ge 231) "state history complete ($(@($placements.results).Count) tournaments)"
Assert-Equal 0 @($placements.results | Where-Object { @($_.places).Count -ne 4 }).Count 'every tournament lists four places'
Get-TestResult
