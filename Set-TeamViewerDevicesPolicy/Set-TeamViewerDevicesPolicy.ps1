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
    This script requires the TeamViewerPS module to be installed.
    This can be done using the following command:

    ```
    Install-Module TeamViewerPS
    ```

    Copyright (c) 2019-2021 TeamViewer GmbH
    See file LICENSE.txt
    Version 2.0
#>

[CmdletBinding(DefaultParameterSetName = "Policy", SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [securestring] $ApiToken,

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

function Install-TeamViewerModule { if (!(Get-Module TeamViewerPS)) { Install-Module TeamViewerPS } }

function Set-TeamViewerDevicesPolicy {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param($policy, $groupNames, $groupIds, $excludedDeviceIds)

    # Fetch groups by name and get device list for each of them.
    if ($groupNames) {
        $groups = $groupNames | ForEach-Object {
            $groupName = $_
            @(Get-TeamViewerGroup -ApiToken $ApiToken -Name $groupName) | `
                Where-Object { $_.Name -eq $groupName }
        }
        $devices = $groups | ForEach-Object {
            @(Get-TeamViewerDevice -ApiToken $ApiToken -Group $_)
        }
    }
    # Fetch device list for each group corresponding to the given IDs.
    elseif ($groupIds) {
        $devices = $groupIds | ForEach-Object {
            @(Get-TeamViewerDevice -ApiToken $ApiToken -GroupId $_)
        }
    }
    # Fetch all devices otherwise.
    else {
        $devices = @(Get-TeamViewerDevice -ApiToken $ApiToken)
    }

    # Filter-out excluded devices and devices that are not assigned to the user
    $devices = @($devices | Where-Object { $_.Id -notin $excludedDeviceIds })

    Write-Information "Setting policy to '$policy' for $($devices.Count) device(s)"

    # Set policy for all identified devices
    ForEach ($device in $devices) {
        $status = 'Unchanged';
        if ($device.IsAssignedToCurrentAccount -ne 'True') {
            $status = 'Skipped'
        }
        elseif ($PSCmdlet.ShouldProcess($device.Name)) {
            try {
                Set-TeamViewerDevice -ApiToken $ApiToken -Device $device -Policy $policy | Out-Null
                $status = 'Updated'
            }
            catch {
                Write-Warning "Failed to set policy for device '$device': $_"
                $status = 'Failed'
            }
        }
        Write-Output ([pscustomobject]@{
                DeviceId = $device.Id
                Alias    = $device.Name
                Policy   = $policy
                Status   = $status
            })
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Install-TeamViewerModule
    $targetPolicy = if ($PSCmdlet.ParameterSetName -eq 'SpecificPolicy') { $PolicyId } else { $Policy.ToLower() }
    Set-TeamViewerDevicesPolicy `
        -policy $targetPolicy `
        -groupNames $FilterGroupNames `
        -groupIds $FilterGroupIds `
        -excludedDeviceIds $ExcludedDeviceIds
}
