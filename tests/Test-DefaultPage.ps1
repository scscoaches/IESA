#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'girls\tests\IesaTestHelpers.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$rootIndex = Get-Content -Raw (Join-Path $repo 'index.html')
$settings = Get-Content -Raw (Join-Path $repo 'girls\2026\my-team.js')
$styles = Get-Content -Raw (Join-Path $repo 'girls\2026\styles.css')

Write-Host 'Root sport picker'
$legacyRedirect = $rootIndex.IndexOf('if (location.search || location.hash)')
$defaultLookup = $rootIndex.IndexOf('localStorage.getItem("iesa-default-page")')
Assert-True ($legacyRedirect -ge 0 -and $defaultLookup -gt $legacyRedirect) 'legacy query/hash redirects take precedence over the saved default'
Assert-True ($rootIndex -match 'var defaultPage = "girls"') 'Girls is the initial default page'
Assert-True ($rootIndex -match 'savedDefaultPage === "girls" \|\| savedDefaultPage === "boys"') 'only a valid saved sport overrides the initial default'
Assert-True ($rootIndex -match 'defaultPage \+ "/index\.html"') 'saved preference opens the matching sport home page'
Assert-True ($rootIndex -match 'linkParameters\.get\("team"\)' -and $rootIndex -match 'linkParameters\.get\("gender"\)') 'root recognizes shared links containing a team and gender'
Assert-True ($rootIndex -match 'location\.replace\(linkedGender \+ "/index\.html"') 'shared team/gender links open their selected sport'
Assert-True ($rootIndex -match 'localStorage\.setItem' -and $rootIndex -match '"iesa-default-page"' -and $rootIndex -match 'linkedGender') 'shared team/gender links save that sport as the default'

Write-Host 'Settings preference'
Assert-True ($settings -match 'var DEFAULT_PAGE_KEY = "iesa-default-page"') 'settings and root picker use the same storage key'
Assert-True ($settings -match 'element\("span", "", "Default"\)') 'the setting label is concise'
Assert-True ($settings.Contains('button.title = "Default to "') -and $settings.Contains('addDefaultChoice("girls"') -and $settings.Contains('addDefaultChoice("boys"')) 'Settings offer accessible Girls and Boys icon buttons'
Assert-True ($settings -match 'var defaultPage = "girls"') 'Girls is selected when no preference has been saved'
Assert-True ($settings -match 'stroke="currentColor"' -and $styles -match 'default-page-choice svg') "sport icons match the site's line-icon style"
Assert-True ($settings -notmatch 'Ask every time' -and $settings -notmatch 'localStorage\.removeItem\(DEFAULT_PAGE_KEY\)') 'the setting always keeps one sport selected'
Assert-True ($settings -match 'linkedSport = linkedGender === "girls" \|\| linkedGender === "boys" \? linkedGender : sport\.sport') 'team links use their gender or current sport as the default'
 $hasGenderShare = $settings.Contains('url.searchParams.set') -and $settings.Contains('sport.sport')
Assert-True $hasGenderShare 'shared team links include their gender'
Assert-True ($settings.IndexOf('dialog.appendChild(defaultRow)') -lt $settings.IndexOf('var toggle = document.getElementById("theme-toggle")')) 'default-page controls appear before Dark mode in Settings'
Assert-True ($settings -match 'localStorage\.setItem\(DEFAULT_PAGE_KEY' -and $settings -match 'selected\)') 'selecting a sport saves the preference'
 $showsSavePopup = $settings.Contains('showDefaultStatus') -and $settings.Contains('Saved')
Assert-True $showsSavePopup 'saving shows a brief confirmation popup'
Assert-True ($settings -match 'Could not save this preference') 'storage failures are reported in Settings'
Assert-True ($settings.Contains('["girls", "boys"].forEach') -and $settings.Contains('finishes(historySport)') -and $settings.Contains('load("seasons.json", historySport)')) 'state finishes load independently for both sports'
Assert-True ($settings.Contains('url.searchParams.set("gender", historySport)') -and $settings.Contains('url.searchParams.set("team", name)')) 'cross-sport finish links carry the selected team and gender'
Assert-True ($styles.Contains('.finish-girls') -and $styles.Contains('.finish-boys') -and $styles.Contains('.dark-theme .my-team-history .finish-girls')) 'finish lists use sport colors in light and dark themes'

$result = Get-TestResult
Write-Host "`n$($result.Passes) passed, $($result.Failures.Count) failed"
if ($result.Failures.Count) { exit 1 }
