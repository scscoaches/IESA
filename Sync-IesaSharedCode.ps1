#requires -Version 5.1
<#
.SYNOPSIS
    Copies the code both sports share from girls\ to boys\ (or checks it matches).

.DESCRIPTION
    Each sport is a complete copy of the site: its own seasons, data and pages,
    and the same code, which reads the sport's IESA pages, wording and class eras
    from that folder's sport.json. girls\ holds the master copy of the code. Edit
    it there, run this to copy it to boys\, and commit both.

    Shared: the build/season scripts and page templates at the sport root, and the
    scripts, styles and icons in <sport>\2026\. Not shared (each sport's own):
    sport.json, seasons.json, live-season.json, placements.json, teams.json,
    site-version.json, index.html, 2026\index.html, 2026\manifest.json,
    2026\team-links.js, every season folder's data and caches, and README.md.

.PARAMETER Check
    Only report differences; exit 1 if any shared file differs or is missing.
#>
param(
    [string]$From = (Join-Path $PSScriptRoot 'girls'),
    [string]$To = (Join-Path $PSScriptRoot 'boys'),
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

function Get-IesaSharedFiles([string]$root) {
    $rootFiles = @('Build-IesaEarlyArchive.ps1', 'Build-IesaPlacements.ps1', 'Build-IesaSeason.ps1',
        'Build-IesaTeamIndex.ps1', 'IesaCalendar.ps1', 'IesaSitePages.ps1', 'Start-IesaSeason.ps1',
        'Sync-IesaSeason.ps1', 'Update-IesaPageShells.ps1', 'Build-IesaAllTime.ps1',
        'archive-grade-template.html', 'archive-season-template.html', 'archive-state-template.html',
        'live-grade-template.html')
    # Season data in 2026\ (the girls' live Class 2A caches) and per-sport files stay put.
    $dataPattern = '^(bracket|regional-seeds|scores|strength)-(7th|8th)\.(js|json)$|^(team-links\.js|index\.html|manifest\.json|data\.json|nfhs-events\.json|hudl-events\.json|iesa-pause\.json)$'
    $assets = @(Get-ChildItem -File -LiteralPath (Join-Path $root '2026') |
        Where-Object { $_.Extension -in '.js', '.css', '.svg', '.png', '.ps1', '.ashx' -and $_.Name -notmatch $dataPattern } |
        ForEach-Object { "2026\$($_.Name)" })
    @($rootFiles) + $assets | Sort-Object
}

$files = Get-IesaSharedFiles $From
$different = @()
foreach ($file in $files) {
    $source = Join-Path $From $file
    $target = Join-Path $To $file
    if (!(Test-Path -LiteralPath $source)) { throw "Missing shared file in ${From}: $file" }
    $same = (Test-Path -LiteralPath $target) -and
        (Get-FileHash -LiteralPath $source).Hash -eq (Get-FileHash -LiteralPath $target).Hash
    if ($same) { continue }
    $different += $file
    if (!$Check) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}
if ($Check) {
    if ($different.Count) {
        Write-Output "Shared code differs from ${From}: $($different -join ', ')"
        exit 1
    }
    Write-Output "Shared code matches ($($files.Count) files)."
} else {
    Write-Output "Copied $($different.Count) of $($files.Count) shared files to $To."
}
