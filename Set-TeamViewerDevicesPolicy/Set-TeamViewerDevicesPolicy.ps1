<#
 .SYNOPSIS
    Sets the policy for a list of TeamViewer devices

 .DESCRIPTION
    The script fetches TeamViewer devices from the TeamViewer company that
    corresponds to the given API token. It will set the policy of those devices
    to either inherit from their parent group or to a policy with the given ID.
    An optional group filter restricts the operation to only those devices that
    are member of the groups with the given names or IDs.
    There is also the option to exclude specific devices by their device ID.
    Devices that are not assigned to the user that corresponds to the API token
    will be skipped.

 .PARAMETER ApiToken
    The TeamViewer API token to use.
    Must be a user access token.
    The token requires the following access permissions:
        - `Computer & Contacts > View entries, add entries, edit entries, remove entries`
        - `Group Management > Read groups` (optional - Groups names filtering)

 .PARAMETER Policy
    The policy to set for the devices.
    Mutually exclusive with the parameter `PolicyId`.
    Can be either `None` for no policy or `Inherit` to inherit the policy of the
    parent group.
    Defaults to `Inherit`.

 .PARAMETER PolicyId
    Specific ID of the policy to set for the devices.
    Mutually exclusive with the parameter `Policy`.

 .PARAMETER FilterGroupNames
    Optionally apply policy changes only to devices that are member of the groups
    with the given names.

 .PARAMETER FilterGroupIds
    Optionally apply policy changes only to devices that are member of the groups
    with the given IDs.

 .PARAMETER ExcludedDeviceIds
    Optionally exclude devices with the given IDs from the policy changes.

 .EXAMPLE
    .\Set-TeamViewerDevicesPolicy.ps1

 .EXAMPLE
    .\Set-TeamViewerDevicesPolicy.ps1 -WhatIf

 .EXAMPLE
    .\Set-TeamViewerDevicesPolicy.ps1 -FilterGroupNames "Group1","Group2"

 .EXAMPLE
    .\Set-TeamViewerDevicesPolicy.ps1 -PolicyId '388e8704-0f4a-4b4d-bdbf-2be823ae690f'

 .EXAMPLE
    .\Set-TeamViewerDevicesPolicy.ps1 -ExcludedDeviceIds 'd12345678','d90123456'

 .NOTES
    Copyright (c) 2019 TeamViewer GmbH
    See file LICENSE.txt
    Version 1.0.0
#>

[CmdletBinding(DefaultParameterSetName = "Policy", SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $ApiToken,

    [Parameter(ParameterSetName = 'Policy', Mandatory = $false)]
    [ValidateSet('None', 'Inherit')]
    [string] $Policy = 'Inherit',

    [Parameter(ParameterSetName = 'SpecificPolicy', Mandatory = $true)]
    [string] $PolicyId,

    [Parameter(Mandatory = $false)]
    [string[]] $FilterGroupNames,

    [Parameter(Mandatory = $false)]
    [string[]] $FilterGroupIds,

    [Parameter(Mandatory = $false)]
    [string[]] $ExcludedDeviceIds
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

function Get-TeamViewerGroup($accessToken, $name) {
    if ($name) { $body = @{ name = $name } }
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/groups" `
        -Method Get -Headers @{authorization = "Bearer $accessToken"} -Body $body
}

function Get-TeamViewerDevice($accessToken, $groupId) {
    if ($groupId) { $body = @{ groupid = $groupId } }
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/devices" `
        -Method Get -Headers @{authorization = "Bearer $accessToken"} -Body $body
}

function Edit-TeamViewerDevicePolicy($accessToken, $deviceId, $policyId) {
    $payload = @{policy_id = $policyId}
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/devices/$deviceId" `
        -Method Put -Headers @{authorization = "Bearer $accessToken"} `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Set-TeamViewerDevicesPolicy {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param($apiToken, $policy, $groupNames, $groupIds, $excludedDeviceIds)

    # Fetch groups by name and get device list for each of them.
    if ($groupNames) {
        $groups = $groupNames | ForEach-Object {
            $groupName = $_
            @(Get-TeamViewerGroup $apiToken $_).groups | `
                Where-Object { $_.name -eq $groupName }
        }
        $devices = $groups | `
            Select-Object -ExpandProperty 'id' | `
            ForEach-Object { @(Get-TeamViewerDevice $apiToken $_).devices }
    }
    # Fetch device list for each group corresponding to the given IDs.
    elseif ($groupIds) {
        $devices = $groupIds | ForEach-Object { @(Get-TeamViewerDevice $apiToken $_).devices }
    }
    # Fetch all devices otherwise.
    else {
        $devices = (@(Get-TeamViewerDevice $apiToken).devices)
    }

    # Filter-out excluded devices and devices that are not assigned to the user
    $devices = @($devices | Where-Object { $_.device_id -notin $excludedDeviceIds })

    Write-Information "Setting policy to '$policy' for $($devices.Count) device(s)"

    # Set policy for all identified devices
    ForEach ($device in $devices) {
        $status = 'Unchanged';
        if ($device.assigned_to -ne 'True') {
            $status = 'Skipped'
        }
        elseif ($PSCmdlet.ShouldProcess($device.alias)) {
            try {
                Edit-TeamViewerDevicePolicy $apiToken $device.device_id $policy | Out-Null
                $status = 'Updated'
            }
            catch {
                Write-Warning "Failed to set policy for device '$($device.alias)': $_"
                $status = 'Failed'
            }
        }
        Write-Output ([pscustomobject]@{
                DeviceId = $device.device_id
                Alias    = $device.alias
                Policy   = $policy
                Status   = $status
            })
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $targetPolicy = if ($PSCmdlet.ParameterSetName -eq 'SpecificPolicy') { $PolicyId } else { $Policy }
    Set-TeamViewerDevicesPolicy $ApiToken $targetPolicy $FilterGroupNames $FilterGroupIds $ExcludedDeviceIds
}
