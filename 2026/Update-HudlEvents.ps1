param(
    [string]$SitePath = "C:\inetpub\personalroot\IESA\2026",
    [datetime]$SeasonStart = [datetime]::new(2026, 8, 1)
)

# Collects each linked school's Hudl junior-high girls basketball broadcasts so the
# team dialog can put a watch link beside a score. Hudl's fan site loads these from
# its public GraphQL API, which is read here and published as hudl-events.json in
# the same shape as nfhs-events.json. Labels use the bracket team name for the
# school's own side because Hudl titles use the high school's name.
$ErrorActionPreference = "Stop"
$endpoint = "https://www.hudl.com/api/public/graphql/query"
$outputPath = Join-Path $SitePath "hudl-events.json"
$links = Get-Content -Raw -LiteralPath (Join-Path $SitePath "team-links.js")
$teams = @([regex]::Matches($links, '"([^"]+)":\s*\{[^}]*hudl:\s*"https://fan\.hudl\.com/[^"]*/organization/(\d+)/') |
    ForEach-Object { [pscustomobject]@{ name = $_.Groups[1].Value; schoolId = $_.Groups[2].Value } })

$query = @'
query($input: GetFanBroadcastsPaginatedInput!) {
  fanBroadcasts(input: $input) {
    edges { node { id title broadcastDateUtc teamHeader { gender sport name } organization { organizationProfileUrl } } }
  }
}
'@

$previous = @{}
if (Test-Path -LiteralPath $outputPath) {
    try {
        $prior = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
        foreach ($property in $prior.schools.PSObject.Properties) { $previous[$property.Name] = @($property.Value) }
    } catch {
        Write-Warning "Ignoring unreadable $outputPath`: $($_.Exception.Message)"
    }
}

function Get-Opponent([string]$title) {
    # "7th Gr. followed by 8th Gr. - St Anthony Effingham vs Dieterich JH Womens Basketball"
    $matchup = ($title -split '\s+-\s+' | Where-Object { $_ -match '\svs\.?\s' } | Select-Object -Last 1)
    if (!$matchup) { return $null }
    $sides = $matchup -split '\s+vs\.?\s+', 2
    if ($sides.Count -ne 2) { return $null }
    $opponent = $sides[1] -replace "\s*\b(?:Womens|Women's|Girls'?)?\s*(?:Other|Varsity|JV|Junior Varsity)?\s*Basketball\s*$", ''
    $opponent = $opponent -replace '\b(?:JH|Jr\.? High|Lady \w+)\b', ' ' -replace '\s+', ' '
    $opponent = $opponent.Trim()
    if ($opponent) { return $opponent } else { return $null }
}

$schools = [ordered]@{}
foreach ($team in $teams) {
    $graphId = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("School$($team.schoolId)"))
    $ownName = $team.name -replace '\s*\(Co-?op\)$', ''
    try {
        $events = [ordered]@{}
        foreach ($status in "UPCOMING_OR_STREAMING", "ARCHIVED") {
            $body = @{
                query = $query
                variables = @{ input = @{
                    schoolIds = @($graphId); first = 100; broadcastStatusFilter = $status
                    sortType = "BROADCAST_DATE"; sortByAscending = $false
                } }
            } | ConvertTo-Json -Depth 6 -Compress
            $response = Invoke-RestMethod -Method Post -Uri $endpoint -ContentType "application/json" -Body $body -TimeoutSec 30
            if ($response.errors) { throw ($response.errors | Select-Object -First 1).message }
            foreach ($node in $response.data.fanBroadcasts.edges.node) {
                $header = $node.teamHeader
                # Some schools file other sports under a basketball team, so the team name is checked too.
                if ($events.Contains($node.id) -or $header.gender -ne "WOMENS" -or $header.sport -ne "BASKETBALL" -or
                    $header.name -notmatch 'Basketball' -or $header.name -notmatch '\b(?:JH|Jr\.?|Junior|Middle|7th|8th)\b') { continue }
                $startTime = [datetime]::Parse($node.broadcastDateUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                if ($startTime -lt $SeasonStart) { continue }
                $opponent = Get-Opponent $node.title
                $profile = $node.organization.organizationProfileUrl
                if (!$opponent -or !$profile) { continue }
                $events[$node.id] = [pscustomobject]@{
                    key = $node.id
                    url = $profile.TrimEnd("/") + "/watch?b=" + [Uri]::EscapeDataString($node.id)
                    label = "$ownName vs. $opponent"
                    title = $node.title
                    start = $node.broadcastDateUtc
                }
            }
        }
        $schools[$team.name] = @($events.Values | Sort-Object start)
    } catch {
        Write-Warning "Unable to read Hudl games for $($team.name): $($_.Exception.Message)"
        if ($previous.ContainsKey($team.name)) { $schools[$team.name] = $previous[$team.name] }
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
