#requires -Version 5.1
<#
.SYNOPSIS
    Re-renders every archived season, class and grade page from the templates.

.DESCRIPTION
    Archive pages are generated from archive-grade-template.html,
    archive-state-template.html and archive-season-template.html. After a
    template or asset version changes, run this to update every archived page.
    It reads only seasons.json and the published data; nothing is fetched.
    The live season is maintained by hand and is skipped.
#>
param([string]$SiteRoot = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'IesaSitePages.ps1')

$count = 0
foreach ($season in Read-IesaCatalogue $SiteRoot) {
    if (!$season.archived) { continue }
    $classes = if ($season.PSObject.Properties['classes']) { @($season.classes) } elseif ($season.className) { @($season.className) } else { @('') }
    foreach ($className in $classes) {
        Write-IesaClassPages $SiteRoot ([int]$season.year) $(if ($className) { $className } else { '' })
        $count++
    }
}
Write-Host "Re-rendered $count archived season classes."
