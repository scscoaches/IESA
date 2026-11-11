#requires -Version 5.1
<#
.SYNOPSIS
    Collapses repeated spaces in school names and other text in archived data.

.DESCRIPTION
    IESA pages sometimes produce names such as "Gardner  (Co-op)" (removing a
    "(Host)" marker leaves two spaces). Browsers hide the extra space, but exact
    name comparisons and the team index treat it as a different spelling. This
    rewrites archived page data, bracket caches and seed caches (1979-2025) so
    every string has single spaces, keeping each file's original wrapper. Only
    files whose strings actually change are written. The live season is left to
    its builder and refresh scripts.
#>
param([string]$SiteRoot = $PSScriptRoot, [switch]$WhatIf)

$ErrorActionPreference = 'Stop'
$script:changed = 0

function Repair($node) {
    if ($node -is [string]) {
        # IESA's &nbsp; decodes to U+00A0, which sits beside ordinary spaces.
        $fixed = (($node -replace '\u00A0', ' ') -replace ' {2,}', ' ').Trim()
        if ($fixed -ne $node) { $script:changed++ }
        return $fixed
    }
    if ($node -is [System.Collections.IList]) {
        return , @($node | ForEach-Object { Repair $_ })
    }
    if ($node -is [pscustomobject]) {
        foreach ($property in @($node.PSObject.Properties)) { $property.Value = Repair $property.Value }
    }
    return $node
}

$years = Get-ChildItem -Directory -LiteralPath $SiteRoot | Where-Object { $_.Name -match '^\d{4}$' -and [int]$_.Name -le 2025 }
$files = $years | ForEach-Object {
    Get-ChildItem -Recurse -File -LiteralPath $_.FullName -Include 'data.json', 'data.js', 'bracket-*.json', 'bracket-*.js', 'regional-seeds-*.json', 'regional-seeds-*.js'
}
$written = 0
$strings = 0
foreach ($file in $files) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $start = $text.IndexOf('{')
    $end = $text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { continue }
    $prefix = $text.Substring(0, $start)
    $suffix = $text.Substring($end + 1)
    $script:changed = 0
    $data = Repair ($text.Substring($start, $end - $start + 1) | ConvertFrom-Json)
    if (!$script:changed) { continue }
    $strings += $script:changed
    # Early state archives were written compressed; keep each file's style.
    $compress = $text.Substring($start, [Math]::Min(200, $end - $start)) -notmatch "`n"
    $json = if ($compress) { $data | ConvertTo-Json -Depth 30 -Compress } else { $data | ConvertTo-Json -Depth 30 }
    if (!$WhatIf) {
        [IO.File]::WriteAllText($file.FullName, $prefix.TrimStart([char]0xFEFF) + $json + $suffix, [Text.UTF8Encoding]::new($false))
    }
    $written++
}
Write-Host "$(if ($WhatIf) { 'Would rewrite' } else { 'Rewrote' }) $written of $(@($files).Count) files ($strings strings had repeated spaces)."
if ($written -and !$WhatIf) {
    # Changed data: tell browsers holding cached pages to reload them.
    . (Join-Path $PSScriptRoot 'IesaSitePages.ps1')
    Write-Host "Site version is now $(Step-IesaSiteVersion $SiteRoot); run Update-IesaPageShells.ps1 to stamp the pages."
}
