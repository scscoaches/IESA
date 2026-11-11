#requires -Version 5.1
# End-to-end tests of 2026\Update-IesaScores.ps1 against a fake IESA site.
. (Join-Path $PSScriptRoot 'IesaTestHelpers.ps1')

function Clear-FullSweep([string]$root) {
    Get-ChildItem -Recurse -Filter 'scores-*.json' -Path (Join-Path $root '2026') | ForEach-Object {
        $cache = Get-Content -Raw $_.FullName | ConvertFrom-Json
        $cache.PSObject.Properties.Remove('fullSweepDate')
        $cache | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $_.FullName
    }
}

function Get-SchoolPageCount($run) { @($run.Requests | Where-Object { $_ -match 'memberStats' }).Count }
function Get-Lines($run, [string]$pattern) { @($run.Output -split "`n" | Where-Object { $_ -match $pattern }) }
function Get-Calls($run, [string]$stub) { @($run.Calls | Where-Object { $_ -match "^$stub\|" }) }

# Writes a bracket cache for every class: state games 1-8 decided when $complete,
# otherwise only the given quarterfinal losers.
function Set-StateResults([string]$root, [string]$grade, [switch]$complete, [string[]]$quarterfinalLosers = @()) {
    foreach ($folder in (Join-Path $root '2026'), (Join-Path $root '2026\1A'), (Join-Path $root '2026\3A'), (Join-Path $root '2026\4A')) {
        $games = [ordered]@{}
        if ($complete) {
            foreach ($n in 1..8) { $games["$n"] = [pscustomobject]@{ teams = @('A', 'B'); scores = @(30, 20); winner = 'A'; loser = 'B' } }
        }
        $i = 1
        foreach ($loser in $quarterfinalLosers) {
            $games["$i"] = [pscustomobject]@{ teams = @('Winner', $loser); scores = @(30, 20); winner = 'Winner'; loser = $loser }
            $i++
        }
        [pscustomobject]@{ regionals = [pscustomobject]@{}; sectionals = [pscustomobject]@{}; games = [pscustomobject]$games } |
            ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $folder "bracket-$grade.json")
    }
}

function Remove-StateResults([string]$root) {
    Get-ChildItem -Recurse -Filter 'bracket-*.json' -Path (Join-Path $root '2026') | Remove-Item
}

