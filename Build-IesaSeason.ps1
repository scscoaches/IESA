param(
    [Parameter(Mandatory)][ValidateRange(2006, 2100)][int]$Year,
    [Parameter(Mandatory)][ValidateSet('1A', '2A', '3A', '4A')][string]$ClassName,
    [string]$OutputRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    throw "Output root does not exist: $OutputRoot"
}

function Get-Text([string]$html) {
    ([System.Net.WebUtility]::HtmlDecode([regex]::Replace($html, '(?is)<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
}

function Get-OfficialPage([string]$url, [string]$marker) {
    $page = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 30
    if ($page.StatusCode -ne 200 -or $page.Content -notmatch [regex]::Escape($marker)) {
        throw "Unexpected IESA page at $url"
    }
    return [string]$page.Content
}

function Get-Assignments([string]$html, [string]$grade) {
    $sectionHeaders = @([regex]::Matches($html,
        "(?is)<td\s+class=['""]TableSubtitle['""][^>]*>\s*Sectional\s+(\d+)\b"))
    $early = $Year -le 2008
    if ($sectionHeaders.Count -gt 8 -or (!$early -and $sectionHeaders.Count -ne 8) -or
        ($early -and $sectionHeaders.Count -lt 1)) {
        throw "$grade $Year expected 8 sectionals; found $($sectionHeaders.Count)"
    }
    $sectionals = @()
    $regionals = @()
    if ($early) {
        $sectionals = @(1..8 | ForEach-Object {
            [pscustomobject]@{ id = $_; regionals = @((2 * $_ - 1), (2 * $_)); host = ''; date = '' }
        })
        $regionals = @(1..16 | ForEach-Object {
            [pscustomobject]@{ id = $_; sectional = [int][math]::Ceiling($_ / 2); host = ''; teams = @() }
        })
    }
    $seen = @{}
    for ($i = 0; $i -lt $sectionHeaders.Count; $i++) {
        $id = [int]$sectionHeaders[$i].Groups[1].Value
        if ($id -lt 1 -or $id -gt 8 -or $seen.ContainsKey($id) -or (!$early -and $id -ne $i + 1)) {
            throw "$grade $Year unexpected sectional number"
        }
        $seen[$id] = $true
        $end = if ($i -lt $sectionHeaders.Count - 1) { $sectionHeaders[$i + 1].Index } else { $html.Length }
        $block = $html.Substring($sectionHeaders[$i].Index, $end - $sectionHeaders[$i].Index)
        $location = [regex]::Match($block, "(?is)<td\s+class=['""]Location['""][^>]*>(.*?)</td>")
        if (!$location.Success -and !$early) { throw "$grade $Year missing Sectional $id location" }
        $hostMatch = if ($location.Success) {
            [regex]::Match($location.Groups[1].Value, '(?is)<b>\s*Host:\s*</b>\s*(.*?)\s*<br')
        } else {
            [regex]::Match($block, '(?is)<td\s+class=[''"]TableSubtitle[''"][^>]*>\s*Sectional\s+\d+\s*@\s*([^<]+)')
        }
        $sectionHost = if ($hostMatch.Success) { Get-Text $hostMatch.Groups[1].Value } else { '' }
        $date = ''
        if ($location.Success) {
            $when = [regex]::Match((Get-Text $location.Groups[1].Value),
                '(?i)(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\s*[A-Za-z.]+\s+\d+,?\s+\d{4}(?:,?\s*\d{1,2}:\d{2}\s*[AP]M)?')
            if ($when.Success) { $date = $when.Value }
        }
        $sectional = [pscustomobject]@{
            id = $id
            regionals = @((2 * $id - 1), (2 * $id))
            host = $sectionHost
            date = $date
        }
        if ($early) { $sectionals[$id - 1] = $sectional } else { $sectionals += $sectional }
        $regionalHeaders = @([regex]::Matches($block,
            "(?is)<td\s+class=['""]TableSubtitle2['""][^>]*>\s*Regional\s+(\d+)\s*</td>"))
        if ($regionalHeaders.Count -ne 2) {
            throw "$grade $Year Sectional $id expected 2 regionals; found $($regionalHeaders.Count)"
        }
        for ($j = 0; $j -lt 2; $j++) {
            $number = 2 * ($id - 1) + $j + 1
            if ([int]$regionalHeaders[$j].Groups[1].Value -ne $number) {
                throw "$grade $Year unexpected regional number in Sectional $id"
            }
            $regionalEnd = if ($j -eq 0) { $regionalHeaders[1].Index } else { $block.Length }
            $regionalBlock = $block.Substring($regionalHeaders[$j].Index,
                $regionalEnd - $regionalHeaders[$j].Index)
            $list = [regex]::Match($regionalBlock,
                "(?is)<td\s+class=['""]ListData['""][^>]*>(.*?)</td>")
            if (!$list.Success) { throw "$grade $Year Regional $number has no team list" }
            $teams = @()
            $listedTeams = @()
            $nonCompetitors = @()
            $regionalHost = 'TBD'
            foreach ($line in [regex]::Split($list.Groups[1].Value, '(?i)<br\s*/?>')) {
                $name = (Get-Text $line) -replace '(?i)\(\s*Host Info\s*\)', ''
                $name = $name.Trim()
                if (!$name) { continue }
                $listedTeams += $name
                if ($line -match 'RegPlaqueInfo\.pdf') {
                    if ($regionalHost -ne 'TBD') { throw "$grade $Year Regional $number has multiple hosts" }
                    $regionalHost = $name
                }
                if ($name -match '(?i)\(NON-COMPETITOR\)') {
                    $nonCompetitors += ($name -replace '(?i)\s*\(NON-COMPETITOR\)', '')
                    continue
                }
                $teams += $name
            }
            if ($teams.Count -lt 2 -or $teams.Count -gt 8 -or
                @($teams | Select-Object -Unique).Count -ne $teams.Count) {
                throw "$grade $Year Regional $number has invalid schools"
            }
            $regional = [pscustomobject]@{
                id = $number
                sectional = $id
                host = $regionalHost
                teams = $teams
            }
            if ($nonCompetitors.Count) {
                $regional | Add-Member -NotePropertyName assignedTeams -NotePropertyValue $listedTeams
            }
            if ($early) { $regionals[$number - 1] = $regional } else { $regionals += $regional }
        }
    }
    return [pscustomobject]@{ regionals = $regionals; sectionals = $sectionals }
}

function Get-CalendarSchedule([string]$html, [string]$grade) {
    $header = [regex]::Match($html, "(?is)GIRLS BASKETBALL $grade GRADE")
    if (!$header.Success) { throw "Official calendar is missing $grade girls basketball" }
    $remaining = $html.Substring($header.Index)
    $nextGrade = [regex]::Match($remaining.Substring($header.Length), '(?is)GIRLS BASKETBALL [78]th GRADE')
    $scope = if ($nextGrade.Success) {
        $remaining.Substring(0, $header.Length + $nextGrade.Index)
    } else { $remaining }
    $yearColumns = @([regex]::Matches($scope, '<th>\s*(\d{4})-\d{4}\s*</th>') |
        ForEach-Object { [int]$_.Groups[1].Value })
    $column = [array]::IndexOf($yearColumns, $Year)
    if ($column -lt 0) { return $null }
    $state = [regex]::Match($scope, "(?is)<td\s+class=['""]Label['""]>\s*State \(Sat\.[^)]*Thur\.\).*?</tr>")
    if (!$state.Success) { throw "Calendar has no $grade state dates for $Year" }
    $dates = @([regex]::Matches($state.Value, "(?is)<td\s+class=['""]ListData['""]>(.*?)</td>") |
        ForEach-Object { Get-Text $_.Groups[1].Value })
    if ($dates.Count -le $column) { throw "Calendar has no $grade $Year state date column" }
    $match = [regex]::Match($dates[$column], '^(?<month>[A-Za-z.]+)\s*(?<first>\d{1,2}),\s*(?<last>\d{1,2}),\s*(?<year>\d{4})$')
    if (!$match.Success -or [int]$match.Groups['year'].Value -ne $Year) {
        throw "Unexpected calendar $grade $Year state dates: $($dates[$column])"
    }
    $month = $match.Groups['month'].Value
    $first = $match.Groups['first'].Value
    $last = $match.Groups['last'].Value
    return [pscustomobject]@{
        label = "$month $first & $last, $Year"
        first = "$month $first, $Year"
        last = "$month $last, $Year"
    }
}

function Add-BracketEntrant([object]$assignments, [int]$regionalId, [string]$school) {
    $regional = $assignments.regionals[$regionalId - 1]
    if ($regional.id -ne $regionalId -or $school -in $regional.teams -or
        $regional.PSObject.Properties['assignedTeams']) {
        throw "Review the published Regional $regionalId assignment before adding $school"
    }
    $regional | Add-Member -NotePropertyName assignedTeams -NotePropertyValue @($regional.teams)
    $regional.teams = @($regional.teams) + @($school)
}

function Get-TeamKey([string]$name) {
    (($name -replace '(?i)\s+\(Co-?op\)$', '' -replace '\s+', ' ').Trim()).ToLowerInvariant()
}

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("iesa-season-$Year-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    $calendarHtml = Get-OfficialPage 'https://www.iesa.org/activities/calendar.asp?activitycode=GBK' 'GIRLS BASKETBALL'
    foreach ($grade in @('7th', '8th')) {
        $gradeNumber = $grade.Substring(0, 1)
        $assignmentUrl = "https://www.iesa.org/activities/gbk/assignments_Regional.asp?Year=$Year&Class=$gradeNumber-$ClassName"
        $html = Get-OfficialPage $assignmentUrl "$Year Class $gradeNumber-$ClassName Regional Assignments"
        $assignments = Get-Assignments $html $grade
        if ($Year -eq 2021 -and $ClassName -eq '1A' -and $grade -eq '8th') {
            $regional = $assignments.regionals[15]
            $assigned = @($regional.teams)
            $expected = @('Millstadt St. James', 'Mt. Olive', 'Mulberry Grove JHS',
                'Pocahontas', 'Ramsey (Co-op)')
            if ($regional.id -ne 16 -or @($assigned | Where-Object { $_ -notin $expected }).Count -or
                @($expected | Where-Object { $_ -notin $assigned }).Count) {
                throw "2021 8th Regional 16 assignment changed; review the Brussels bracket exception"
            }
            Add-BracketEntrant $assignments 16 'Brussels'
        }
        if ($Year -eq 2024 -and $ClassName -eq '2A') {
            Add-BracketEntrant $assignments 5 'Bement'
            Add-BracketEntrant $assignments 6 'Armstrong-Ellis'
        }
        $directory = Join-Path $staging $grade
        New-Item -ItemType Directory -Path $directory | Out-Null
        $data = [pscustomobject]@{
            year = $Year
            grade = $grade
            className = $ClassName
            archived = $true
            regionals = $assignments.regionals
            sectionals = $assignments.sectionals
        }
        $data | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $directory 'data.json')
    }

    & (Join-Path $PSScriptRoot '2026\Update-IesaSeeds.ps1') -Year $Year -ClassName $ClassName `
        -SitePath $staging -OutputPath $staging -AllowBracketParticipants:($Year -le 2019)
    if ($Year -le 2019) {
        foreach ($grade in @('7th', '8th')) {
            $dataPath = Join-Path (Join-Path $staging $grade) 'data.json'
            $data = Get-Content -Raw -LiteralPath $dataPath | ConvertFrom-Json
            $seedData = Get-Content -Raw -LiteralPath (Join-Path $staging "regional-seeds-$grade.json") | ConvertFrom-Json
            foreach ($regional in $data.regionals) {
                $publishedBracket = $seedData.regionalBrackets.("$($regional.id)")
                $published = @($publishedBracket.seeds)
                if ($published.Count -lt 2 -or $published.Count -gt 8) {
                    throw "$Year $grade Regional $($regional.id) has an invalid published bracket roster"
                }
                $assigned = @($regional.teams)
                $bracketTeams = @($published | ForEach-Object { $_.team })
                $added = @($bracketTeams | Where-Object { (Get-TeamKey $_) -notin @($assigned | ForEach-Object { Get-TeamKey $_ }) })
                $omitted = @($assigned | Where-Object { (Get-TeamKey $_) -notin @($bracketTeams | ForEach-Object { Get-TeamKey $_ }) })
                if (($added.Count -or $omitted.Count) -and
                    !$regional.PSObject.Properties['assignedTeams']) {
                    $regional | Add-Member -NotePropertyName assignedTeams -NotePropertyValue $assigned
                }
                $regional.teams = $bracketTeams
                if ($publishedBracket.missingSeed -eq 1) {
                    $regional | Add-Member -NotePropertyName note -NotePropertyValue (
                        'Published bracket leaves the first seed and regional final unresolved.')
                }
            }
            $data | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $dataPath
        }
    }
    & (Join-Path $PSScriptRoot '2026\Update-IesaBracket.ps1') -Year $Year -ClassName $ClassName `
        -SitePath $staging -OutputPath $staging

    $template = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'archive-grade-template.html')
    $seasonPage = (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'archive-season-template.html')).
        Replace('{{YEAR}}', "$Year").Replace('{{CLASS}}', $ClassName)
    $seasonPage | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $staging 'index.html')
    foreach ($grade in @('7th', '8th')) {
        $gradeNumber = $grade.Substring(0, 1)
        $directory = Join-Path $staging $grade
        $dataPath = Join-Path $directory 'data.json'
        $data = Get-Content -Raw -LiteralPath $dataPath | ConvertFrom-Json
        $bracket = Get-Content -Raw -LiteralPath (Join-Path $staging "bracket-$grade.json") | ConvertFrom-Json
        $seeds = Get-Content -Raw -LiteralPath (Join-Path $staging "regional-seeds-$grade.json") | ConvertFrom-Json
        if (@($bracket.quarterfinalMatchups.PSObject.Properties).Count -ne 4 -or
            @($seeds.regionalBrackets.PSObject.Properties | Where-Object { $_.Value.seeds.Count -gt 0 }).Count -ne 16) {
            throw "$grade $Year has incomplete IESA quarterfinal pairings or regional seeds"
        }
        if ($Year -eq 2021 -and $ClassName -eq '1A' -and $grade -eq '8th' -and
            (@($seeds.regionalBrackets.'16'.seeds | Where-Object { $_.team -eq 'Brussels' }).Count -ne 1 -or
             $bracket.regionals.'16'.loser -ne 'Brussels' -or
             $bracket.regionals.'16'.winner -ne 'Mt. Olive')) {
            throw '2021 8th Regional 16 bracket and qualifier disagree about Brussels'
        }
        if ($Year -eq 2024 -and $ClassName -eq '2A') {
            foreach ($extra in @(@(5, 'Bement'), @(6, 'Armstrong-Ellis'))) {
                if (@($seeds.regionalBrackets.("$($extra[0])").seeds |
                    Where-Object { $_.team -eq $extra[1] }).Count -ne 1) {
                    throw "2024 $grade Regional $($extra[0]) bracket lacks $($extra[1])"
                }
            }
        }
        foreach ($sectional in $data.sectionals) {
            $records = [ordered]@{}
            foreach ($regionalId in $sectional.regionals) {
                $entry = $bracket.sectionalPairingRecords.("$regionalId")
                $winner = $bracket.regionals.("$regionalId").winner
                if (!$entry -or !$winner) { continue }
                if ((Get-TeamKey $entry.team) -ne (Get-TeamKey $winner) -or
                    $entry.record -notmatch '^\d+-\d+$') {
                    throw "$grade $Year Sectional $($sectional.id) pairing record disagrees with Regional $regionalId"
                }
                $records["$regionalId"] = $entry.record
            }
            if ($records.Count) {
                $sectional | Add-Member -NotePropertyName records -NotePropertyValue $records
            }
        }
        foreach ($regional in $data.regionals) {
            $bracketHost = $seeds.regionalBrackets.("$($regional.id)").host
            if (!$bracketHost -and $Year -gt 2019) {
                throw "$grade $Year Regional $($regional.id) has no published bracket host"
            }
            if ($regional.host -eq 'TBD') { $regional.host = $bracketHost }
        }
        $stateUrl = "https://www.iesa.org/activities/gbk/scoreboards/index.asp?Year=$Year&Class=$gradeNumber-$ClassName"
        $stateHtml = Get-OfficialPage $stateUrl "$($gradeNumber)th Grade Class $ClassName  State Tournament"
        $header = [regex]::Match($stateHtml,
            "(?is)$($gradeNumber)th Grade Class $ClassName\s+State Tournament(.*?)(?:First Round|Quarterfinals)")
        if (!$header.Success) { throw "Missing $grade $Year state venue" }
        $venueMatch = [regex]::Match($header.Groups[1].Value, '(?is)@\s*([^<\r\n]+)')
        $venue = if ($venueMatch.Success) { Get-Text $venueMatch.Groups[1].Value } else { 'Venue unavailable from IESA' }
        $schedule = Get-CalendarSchedule $calendarHtml $grade
        $firstDate = if ($schedule) { $schedule.first } else { '' }
        $finalDate = if ($schedule) { $schedule.last } else { '' }

        $pairings = @(1..4 | ForEach-Object {
            $pair = @($bracket.quarterfinalMatchups."$_")
            $unmappedStateEntrant = $Year -eq 2008 -and $grade -eq '8th' -and $_ -eq 2 -and
                $pair.Count -eq 2 -and $null -eq $pair[0] -and $pair[1] -eq 1 -and
                $bracket.games.'2'.teams[0] -eq 'Decatur St. Patrick'
            if ($pair.Count -ne 2 -or (!$unmappedStateEntrant -and
                @($pair | Where-Object { $null -eq $_ }).Count)) {
                throw "$grade $Year missing Game $_ pairing"
            }
            [pscustomobject]@{ game = $_; matchup = $pair; date = $firstDate; time = '' }
        })
        $data | Add-Member -NotePropertyName venue -NotePropertyValue $venue
        $data | Add-Member -NotePropertyName stateDate -NotePropertyValue $(if ($schedule) { $schedule.label } else { '' })
        $data | Add-Member -NotePropertyName quarterfinals -NotePropertyValue $pairings
        $data | Add-Member -NotePropertyName semifinals -NotePropertyValue @(
            [pscustomobject]@{ game = 5; matchup = @(1, 2); date = $firstDate; time = '' },
            [pscustomobject]@{ game = 6; matchup = @(3, 4); date = $firstDate; time = '' }
        )
        $data | Add-Member -NotePropertyName thirdPlace -NotePropertyValue ([pscustomobject]@{ date = $finalDate; time = '' })
        $data | Add-Member -NotePropertyName championship -NotePropertyValue ([pscustomobject]@{ date = $finalDate; time = '' })
        $json = $data | ConvertTo-Json -Depth 10
        $json | Set-Content -Encoding UTF8 -LiteralPath $dataPath
        ("window.tournamentData = " + $json + ";") |
            Set-Content -Encoding UTF8 -LiteralPath (Join-Path $directory 'data.js')
        $page = $template.Replace('{{YEAR}}', "$Year").Replace('{{CLASS}}', $ClassName).
            Replace('{{GRADE}}', $grade).
            Replace('{{SEVENTH_ACTIVE}}', $(if ($grade -eq '7th') { 'class="active"' } else { '' })).
            Replace('{{EIGHTH_ACTIVE}}', $(if ($grade -eq '8th') { 'class="active"' } else { '' }))
        $page | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $directory 'index.html')
    }

    $destination = Join-Path $OutputRoot "$Year"
    if (!(Test-Path -LiteralPath $destination)) {
        New-Item -ItemType Directory -Path $destination | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $staging 'index.html') `
        -Destination (Join-Path $destination 'index.html') -Force
    foreach ($grade in @('7th', '8th')) {
        $target = Join-Path $destination $grade
        if (!(Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target | Out-Null }
        foreach ($file in @('data.json', 'data.js', 'index.html')) {
            Copy-Item -LiteralPath (Join-Path (Join-Path $staging $grade) $file) `
                -Destination (Join-Path $target $file) -Force
        }
        foreach ($prefix in @('bracket', 'regional-seeds')) {
            foreach ($extension in @('json', 'js')) {
                $file = "$prefix-$grade.$extension"
                Copy-Item -LiteralPath (Join-Path $staging $file) `
                    -Destination (Join-Path $destination $file) -Force
            }
        }
    }
    [pscustomobject]@{ year = $Year; className = $ClassName } | ConvertTo-Json |
        Set-Content -Encoding UTF8 -LiteralPath (Join-Path $destination 'season.json')
    $manifestPath = Join-Path $OutputRoot 'seasons.json'
    $seasons = if (Test-Path -LiteralPath $manifestPath) {
        @(Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json)
    } else { @() }
    $seasons = @($seasons | Where-Object { $_.year -ne $Year })
    $seasons += [pscustomobject]@{ year = $Year; className = $ClassName; archived = $true }
    ConvertTo-Json -InputObject @($seasons | Sort-Object year -Descending) -Depth 4 |
        Set-Content -Encoding UTF8 -LiteralPath $manifestPath
    Write-Output "Published $Year Class $ClassName 7th/8th regional-to-state brackets."
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
