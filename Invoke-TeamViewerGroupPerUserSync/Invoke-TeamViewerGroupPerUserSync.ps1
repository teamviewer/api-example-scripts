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
    .\Invoke-TeamViewerGroupPerUserSync -ApiToken 'MyApiToken' -MappingFilePath 'MyMappings.csv' -SourceGroupName 'My Computers'

 .EXAMPLE
    .\Invoke-TeamViewerGroupPerUserSync -ApiToken 'MyApiToken' -MappingFilePath 'MyMappings.csv' -IgnoreSourceGroup

 .NOTES
    Copyright (c) 2020 TeamViewer GmbH
    Version 1.2
#>

[CmdletBinding(DefaultParameterSetName = 'Default', SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $ApiToken,

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

$tvApiBaseUrl = 'https://webapi.teamviewer.com'

# Adapt this function in case the group name should follow a different pattern:
function ConvertTo-GroupName($user) {
    return "Devices of $($user.email)"
}

function ConvertTo-TeamViewerRestError {
    param([parameter(ValueFromPipeline)]$err)
    try { return ($err | Out-String | ConvertFrom-Json) }
    catch { return $err }
}

function Invoke-TeamViewerRestMethod {
    try { return ((Invoke-WebRequest -UseBasicParsing @args).Content | ConvertFrom-Json) }
    catch [System.Net.WebException] {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $reader.BaseStream.Position = 0
        Throw ($reader.ReadToEnd() | ConvertTo-TeamViewerRestError)
    }
}

function Invoke-TeamViewerPing($accessToken) {
    $result = Invoke-TeamViewerRestMethod `
        -Uri "$tvApiBaseUrl/api/v1/ping" `
        -Method Get `
        -Headers @{authorization = "Bearer $accessToken" }
    return $result -And $result.token_valid
}

function Get-TeamViewerUser($accessToken) {
    $result = Invoke-TeamViewerRestMethod `
        -Uri "$tvApiBaseUrl/api/v1/users" `
        -Method Get `
        -Headers @{authorization = "Bearer $accessToken" }
    return $result.users
}

function Get-TeamViewerGroup($accessToken) {
    $result = Invoke-TeamViewerRestMethod `
        -Uri "$tvApiBaseUrl/api/v1/groups" `
        -Method Get `
        -Headers @{authorization = "Bearer $accessToken" }
    return $result.groups
}

function Add-TeamViewerGroup($accessToken, $group) {
    $missingFields = (@('name') | Where-Object { !$group[$_] })
    if ($missingFields.Count -gt 0) {
        Throw "Cannot create group! Missing required fields [$missingFields]!"
    }
    $payload = @{ }
    @('name') | Where-Object { $group[$_] } | ForEach-Object { $payload[$_] = $group[$_] }
    return Invoke-TeamViewerRestMethod `
        -Uri "$tvApiBaseUrl/api/v1/groups" `
        -Method Post `
        -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType "application/json; charset=utf-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Add-TeamViewerGroupShare($accessToken, $groupId, $user) {
    $missingFields = (@('userid', 'permissions') | Where-Object { !$user[$_] })
    if ($missingFields.Count -gt 0) {
        Throw "Cannot create group share! Missing required fields [$missingFields]!"
    }
    $payload = @{ users = @(@{ }) }
    @('userid', 'permissions') | Where-Object { $user[$_] } | ForEach-Object { $payload.users[0][$_] = $user[$_] }
    return Invoke-TeamViewerRestMethod `
        -Uri "$tvApiBaseUrl/api/v1/groups/$groupId/share_group" `
        -Method Post `
        -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType "application/json; charset=utf-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Get-TeamViewerDevice($accessToken) {
    $result = Invoke-TeamViewerRestMethod `
        -Uri "$tvApiBaseUrl/api/v1/devices" `
        -Method Get `
        -Headers @{authorization = "Bearer $accessToken" }
    return $result.devices
}

function Edit-TeamViewerDevice($accessToken, $deviceId, $device) {
    $payload = @{ }
    @('groupid') | Where-Object { $device[$_] } | ForEach-Object { $payload[$_] = $device[$_] }
    return Invoke-TeamViewerRestMethod `
        -Uri "$tvApiBaseUrl/api/v1/devices/$deviceId" `
        -Method Put `
        -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType "application/json; charset=utf-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

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
    param($apiToken, $sourceGroupName, [bool]$ignoreSourceGroup, $mappingData)

    Write-Log "Script started"
    Write-Log "Environment: OS $([environment]::OSVersion.VersionString), PS $($PSVersionTable.PSVersion)"
    Write-Log "Read $($mappingData.Count) mapping entries from CSV."

    Write-Log "Checking connection to TeamViewer API."
    if (!(Invoke-TeamViewerPing -accessToken $apiToken)) {
        Write-Log -Fatal "Failed to contact TeamViewer API. Invalid token or connection problem. Aborting."
    }

    $statistics = @{ Updated = 0; Failed = 0; Unchanged = 0; }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Fetch current users/devices/groups:

    Write-Log "Fetching TeamViewer company users."
    $users = @(Get-TeamViewerUser -accessToken $apiToken)
    $usersByEmail = @{ }
    ($users | ForEach-Object { $usersByEmail[$_.email] = $_ } | Out-Null)
    Write-Log "Retrieved $($users.Count) TeamViewer company users."

    Write-Log "Fetching TeamViewer groups of administrative user."
    $groups = @(Get-TeamViewerGroup -accessToken $apiToken)
    $groupsByName = @{ }
    ($groups | ForEach-Object { $groupsByName[$_.name] = $_ } | Out-Null)
    Write-Log "Retrieved $($groups.Count) TeamViewer groups."

    Write-Log "Fetching TeamViewer devices list of administrative user."
    $devices = @(Get-TeamViewerDevice -accessToken $apiToken)
    $devicesByAlias = @{ }
    $devicesByRemoteControlId = @{}
    ($devices | Where-Object { $_.alias } | ForEach-Object { $devicesByAlias[$_.alias] = $_ } | Out-Null)
    ($devices | Where-Object { $_.remotecontrol_id } | ForEach-Object { $devicesByRemoteControlId[$_.remotecontrol_id] = $_ } | Out-Null)
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
                    $group = (Add-TeamViewerGroup -accessToken $apiToken -group @{name = $groupName })
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
        $device = $devicesByRemoteControlId["r$($entry.teamviewerid)"]
        if (!$device) {
            # Second, try to resolve device by alias
            $device = $devicesByAlias[$entry.device]
            if (!$device) {
                Write-Log -Severity Error "Device '$(if ($entry.device) { $entry.device } else { $entry.teamviewerid })' not found. Skipping"
                $statistics.Failed++
                continue
            }
        }
        if (!$ignoreSourceGroup -And $device.groupid -ne $sourceGroup.id) {
            Write-Log -Severity Warning "Device '$($device.alias)' not in source group. Skipping."
            $statistics.Unchanged++
            continue
        }

        # Move device to target group, if not yet done.
        if (!$device.groupid -or $device.groupid -ne $group.id) {
            try {
                Write-Log "Moving device '$($device.alias)' to group '$groupName'."
                if ($PSCmdlet.ShouldProcess("Move device '$($device.alias)' to group '$groupName'.")) {
                    Edit-TeamViewerDevice `
                        -accessToken $apiToken `
                        -deviceId $device.device_id `
                        -device @{groupid = $group.id } | Out-Null
                }
                $didUpdate = $true
            }
            catch {
                Write-Log -Severity Error "Failed to move device '$($device.alias)' to group '$groupName'. Error: $_"
                $statistics.Failed++
                continue
            }
        }
        else {
            Write-Log "Device '$($device.alias)' is already in group '$groupName'. Ignoring."
        }

        # Share target group with user, if not yet done.
        $sharedUserIds = (@($group.shared_with) | Select-Object -ExpandProperty userid)
        if ($user.id -notin $sharedUserIds) {
            try {
                Write-Log "Sharing group '$groupName' with user '$($user.email)'."
                if ($PSCmdlet.ShouldProcess("Sharing group '$groupName' with user '$($user.email)'.")) {
                    $share = @{ userid = $user.id; permissions = 'full' }
                    Add-TeamViewerGroupShare `
                        -accessToken $apiToken `
                        -groupId $group.id `
                        -user $share | Out-Null
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
    $mappingData = @(Import-Csv -Path $MappingFilePath -Delimiter ',')

    Invoke-TeamViewerGroupPerUserSync `
        -apiToken $ApiToken `
        -sourceGroupName $SourceGroupName `
        -ignoreSourceGroup $IgnoreSourceGroup `
        -mappingData $mappingData `
    | Format-Log `
    | Out-Log
}