$root = New-MockSite
try {
    Write-Host 'First run of the day reads every class'
    Clear-FullSweep $root
    $run = Invoke-MockRefresh $root
    foreach ($class in '2A', '1A', '3A', '4A') {
        Assert-Equal 2 (Get-Lines $run "^$class (7th|8th): full daily check").Count "Class ${class}: full check for both grades"
    }
    Assert-True ((Get-SchoolPageCount $run) -gt 800) "all four classes read (about 830 school pages; read $(Get-SchoolPageCount $run))"
    Assert-Equal 1 @($run.Requests | Where-Object { $_ -match 'members\.asp' }).Count 'member directory read once'
    Assert-Equal 0 @($run.Requests | Where-Object { $_ -match 'assignments_Regional' }).Count 'no roster check once the brackets begin'
    Assert-Equal 0 (Get-Calls $run 'Update-Strength').Count 'no strength of schedule rebuild once the brackets begin'
    foreach ($stub in 'Update-IesaSeeds', 'Update-IesaBracket') {
        Assert-Equal 4 @($run.Calls | Where-Object { $_ -match "^$stub\|.*\|2026\|7th,8th$" }).Count "$stub called for each class, both grades, with the season year"
    }

    Write-Host 'Later runs that day read only the followed class'
    $run = Invoke-MockRefresh $root
    Assert-Equal 2 (Get-Lines $run '^2A (7th|8th): partial check').Count 'Class 2A partial check for both grades'
    Assert-Equal 0 (Get-Lines $run '^(1A|3A|4A) ').Count 'Classes 1A, 3A and 4A skipped'
    Assert-True ((Get-SchoolPageCount $run) -lt 230) "only 2A schools read (read $(Get-SchoolPageCount $run))"
    Assert-Equal 0 @($run.Requests | Where-Object { $_ -match 'assignments_Regional' }).Count 'no roster check after the daily full check'
    foreach ($stub in 'Update-IesaSeeds', 'Update-IesaBracket') {
        Assert-Equal 4 (Get-Calls $run $stub).Count "$stub still checks every class"
    }
    Assert-Equal 0 (Get-Calls $run 'Update-Strength').Count 'no strength of schedule rebuild'

    Write-Host 'The 9 PM postseason run reads every class''s remaining schools'
    $run = Invoke-MockRefresh $root '-Evening'
    Assert-Equal 8 (Get-Lines $run '^(1A|2A|3A|4A) (7th|8th): partial check').Count 'all four classes re-read, both grades'
    Assert-Equal 0 @($run.Calls | Where-Object { $_ -match '^Update-(Nfhs|Hudl)Events|^Update-Strength' }).Count 'no watch links or strength of schedule'
    Assert-Equal 4 (Get-Calls $run 'Update-IesaBracket').Count 'brackets checked for every class'

    Write-Host 'Eliminated schools are not re-read later in the day'
    $names = @((Get-Content -Raw (Join-Path $root '2026\scores-7th.json') | ConvertFrom-Json).teams.PSObject.Properties.Name | Select-Object -First 40)
    $regionals = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) { $regionals["$($i + 1)"] = [pscustomobject]@{ winner = 'X'; loser = $names[$i] } }
    [pscustomobject]@{ regionals = $regionals; sectionals = [pscustomobject]@{} } | ConvertTo-Json -Depth 4 |
        Set-Content -Encoding UTF8 (Join-Path $root '2026\bracket-7th.json')
    $run = Invoke-MockRefresh $root
    $line = @(Get-Lines $run '^2A 7th: partial check')
    Assert-True ($line.Count -eq 1 -and $line[0] -match 'reused 40\b') "40 eliminated 7th graders reused ($line)"
    Clear-FullSweep $root
    $run = Invoke-MockRefresh $root
    $line = @(Get-Lines $run '^2A 7th: full daily check')
    Assert-True ($line.Count -eq 1 -and $line[0] -match 'reused 40\b') "eliminated schools not re-read by the next morning's full check either ($line)"
    Remove-Item (Join-Path $root '2026\bracket-7th.json')

    Write-Host 'State quarterfinal losers are not re-read'
    $names = @((Get-Content -Raw (Join-Path $root '2026\scores-8th.json') | ConvertFrom-Json).teams.PSObject.Properties.Name | Select-Object -First 4)
    Set-StateResults $root '8th' -quarterfinalLosers $names
    $run = Invoke-MockRefresh $root
    $line = @(Get-Lines $run '^2A 8th: partial check')
    Assert-True ($line.Count -eq 1 -and $line[0] -match 'reused 4\b') "4 quarterfinal losers reused ($line)"
    Remove-StateResults $root

    Write-Host 'A finished grade is no longer requested'
    Set-StateResults $root '7th' -complete
    $run = Invoke-MockRefresh $root '-Evening'
    Assert-Equal 0 (Get-Lines $run '^(1A|2A|3A|4A) 7th:').Count 'no 7th-grade school pages read'
    Assert-Equal 4 (Get-Lines $run '^(1A|2A|3A|4A) 8th:').Count '8th grade still read in every class'
    Assert-Equal 4 @($run.Calls | Where-Object { $_ -match '^Update-IesaBracket\|.*\|8th$' }).Count 'brackets fetched for 8th grade only'
    Assert-True ($run.Output -notmatch 'state tournament is complete') 'season not reported complete while 8th grade plays'

    Write-Host 'After every state final, nothing is requested and the workflow is told to stop'
    Set-StateResults $root '8th' -complete
    $outputFile = Join-Path $root 'github-output.txt'
    $env:GITHUB_OUTPUT = $outputFile
    try { $run = Invoke-MockRefresh $root '-Force' } finally { Remove-Item Env:\GITHUB_OUTPUT }
    Assert-True ($run.Output -match 'state tournament is complete') 'reports every tournament complete'
    Assert-Equal 0 $run.Requests.Count 'no IESA requests at all'
    Assert-Equal 0 $run.Calls.Count 'no seed, bracket or strength scripts run'
    Assert-True ((Test-Path $outputFile) -and (Get-Content -Raw $outputFile) -match 'complete=true') 'complete=true written for the workflow'
    Remove-StateResults $root

    Write-Host 'A class''s first capture is a silent baseline'
    '{"updatedAt":null,"previousCaptureAt":null,"teams":{},"updatedGames":[],"rosterChanges":[]}' |
        Set-Content -Encoding UTF8 (Join-Path $root '2026\3A\scores-7th.json')
    $run = Invoke-MockRefresh $root '-Classes 3A -Force'
    $cache = Get-Content -Raw (Join-Path $root '2026\3A\scores-7th.json') | ConvertFrom-Json
    Assert-True (@($cache.teams.PSObject.Properties).Count -gt 50) '3A 7th schools captured'
    Assert-Equal 0 @($cache.updatedGames).Count 'no "new score" entries on the first capture'
    $cache = Get-Content -Raw (Join-Path $root '2026\scores-7th.json') | ConvertFrom-Json
    Assert-True (@($cache.updatedGames).Count -gt 0) 'a class with earlier captures still reports changed scores'

    Write-Host '-Classes limits a manual run'
    $run = Invoke-MockRefresh $root '-Classes 1A -Force'
    Assert-Equal 2 (Get-Lines $run '^1A (7th|8th): full daily check').Count 'Class 1A refreshed'
    Assert-Equal 0 (Get-Lines $run '^(2A|3A|4A) ').Count 'other classes untouched'
    Assert-Equal 0 @($run.Calls | Where-Object { $_ -match '^Update-(Nfhs|Hudl)Events' }).Count 'stream links (followed class) not refreshed'

    Write-Host 'Season dates come from live-season.json'
    '{"year":2026,"followedClass":"2A","gamesFrom":"2100-01-01","seedsFrom":"2026-01-01","bracketFrom":"2026-01-01","endDate":"2100-12-31"}' |
        Set-Content -Encoding UTF8 (Join-Path $root 'live-season.json')
    $run = Invoke-MockRefresh $root '-Force'
    Assert-True ($run.Output -match 'nothing to check yet' -and $run.Requests.Count -eq 0 -and $run.Calls.Count -eq 0) 'nothing requested before "Games may begin"'
    '{"year":2026,"followedClass":"2A","gamesFrom":"2026-01-01","seedsFrom":"2026-01-01","bracketFrom":"2026-01-01","endDate":"2100-12-31","grades":{"7th":{"seedsFrom":"2026-01-01","bracketFrom":"2026-01-01"},"8th":{"seedsFrom":"2100-01-01","bracketFrom":"2100-01-01"}}}' |
        Set-Content -Encoding UTF8 (Join-Path $root 'live-season.json')
    $run = Invoke-MockRefresh $root '-Force'
    Assert-Equal 4 @($run.Calls | Where-Object { $_ -match '^Update-IesaSeeds\|.*\|7th$' }).Count 'seeds for the grade past its ranking date only'
    Assert-Equal 4 @($run.Calls | Where-Object { $_ -match '^Update-IesaBracket\|.*\|7th$' }).Count 'results for the grade past its first regional only'
    '{"year":2026,"followedClass":"2A","seedsFrom":"2100-01-01","bracketFrom":"2100-01-01","endDate":"2100-12-31"}' |
        Set-Content -Encoding UTF8 (Join-Path $root 'live-season.json')
    $run = Invoke-MockRefresh $root '-Force'
    Assert-Equal 0 @($run.Calls | Where-Object { $_ -match '^Update-Iesa(Seeds|Bracket)' }).Count 'no seed or bracket refresh before their dates'
    Assert-Equal 8 @($run.Requests | Where-Object { $_ -match 'assignments_Regional.*Year=2026' }).Count 'roster check before the brackets: two assignment pages per class, current year'
    Assert-Equal 4 @($run.Calls | Where-Object { $_ -match '^Update-Strength\|.*\|2026\|' }).Count 'strength of schedule per class with the season year before the brackets'
    '{"year":2026,"followedClass":"2A","seedsFrom":"2026-01-01","bracketFrom":"2026-01-01","endDate":"2026-01-02"}' |
        Set-Content -Encoding UTF8 (Join-Path $root 'live-season.json')
    $run = Invoke-MockRefresh $root '-Force'
    Assert-True ($run.Output -match 'season is complete' -and $run.Requests.Count -eq 0) 'no requests after the season''s end date'
} finally {
    Remove-Item -Recurse -Force -LiteralPath $root -ErrorAction SilentlyContinue
}
Get-TestResult
