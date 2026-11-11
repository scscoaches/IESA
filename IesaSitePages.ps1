# Shared site layout helpers for the archive builders. Dot-source this file.
#
# Layout: the first class archived for a year keeps <year>/<grade>/ (its class
# is the season's className in seasons.json); every other class of that year
# lives in <year>/<class>/<grade>/. seasons.json lists all of them in classes.

$script:IesaSiteRoot = $PSScriptRoot
$script:IesaClassOrder = @('A', 'AA', '1A', '2A', '3A', '4A')

function Read-IesaCatalogue([string]$root) {
    $path = Join-Path $root 'seasons.json'
    if (!(Test-Path -LiteralPath $path)) { return }
    # Windows PowerShell's ConvertFrom-Json emits a JSON array as one object;
    # ForEach-Object unrolls it so callers receive the seasons themselves.
    Get-Content -Raw -LiteralPath $path | ConvertFrom-Json | ForEach-Object { $_ }
}

function Write-IesaCatalogue([string]$root, [object[]]$seasons) {
    $flat = @($seasons | ForEach-Object { $_ })
    if (!$flat.Count -or @($flat | Where-Object { $_ -isnot [pscustomobject] -or $_.year -isnot [int] -and $_.year -isnot [long] }).Count -or
        @($flat.year | Select-Object -Unique).Count -ne $flat.Count) {
        throw 'Refusing to write a malformed seasons.json.'
    }
    $json = ConvertTo-Json -InputObject @($flat | Sort-Object year -Descending) -Depth 5
    [System.IO.File]::WriteAllText((Join-Path $root 'seasons.json'), $json + "`n",
        [System.Text.UTF8Encoding]::new($false))
}

function Get-IesaSortedClasses([object[]]$classes) {
    @($classes | Where-Object { $_ } | Select-Object -Unique |
        Sort-Object { [array]::IndexOf($script:IesaClassOrder, [string]$_) })
}

function Get-IesaClassFolder([string]$root, [int]$year, [string]$className) {
    $season = Read-IesaCatalogue $root | Where-Object { $_.year -eq $year } | Select-Object -First 1
    if (!$season -or !$season.className -or $season.className -eq $className) { return "$year" }
    return "$year\$className"
}

function Add-IesaCatalogueClass([string]$root, [int]$year, [string]$className) {
    $seasons = @(Read-IesaCatalogue $root)
    $season = $seasons | Where-Object { $_.year -eq $year } | Select-Object -First 1
    if (!$season) {
        $season = [pscustomobject]@{ year = $year; className = $className; archived = $true }
        $seasons += $season
    }
    $existing = if ($season.PSObject.Properties['classes']) { @($season.classes) } else { @($season.className) }
    $classes = Get-IesaSortedClasses (@($existing) + @($className))
    if ($season.PSObject.Properties['classes']) { $season.classes = $classes } else {
        $season | Add-Member -NotePropertyName classes -NotePropertyValue $classes
    }
    Write-IesaCatalogue $root $seasons
}

function Write-IesaText([string]$path, [string]$text) {
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
}

function Read-IesaPageData([string]$dataScript) {
    $text = Get-Content -Raw -LiteralPath $dataScript
    $start = $text.IndexOf('{')
    $end = $text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { throw "Unreadable page data at $dataScript" }
    $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
}

# Renders the season landing page and every grade page of one archived class.
function Write-IesaClassPages([string]$root, [int]$year, [string]$className) {
    $relative = Get-IesaClassFolder $root $year $className
    $folder = Join-Path $root $relative
    $depth = @($relative -split '\\').Count
    $landingRoot = '../' * $depth
    $pageRoot = '../' * ($depth + 1)
    $grades = @('combined', '7th', '8th' | Where-Object {
        Test-Path -LiteralPath (Join-Path (Join-Path $folder $_) 'data.js') })
    if (!$grades.Count) { throw "No archived grades in $folder" }

    foreach ($grade in $grades) {
        $directory = Join-Path $folder $grade
        $data = Read-IesaPageData (Join-Path $directory 'data.js')
        if ($data.PSObject.Properties['rounds']) {
            $template = Get-Content -Raw -LiteralPath (Join-Path $script:IesaSiteRoot 'archive-state-template.html')
            $page = $template.Replace('{{YEAR}}', "$year").Replace('{{LABEL}}', [string]$data.label).
                Replace('{{GRADE}}', $grade).Replace('{{ROOT}}', $pageRoot)
        } else {
            $template = Get-Content -Raw -LiteralPath (Join-Path $script:IesaSiteRoot 'archive-grade-template.html')
            $page = $template.Replace('{{YEAR}}', "$year").Replace('{{CLASS}}', $className).
                Replace('{{GRADE}}', $grade).Replace('{{ROOT}}', $pageRoot).
                Replace('{{SEVENTH_ACTIVE}}', $(if ($grade -eq '7th') { 'class="active"' } else { '' })).
                Replace('{{EIGHTH_ACTIVE}}', $(if ($grade -eq '8th') { 'class="active"' } else { '' }))
            if ($year -le 2005) { $page = $page.Replace("<script src=`"../regional-seeds-$grade.js`"></script>", '') }
        }
        Write-IesaText (Join-Path $directory 'index.html') $page
    }

    if ($year -ge 2002) {
        $landing = (Get-Content -Raw -LiteralPath (Join-Path $script:IesaSiteRoot 'archive-season-template.html')).
            Replace('{{YEAR}}', "$year").Replace('{{CLASS}}', $className).Replace('{{ROOT}}', $landingRoot)
    } else {
        $links = if ($grades -contains 'combined') {
            "<a href='combined/index.html'>Combined 7th/8th tournament</a>"
        } else { "<a href='7th/index.html'>7th Grade</a> &nbsp; <a href='8th/index.html'>8th Grade</a>" }
        $heading = if ($year -le 1985) { "$year Combined 7th/8th State Tournament" } elseif ($year -le 1989) {
            "$year Girls Basketball State Tournaments"
        } else { "$year Class $className Girls Basketball State Tournaments" }
        $landing = "<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>$heading</title></head><body><main><h1>$heading</h1><p>$links</p><p><a href='${landingRoot}index.html'>All seasons</a></p></main></body></html>`n"
    }
    Write-IesaText (Join-Path $folder 'index.html') $landing
}
