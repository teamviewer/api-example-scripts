<#
 .SYNOPSIS
    Moves devices to a shared group per user

 .DESCRIPTION
    The script moves device entries from a common group to a shared group per
    user. If such group doesn't exist, it will attempt to create the group.
    Then it moves the device into that group and shares it with the respective
    user. If the device is already present in the group or the group is already
    shared with the user, the entry is skipped without doing any changes.

    The caller needs to provide mapping data that maps a device to a user.
    The data needs to be in CSV format and must have the following columns:
        - email
          (The email of the user to map the device to.)
        - device
          (The alias of the device.)
        - teamviewerid
          (The TeamViewer ID of the device.)

    To resolve a certain device, the script prefers the TeamViewer ID over the
    alias. The TeamViewer ID can also be left blank, so the script will only
    try to resolve via the given device alias.

    The created groups are named using the following pattern:
        "Devices of user@example.test"
        (using the user's email address)

    By default, this script writes log data to a file in the current working
    directory using the following name pattern:
        "TeamViewerGroupPerUserSync.2020-03-11_17:00:00.log"
        (using the date/time of the script invocation)

 .PARAMETER ApiToken
    The TeamViewer API token to use.
    Must be a user access token.
    The token requires the following access permissions:
        - "User management": "View users"
        - "Group management": "View, create, delete, edit and share groups"
        - "Computer & Contacts": "View, add, edit and delete entries"

 .PARAMETER MappingFilePath
    Path to the file that holds the mappings between users (email) and devices.
    The file needs to be in CSV format (using "," comma delimiter) and must
    provide the columns described above: email, device

 .PARAMETER SourceGroupName
    The name of the group, where all devices are currently located.
    If this parameter is set, only devices from that group are considered for
    the sync.
    Devices will be moved out of this group into the respective per-user groups.
    Cannot be used in combination with the `IgnoreSourceGroup` parameter.

 .PARAMETER IgnoreSourceGroup
    If set, there will be no restriction/filtering done on the current group of
    devices. All devices of the account associated with the API token are
    considered, regardless of their current group.

 .PARAMETER NoLogFile
    Optionally, suppresses outputting log data to a file.

 .EXAMPLE
    .\Invoke-TeamViewerGroupPerUserSync -MappingFilePath 'MyMappings.csv' -SourceGroupName 'My Computers'

 .EXAMPLE
    .\Invoke-TeamViewerGroupPerUserSync -MappingFilePath 'MyMappings.csv' -IgnoreSourceGroup

 .NOTES
    This script requires the TeamViewerPS module to be installed.
    This can be done using the following command:

    ```
    Install-Module TeamViewerPS
    ```

    Copyright (c) 2020-2021 TeamViewer GmbH
    Version 2.0
#>

[CmdletBinding(DefaultParameterSetName = 'Default', SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [securestring] $ApiToken,

    [Parameter(Mandatory = $true)]
    [string] $MappingFilePath,

    [Parameter(ParameterSetName = 'Default', Mandatory = $true)]
    [string] $SourceGroupName,

    [Parameter(ParameterSetName = 'IgnoreSourceGroup')]
    [switch] $IgnoreSourceGroup,

    [Parameter(Mandatory = $false)]
    [switch] $NoLogFile
)

if (-Not $MyInvocation.BoundParameters.ContainsKey('ErrorAction')) { $script:ErrorActionPreference = 'Stop' }
if (-Not $MyInvocation.BoundParameters.ContainsKey('InformationAction')) { $script:InformationPreference = 'Continue' }
if (-Not $MyInvocation.BoundParameters.ContainsKey('ProgressPreference')) { $script:ProgressPreference = 'SilentlyContinue' }

# Adapt this function in case the group name should follow a different pattern:
function ConvertTo-GroupName($user) {
    return "Devices of $($user.email)"
}

function Install-TeamViewerModule { if (!(Get-Module TeamViewerPS)) { Install-Module TeamViewerPS } }

function Write-Log {
    param(
        [Parameter(ValueFromPipeline)] $message,
        [Parameter(Mandatory = $false)][ValidateSet('Info', 'Error', 'Warning')][string] $Severity = "Info",
        [Parameter(Mandatory = $false)] [switch] $Fatal)
    if ($Fatal) {
        $Severity = 'Error'
    }
    Write-Output -InputObject @{
        Date     = (Get-Date)
        Message  = $message
        Severity = $Severity
    } -NoEnumerate
    if ($Fatal) { Write-Error $message }
}

function Format-Log {
    Process {
        if ($_ -is [object] -And $_ -And $_.Date -And $_.Message -And $_.Severity) {
            "$("{0:yyyy-MM-dd HH:mm:ss}" -f $_.Date) [$($_.Severity.ToUpper())]: $($_.Message)"
        }
        elseif ($_ -is [object] -And $_ -And $_.Statistics -And $_.Duration) {
            "$($_.Statistics | Format-Table -AutoSize -HideTableHeaders | Out-String)"
            "Duration: $($_.Duration)"
        }
        else { $_ }
    }
}

function Out-Log {
    Begin {
        $filename = "TeamViewerGroupPerUserSync.$("{0:yyyy-MM-dd_HHmmss}" -f (Get-Date)).log"
    }
    Process {
        if (-Not $NoLogFile -And -Not $WhatIfPreference) {
            $_ | Tee-Object -Append -FilePath $filename
        }
        else {
            $_
        }
    }
}

function Invoke-TeamViewerGroupPerUserSync {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param($sourceGroupName, [bool]$ignoreSourceGroup, $mappingData)

    Write-Log "Script started"
    Write-Log "Environment: OS $([environment]::OSVersion.VersionString), PS $($PSVersionTable.PSVersion)"
    Write-Log "Read $($mappingData.Count) mapping entries from CSV."

    Write-Log "Checking connection to TeamViewer API."
    if (!(Invoke-TeamViewerPing -ApiToken $ApiToken)) {
        Write-Log -Fatal "Failed to contact TeamViewer API. Invalid token or connection problem. Aborting."
    }

    $statistics = @{ Updated = 0; Failed = 0; Unchanged = 0; }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Fetch current users/devices/groups:

    Write-Log "Fetching TeamViewer company users."
    $users = @(Get-TeamViewerUser -ApiToken $ApiToken)
    $usersByEmail = @{ }
    ($users | ForEach-Object { $usersByEmail[$_.Email] = $_ } | Out-Null)
    Write-Log "Retrieved $($users.Count) TeamViewer company users."

    Write-Log "Fetching TeamViewer groups of administrative user."
    $groups = @(Get-TeamViewerGroup -ApiToken $ApiToken)
    $groupsByName = @{ }
    ($groups | ForEach-Object { $groupsByName[$_.Name] = $_ } | Out-Null)
    Write-Log "Retrieved $($groups.Count) TeamViewer groups."

    Write-Log "Fetching TeamViewer devices list of administrative user."
    $devices = @(Get-TeamViewerDevice -ApiToken $ApiToken)
    $devicesByAlias = @{ }
    $devicesByRemoteControlId = @{}
    ($devices | Where-Object { $_.Name } | ForEach-Object { $devicesByAlias[$_.Name] = $_ } | Out-Null)
    ($devices | Where-Object { $_.TeamViewerId } | ForEach-Object { $devicesByRemoteControlId[$_.TeamViewerId] = $_ } | Out-Null)
    Write-Log "Retrieved $($devices.Count) TeamViewer devices."

    # Check for source group
    $sourceGroup = $groupsByName[$sourceGroupName]
    if (!$ignoreSourceGroup -And !$sourceGroup) {
        Write-Log -Fatal "Source group with name '$($sourceGroupName)' not found. Aborting."
    }

    Write-Log "Starting processing of $($mappingData.Count) given mapping entries."
    $count = 0
    $totalCount = $mappingData.Count
    foreach ($entry in $mappingData) {
        $count++
        Write-Log "Processing entry [$count/$totalCount] - email: '$($entry.email)', device: '$($entry.device)', teamviewerid: '$($entry.teamviewerid)'."

        $user = $usersByEmail[$entry.email]
        if (!$user) {
            Write-Log -Severity Error "Failed to find user with email '$($entry.email)'. Skipping."
            $statistics.Failed++
            continue
        }

        $didUpdate = $false

        # Get group and create if not yet existing
        $groupName = (ConvertTo-GroupName $user)
        $group = $groupsByName[$groupName]
        if (!$group) {
            Write-Log "Creating group '$groupName'."
            try {
                if ($PSCmdlet.ShouldProcess("Create group '$groupName'.")) {
                    $group = (New-TeamViewerGroup -ApiToken $ApiToken -Name $groupName)
                    $groups += @($group)
                    $groupsByName[$groupName] = $group
                }
                $didUpdate = $true
            }
            catch {
                Write-Log -Severity Error "Failed to create group '$groupName'. Error: $_"
                $statistics.Failed++
                continue
            }
        }

        # First, try to resolve device by TeamViewer ID
        $device = $devicesByRemoteControlId["$($entry.teamviewerid)"]
        if (!$device) {
            # Second, try to resolve device by alias
            $device = $devicesByAlias[$entry.device]
            if (!$device) {
                Write-Log -Severity Error "Device '$(if ($entry.device) { $entry.device } else { $entry.teamviewerid })' not found. Skipping"
                $statistics.Failed++
                continue
            }
        }
        if (!$ignoreSourceGroup -And $device.GroupId -ne $sourceGroup.id) {
            Write-Log -Severity Warning "Device '$($device.Name)' not in source group. Skipping."
            $statistics.Unchanged++
            continue
        }

        # Move device to target group, if not yet done.
        if (!$device.GroupId -or $device.GroupId -ne $group.Id) {
            try {
                Write-Log "Moving device '$($device.Name)' to group '$groupName'."
                if ($PSCmdlet.ShouldProcess("Move device '$($device.Name)' to group '$groupName'.")) {
                    Set-TeamViewerDevice `
                        -ApiToken $ApiToken `
                        -Device $device `
                        -Group $group | Out-Null
                }
                $didUpdate = $true
            }
            catch {
                Write-Log -Severity Error "Failed to move device '$($device.Name)' to group '$groupName'. Error: $_"
                $statistics.Failed++
                continue
            }
        }
        else {
            Write-Log "Device '$($device.Name)' is already in group '$groupName'. Ignoring."
        }

        # Share target group with user, if not yet done.
        $sharedUserIds = (@($group.SharedWith) | Select-Object -ExpandProperty UserId)
        if ($user.id -notin $sharedUserIds) {
            try {
                Write-Log "Sharing group '$groupName' with user '$($user.email)'."
                if ($PSCmdlet.ShouldProcess("Sharing group '$groupName' with user '$($user.email)'.")) {
                    Publish-TeamViewerGroup `
                        -ApiToken $ApiToken `
                        -Group $group `
                        -User $user `
                        -Permissions readwrite | Out-Null
                }
                $didUpdate = $true
            }
            catch {
                Write-Log -Severity Error "Failed to share group '$groupName' with user '$($user.email)'. Error: $_"
                $statistics.Failed++
                continue
            }
        }
        else {
            Write-Log "Group '$groupName' is already shared with user '$($user.email)'. Ignoring."
        }

        if ($didUpdate) { $statistics.Updated++ }
        else { $statistics.Unchanged++ }
    }

    Write-Log "Script finished"
    $stopwatch.Stop()

    Write-Output @{
        Statistics = $statistics
        Duration   = $stopwatch.Elapsed
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Install-TeamViewerModule

    $mappingData = @(Import-Csv -Path $MappingFilePath -Delimiter ',')

    Invoke-TeamViewerGroupPerUserSync `
        -sourceGroupName $SourceGroupName `
        -ignoreSourceGroup $IgnoreSourceGroup `
        -mappingData $mappingData `
    | Format-Log `
    | Out-Log
}
