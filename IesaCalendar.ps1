# Reads IESA's girls basketball calendar
# (https://www.iesa.org/activities/calendar.asp?activitycode=GBK), which lists
# four seasons ("2026-2027" ...) for each grade. Dot-source this file.

$IesaCalendarUrl = 'https://www.iesa.org/activities/calendar.asp?activitycode=GBK'

# The calendar's rows this site uses, keyed by the start of their label.
$IesaCalendarItems = [ordered]@{
    finalEntryDeadline = 'Final Entry Deadline'
    gamesMayBegin = 'Games may begin'
    onlineRanking = 'Online Ranking'
    regionals = 'Regionals'
    sectionals = 'Sectionals'
    state = 'State'
    seasonMustEnd = 'Season must end'
}

# Dates are written many ways: "Aug 1, 2026", "Nov.10, 2026",
# "Nov. 21, 23-25, 2026", "Nov. 30, Dec. 1, 3, 4 2026", "Nov. 27,28,30 Dec.1,2028".
# Returns the first and last day listed.
function ConvertFrom-IesaCalendarDate([string]$text) {
    $text = ($text -replace '\s+', ' ').Trim()
    $yearMatch = [regex]::Match($text, '(\d{4})\s*$')
    if (!$yearMatch.Success) { throw "Calendar date without a year: '$text'" }
    $year = [int]$yearMatch.Groups[1].Value
    $months = @{ jan = 1; feb = 2; mar = 3; apr = 4; may = 5; jun = 6; jul = 7; aug = 8; sep = 9; oct = 10; nov = 11; dec = 12 }
    $month = 0
    $days = @()
    foreach ($token in [regex]::Matches($text.Substring(0, $yearMatch.Index), '[A-Za-z]+|\d{1,2}(?:-\d{1,2})?')) {
        $value = $token.Value
        if ($value -match '^[A-Za-z]+$') {
            $short = $value.Substring(0, [math]::Min(3, $value.Length)).ToLowerInvariant()
            if (!$months.ContainsKey($short)) { throw "Unknown month '$value' in calendar date '$text'" }
            $month = $months[$short]
            continue
        }
        if (!$month) { throw "Calendar date has a day before its month: '$text'" }
        foreach ($day in $value -split '-') { $days += [datetime]::new($year, $month, [int]$day) }
    }
    if (!$days.Count) { throw "Calendar date without a day: '$text'" }
    [pscustomobject]@{ first = $days[0]; last = $days[$days.Count - 1]; text = $text }
}

function Get-IesaCalendarCellText([string]$html) {
    ([System.Net.WebUtility]::HtmlDecode(($html -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
}

# Returns $calendar[<season year>][<grade>][<item>] = { first; last; text }, where
# the season year is the fall the tournaments are played (2026 for "2026-2027").
function Get-IesaCalendar([string]$html) {
    $calendar = @{}
    foreach ($grade in '7th', '8th') {
        $header = [regex]::Match($html, "(?is)GIRLS BASKETBALL $grade GRADE")
        if (!$header.Success) { throw "The IESA calendar has no $grade grade girls basketball table." }
        $rest = $html.Substring($header.Index)
        $next = [regex]::Match($rest.Substring($header.Length), '(?is)GIRLS BASKETBALL [78]th GRADE|</table>')
        $scope = if ($next.Success) { $rest.Substring(0, $header.Length + $next.Index) } else { $rest }
        $years = @([regex]::Matches($scope, '(?is)<th>\s*(\d{4})-\d{4}\s*</th>') | ForEach-Object { [int]$_.Groups[1].Value })
        if (!$years.Count) { throw "The IESA calendar's $grade grade table lists no seasons." }
        foreach ($row in [regex]::Matches($scope, "(?is)<tr>\s*<td\s+class=['""]Label['""]>(.*?)</td>(.*?)</tr>")) {
            $label = Get-IesaCalendarCellText $row.Groups[1].Value
            $item = @($IesaCalendarItems.Keys | Where-Object { $label.StartsWith($IesaCalendarItems[$_], [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
            if (!$item) { continue }
            $cells = @([regex]::Matches($row.Groups[2].Value, "(?is)<td\s+class=['""]ListData['""]>(.*?)</td>") | ForEach-Object { Get-IesaCalendarCellText $_.Groups[1].Value })
            for ($i = 0; $i -lt [math]::Min($cells.Count, $years.Count); $i++) {
                if (!$cells[$i]) { continue }
                $year = $years[$i]
                if (!$calendar.ContainsKey($year)) { $calendar[$year] = @{} }
                if (!$calendar[$year].ContainsKey($grade)) { $calendar[$year][$grade] = @{} }
                $calendar[$year][$grade][$item] = ConvertFrom-IesaCalendarDate $cells[$i]
            }
        }
    }
    return $calendar
}

# The live-season.json dates for one season. Refreshes stop on the "Season must
# end" date, so endDate (the last day refreshes may run) is the day before it.
function Get-IesaSeasonDates($calendar, [int]$year) {
    if (!$calendar.ContainsKey($year)) { throw "The IESA calendar has no $year-$($year + 1) season." }
    $grades = [ordered]@{}
    foreach ($grade in '7th', '8th') {
        $dates = $calendar[$year][$grade]
        foreach ($item in 'finalEntryDeadline', 'gamesMayBegin', 'onlineRanking', 'regionals', 'state', 'seasonMustEnd') {
            if (!$dates -or !$dates.ContainsKey($item)) { throw "The IESA calendar has no $grade grade '$($IesaCalendarItems[$item])' date for $year." }
        }
        $grades[$grade] = [ordered]@{
            seedsFrom = $dates.onlineRanking.first.ToString('yyyy-MM-dd')
            bracketFrom = $dates.regionals.first.ToString('yyyy-MM-dd')
            stateLast = $dates.state.last.ToString('yyyy-MM-dd')
        }
    }
    $both = @($calendar[$year]['7th'], $calendar[$year]['8th'])
    $first = { param($item) @($both | ForEach-Object { $_[$item].first } | Sort-Object)[0] }
    $mustEnd = @($both | ForEach-Object { $_['seasonMustEnd'].first } | Sort-Object)[-1]
    [ordered]@{
        createFrom = (& $first 'finalEntryDeadline').ToString('yyyy-MM-dd')
        gamesFrom = (& $first 'gamesMayBegin').ToString('yyyy-MM-dd')
        seedsFrom = (& $first 'onlineRanking').ToString('yyyy-MM-dd')
        bracketFrom = (& $first 'regionals').ToString('yyyy-MM-dd')
        endDate = $mustEnd.AddDays(-1).ToString('yyyy-MM-dd')
        seasonMustEnd = $mustEnd.ToString('yyyy-MM-dd')
        grades = $grades
    }
}
