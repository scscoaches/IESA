param(
    [string]$SitePath = "C:\inetpub\personalroot\IESA\2026",
    [datetime]$SeasonStart = [datetime]::new(2026, 8, 1)
)

# Collects each linked school's NFHS Network girls middle-school game pages so the
# team dialog can put a watch link beside a score. NFHS blocks cross-site browser
# requests, so the pages are read here and published as nfhs-events.json.
$ErrorActionPreference = "Stop"
$outputPath = Join-Path $SitePath "nfhs-events.json"
$links = Get-Content -Raw -LiteralPath (Join-Path $SitePath "team-links.js")
$slugs = @([regex]::Matches($links, 'nfhs:\s*"https://www\.nfhsnetwork\.com/schools/([^/"]+)') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

$previous = @{}
if (Test-Path -LiteralPath $outputPath) {
    try {
        $prior = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
        foreach ($property in $prior.schools.PSObject.Properties) { $previous[$property.Name] = @($property.Value) }
    } catch {
        Write-Warning "Ignoring unreadable $outputPath`: $($_.Exception.Message)"
    }
}

$schools = [ordered]@{}
foreach ($slug in $slugs) {
    $url = "https://www.nfhsnetwork.com/schools/$slug/basketball/girls/middle-school"
    try {
        $html = (Invoke-WebRequest -UseBasicParsing $url -TimeoutSec 30).Content
        $events = [ordered]@{}
        $cards = [regex]::Matches($html, '(?s)<a href="(/events/[^"/]+/(gam[a-z0-9]+))"[^>]*aria-label="([^"]*)"(.*?)</a>')
        foreach ($card in $cards) {
            $key = $card.Groups[2].Value
            $banner = [regex]::Match($card.Groups[4].Value, 'line-clamp-1 text-ellipsis break-all">([^<]+)').Groups[1].Value
            $start = [regex]::Match($card.Groups[4].Value, 'datetime="([^"]+)"').Groups[1].Value
            # Pages without a girls middle-school section fall back to every school event.
            if ($events.Contains($key) -or $banner -notmatch 'Middle School' -or $banner -notmatch 'Girls Basketball' -or !$start) { continue }
            $startTime = [datetime]::Parse($start, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            if ($startTime -lt $SeasonStart) { continue }
            $events[$key] = [pscustomobject]@{
                key = $key
                url = "https://www.nfhsnetwork.com" + $card.Groups[1].Value
                label = [Net.WebUtility]::HtmlDecode($card.Groups[3].Value)
                start = $start
            }
        }
        $schools[$slug] = @($events.Values | Sort-Object start)
    } catch {
        Write-Warning "Unable to read NFHS games for ${slug}: $($_.Exception.Message)"
        if ($previous.ContainsKey($slug)) { $schools[$slug] = $previous[$slug] }
    } finally {
        Start-Sleep -Seconds 1
    }
}

$json = [pscustomobject]@{
    updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    schools = $schools
} | ConvertTo-Json -Depth 5
$temporary = "$outputPath.tmp"
$json | Set-Content -Encoding UTF8 -LiteralPath $temporary
Move-Item -LiteralPath $temporary -Destination $outputPath -Force
