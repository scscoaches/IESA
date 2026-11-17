# Which IESA sport this copy of the site serves. Each sport's site root (girls\,
# boys\) holds a sport.json; the code itself is identical in both and reads its
# IESA pages, calendar wording and class eras from here. Dot-source this file.
#   yearOffset     IESA's tournament year minus the calendar's season start year
#                  (girls play in the fall: 0; boys' "2026-2027" season is 2027: 1).
#   combinedLast   last year with one combined 7th/8th bracket (0: none).
#   gradeOnlyLast  last year with grade brackets but no classes (0: none).
#   earlyLast      last year archived from IESA's state-only bracket pages.
#   legacyLast     last year of Class A/AA (32 regionals, no seeds); numbered
#                  classes with seeded regional brackets follow.
#   earlyPairingsFrom  first state-only year with published sectional pairings
#                  (0: none).
#   earlyAssignmentsLast  last year whose assignment pages may omit sectionals.

function Get-IesaSport([string]$siteRoot) {
    $sport = [ordered]@{
        sport = 'girls'; name = 'Girls Basketball'; code = 'gbk'; activityCode = 'GBK'
        calendarHeading = 'GIRLS BASKETBALL'; yearOffset = 0; firstYear = 1979
        combinedLast = 1985; gradeOnlyLast = 1989; earlyLast = 2001; legacyLast = 2005; earlyPairingsFrom = 1999
        earlyAssignmentsLast = 2008
        nfhsGender = 'girls'; hudlGender = 'WOMENS'; scoreWorkflow = 'update-scores.yml'; historyClasses = @()
    }
    $path = Join-Path $siteRoot 'sport.json'
    if (Test-Path -LiteralPath $path) {
        foreach ($property in (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json).PSObject.Properties) {
            $sport[$property.Name] = $property.Value
        }
    }
    [pscustomobject]$sport
}

$IesaSport = Get-IesaSport (Split-Path -Parent $PSScriptRoot)
$IesaSportUrl = "https://www.iesa.org/activities/$($IesaSport.code)"
$IesaIsGirls = $IesaSport.sport -eq 'girls'
