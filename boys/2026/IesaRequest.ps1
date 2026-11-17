# Shared guard for every request to www.iesa.org. Dot-source it, then call
# Invoke-IesaPage instead of Invoke-WebRequest.
#   - Requests are at least 3 seconds apart.
#   - Three failures in a row mean IESA is struggling: requests stop and
#     iesa-pause.json pauses all IESA traffic (scripts and the Update button)
#     for 6 hours. Delete the file to resume sooner, or create it by hand to
#     pause on purpose: {"until":"2026-10-14 05:30","reason":"IESA outage"}.
#   - A single process makes at most 700 requests.
#   - $env:IESA_OFFLINE = "1" blocks all IESA requests, for testing changes
#     against the cached files without touching IESA.
$script:IesaPausePath = Join-Path $PSScriptRoot "iesa-pause.json"
if ($null -eq $global:IesaGuard) {
    $global:IesaGuard = @{ Last = [datetime]::MinValue; Failures = 0; Count = 0 }
}
$IesaMinimumGapSeconds = 3
$IesaFailureLimit = 3
$IesaRequestLimit = 700
$IesaPauseHours = 6

function Get-IesaPause {
    if ($env:IESA_OFFLINE -eq "1") { return "IESA requests are disabled (IESA_OFFLINE=1)." }
    if (!(Test-Path -LiteralPath $script:IesaPausePath)) { return $null }
    try {
        $pause = Get-Content -Raw -LiteralPath $script:IesaPausePath | ConvertFrom-Json
        $until = [datetime]::ParseExact($pause.until, "yyyy-MM-dd HH:mm", [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return "IESA requests are paused ($script:IesaPausePath could not be read)."
    }
    if ((Get-Date) -ge $until) { return $null }
    return "IESA requests are paused until $($pause.until): $($pause.reason)"
}

function Set-IesaPause([string]$reason) {
    $until = (Get-Date).AddHours($IesaPauseHours).ToString("yyyy-MM-dd HH:mm")
    [pscustomobject]@{ until = $until; reason = $reason } | ConvertTo-Json |
        Set-Content -Encoding UTF8 -LiteralPath $script:IesaPausePath
    Write-Warning "Paused IESA requests until ${until}: $reason"
}

function Invoke-IesaPage([string]$Uri, [int]$TimeoutSec = 30) {
    $paused = Get-IesaPause
    if ($paused) { throw $paused }
    if ($global:IesaGuard.Count -ge $IesaRequestLimit) {
        throw "Stopped after $IesaRequestLimit IESA requests in one run."
    }
    $wait = $IesaMinimumGapSeconds - ((Get-Date) - $global:IesaGuard.Last).TotalSeconds
    if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]($wait * 1000)) }
    $global:IesaGuard.Count++
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec $TimeoutSec
        $global:IesaGuard.Failures = 0
        return $response
    } catch {
        $global:IesaGuard.Failures++
        if ($global:IesaGuard.Failures -ge $IesaFailureLimit) {
            Set-IesaPause "IESA failed $IesaFailureLimit requests in a row ($($_.Exception.Message))"
        }
        throw
    } finally {
        $global:IesaGuard.Last = Get-Date
    }
}
