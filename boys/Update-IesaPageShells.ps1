#requires -Version 5.1
<#
.SYNOPSIS
    Re-renders every archived season, class and grade page from the templates.

.DESCRIPTION
    Archive pages are generated from archive-grade-template.html,
    archive-state-template.html and archive-season-template.html. After a
    template or asset version changes, run this to update every archived page.
    It reads only seasons.json and the published data; nothing is fetched.
    Hand-maintained live pages (2026 Class 2A) only get the new version stamp.
#>
param([string]$SiteRoot = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'IesaSitePages.ps1')

$count = 0
# Bump the version first so every re-rendered page tells cached copies to reload.
$version = Step-IesaSiteVersion $SiteRoot
foreach ($season in Read-IesaCatalogue $SiteRoot) {
    $classes = if ($season.PSObject.Properties['classes']) { @($season.classes) } elseif ($season.className) { @($season.className) } else { @('') }
    foreach ($className in $classes) {
        if (!$season.archived) {
            # The live season: classes built with -Live use the live template. A
            # class without data.json keeps hand-maintained pages (2026 Class 2A).
            $folder = Join-Path $SiteRoot (Get-IesaClassFolder $SiteRoot ([int]$season.year) $className)
            if ($className -and (Test-Path -LiteralPath (Join-Path $folder '7th\data.json'))) {
                Write-IesaLiveClassPages $SiteRoot ([int]$season.year) $className
                $count++
            } elseif ($className) {
                # Hand-maintained pages only get the new version stamp; otherwise
                # my-team.js would reload them in every new browser session.
                foreach ($page in Get-ChildItem -LiteralPath $folder -Filter index.html -Recurse -Depth 1) {
                    $html = [IO.File]::ReadAllText($page.FullName)
                    $stamped = $html -replace '(<meta name="iesa-site-version" content=")\d+', "`${1}$version"
                    if ($stamped -ne $html) { Write-IesaText $page.FullName $stamped }
                }
            }
            continue
        }
        Write-IesaClassPages $SiteRoot ([int]$season.year) $(if ($className) { $className } else { '' })
        $count++
    }
}
Write-Host "Re-rendered $count season classes at site version $version."
