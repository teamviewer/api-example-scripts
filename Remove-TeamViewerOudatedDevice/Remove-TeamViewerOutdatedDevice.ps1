<#
 .SYNOPSIS
    Removes TeamViewer devices that didn't appear online for a given time.

 .DESCRIPTION
    The script fetches a list of TeamViewer devices of the TeamViewer company
    that corresponds to a given API token. The list will be filtered by
    devices being offline for a certain amount of time. These devices will
    be removed.
    The expiration can either be specified by a specific date or by interval.

 .PARAMETER ApiToken
    The TeamViewer API token to use.
    Must be a user access token.
    The token requires the following access permissions:
        - `Computer & Contacts > View entries, add entries, edit entries, remove entries`

 .PARAMETER ExpiryDate
    A specific expiry date. All devices that haven't been online since that
    date are considered being removed.

 .PARAMETER ExpiryInterval
    Switch that enables interval-based calculation of the expiration date.
    Should be used in combination with the `Days`, `Hours`, `Minutes` and/or
    `Seconds` parameter.

 .PARAMETER Days
    Days of the expiration interval.
    Must be used in combination with the `ExpiryInterval` parameter.

 .PARAMETER Hours
    Hours of the expiration interval.
    Must be used in combination with the `ExpiryInterval` parameter.

 .PARAMETER Minutes
    Minutes of the expiration interval.
    Must be used in combination with the `ExpiryInterval` parameter.

 .PARAMETER Seconds
    Seconds of the expiration interval.
    Must be used in combination with the `ExpiryInterval` parameter.

 .PARAMETER Remove
    If set, the script actually removes outdated devices.
    Otherwise, the script only outputs possible removal candidates.
    The default value is `false`.

 .PARAMETER Force
    If set, the script will NOT ask the user for confirmation of the
    removal. This parameter only has effect in combination with the
    `Remove` parameter.
    The default value is `false`, causing the script to ask the user
    one more time before starting to remove devices.

 .EXAMPLE
    .\Remove-TeamViewerOutdatedDevice -ExpiryDate '2018-12-17T17:00:00'

 .EXAMPLE
    .\Remove-TeamViewerOutdatedDevice -ExpiryDate 2018-12-31 -WhatIf

 .EXAMPLE
    .\Remove-TeamViewerOutdatedDevice -ExpiryInterval -Days 10

 .EXAMPLE
    .\Remove-TeamViewerOutdatedDevice -ExpiryInterval -Hours 12 -Force

 .NOTES
    Copyright (c) 2019 TeamViewer GmbH
    See file LICENSE.txt
    Version 1.0.0
#>

[CmdletBinding(DefaultParameterSetName="ExactDate", SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $ApiToken,

    [Parameter(ParameterSetName = "ExactDate", Mandatory = $true)]
    [DateTime] $ExpiryDate,

    [Parameter(ParameterSetName = "DateInterval", Mandatory = $true)]
    [switch] $ExpiryInterval,

    [Parameter(ParameterSetName = "DateInterval", Mandatory = $false)]
    [int] $Days,

    [Parameter(ParameterSetName = "DateInterval", Mandatory = $false)]
    [int] $Hours,

    [Parameter(ParameterSetName = "DateInterval", Mandatory = $false)]
    [int] $Minutes,

    [Parameter(ParameterSetName = "DateInterval", Mandatory = $false)]
    [int] $Seconds,

    [Switch] $Force = $false
)

if (-Not $MyInvocation.BoundParameters.ContainsKey('ErrorAction')) { $script:ErrorActionPreference = 'Stop' }
if (-Not $MyInvocation.BoundParameters.ContainsKey('InformationAction')) { $script:InformationPreference = 'Continue' }

$tvApiVersion = 'v1'
$tvApiBaseUrl = 'https://webapi.teamviewer.com'

function ConvertTo-TeamViewerRestError {
    param([parameter(ValueFromPipeline)]$err)
    try { return ($err | Out-String | ConvertFrom-Json) }
    catch { return $err }
}

function Invoke-TeamViewerRestMethod {
    # Using `Invoke-WebRequest` instead of `Invoke-RestMethod`:
    # There is a known issue for PUT and DELETE operations to hang on Windows Server 2012.
    try { return ((Invoke-WebRequest -UseBasicParsing @args).Content | ConvertFrom-Json) }
    catch [System.Net.WebException] {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $reader.BaseStream.Position = 0
        Throw ($reader.ReadToEnd() | ConvertTo-TeamViewerRestError)
    }
}

function Get-TeamViewerDevice($accessToken, $onlineState) {
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/devices" `
        -Method Get -Headers @{authorization = "Bearer $accessToken"} `
        -Body @{ online_state = $onlineState }
}

function Remove-TeamViewerDevice {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
    param($accessToken, $deviceId)
    if ($PSCmdlet.ShouldProcess($deviceId)) {
        return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/devices/$deviceId" `
            -Method Delete -Headers @{authorization = "Bearer $accessToken"}
    }
}

function Remove-TeamViewerOutdatedDevice {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param($accessToken, $expiryDate, [bool]$force)

    $devices = @((Get-TeamViewerDevice $accessToken 'offline').devices | `
            Where-Object { $_.last_seen -And [DateTime]($_.last_seen) -le $expiryDate })

    Write-Information "Found $($devices.Count) devices that have been offline since $expiryDate"

    if ($devices.Count -gt 0 -And -Not $WhatIfPreference -And -Not $force -And
        -Not $PSCmdlet.ShouldContinue("Do you really want to remove those devices?", $devices)) {
        Write-Information "Aborting..."
        exit
    }

    ForEach ($device in $devices) {
        $status = 'Unchanged'
        if ($force -Or $PSCmdlet.ShouldProcess($device.alias)) {
            try {
                Remove-TeamViewerDevice $accessToken $device.device_id
                $status = 'Removed'
            }
            catch {
                Write-Warning "Failed to remove device '$($device.alias)': $_"
                $status = 'Failed'
            }
        }
        Write-Output ([pscustomobject]@{
                Alias    = $device.alias
                DeviceId = $device.device_id
                LastSeen = [DateTime]($device.last_seen)
                Status   = $status
            })
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $now = (Get-Date)
    if ($ExpiryInterval) {
        $ExpiryDate = $now.AddDays(-1 * $Days).AddHours(-1 * $Hours).AddMinutes(-1 * $Minutes).AddSeconds(-1 * $Seconds)
    }
    if ($ExpiryDate -ge $now) {
        Throw "Invalid expiry date specified: $ExpiryDate"
    }
    Remove-TeamViewerOutdatedDevice $ApiToken $ExpiryDate $Force
}
