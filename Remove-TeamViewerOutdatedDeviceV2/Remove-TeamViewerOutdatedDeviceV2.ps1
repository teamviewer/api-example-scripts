<#
 .SYNOPSIS
    Removes TeamViewer devices (MDv2) that didn't appear online for a given time.

 .DESCRIPTION
    The script fetches a list of TeamViewer devices (MDv2) of the TeamViewer company that corresponds to a given API token.
    The list will be filtered by devices being offline for a certain amount of time. These devices will be removed.
    The expiration can either be specified by a specific date or by interval.

 .PARAMETER ApiToken
    The TeamViewer API token to use.
    Must be a user access token.
    The token requires the following access permissions: `Device Groups > read operations, modifying operations`

 .PARAMETER ExpiryDate
    A specific expiry date. All devices that haven't been online since that date are considered being removed.

 .PARAMETER ExpiryInterval
    Switch that enables interval-based calculation of the expiration date.
    Should be used in combination with the `Days`, `Hours`, `Minutes` and/or `Seconds` parameter.

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

 .PARAMETER Force
    If set, the script will NOT ask the user for confirmation of the removal.
    This parameter only has effect in combination with the `Remove` parameter.
    The default value is `false`, causing the script to ask the user one more time before starting to remove devices.

 .EXAMPLE
    .\Remove-TeamViewerOutdatedDeviceV2 -ExpiryDate '2018-12-17T17:00:00'

 .EXAMPLE
    .\Remove-TeamViewerOutdatedDeviceV2 -ExpiryDate 2018-12-31 -WhatIf

 .EXAMPLE
    .\Remove-TeamViewerOutdatedDeviceV2 -ExpiryInterval -Days 10

 .EXAMPLE
    .\Remove-TeamViewerOutdatedDeviceV2 -ExpiryInterval -Hours 12 -Force

 .NOTES
     This script requires the TeamViewerPS module to be installed.
    This can be done using the following command:

    ```
    Install-Module TeamViewerPS
    ```

    Copyright (c) 2019-2023 TeamViewer Germany GmbH
    See file LICENSE
    Version 2.1
#>

[CmdletBinding(DefaultParameterSetName = 'ExactDate', SupportsShouldProcess = $true)]
param(
   [Parameter(Mandatory = $true)]
   [securestring] $ApiToken,

   [Parameter(ParameterSetName = 'ExactDate', Mandatory = $true)]
   [DateTime] $ExpiryDate,

   [Parameter(ParameterSetName = 'DateInterval', Mandatory = $true)]
   [switch] $ExpiryInterval,

   [Parameter(ParameterSetName = 'DateInterval', Mandatory = $false)]
   [int] $Days,

   [Parameter(ParameterSetName = 'DateInterval', Mandatory = $false)]
   [int] $Hours,

   [Parameter(ParameterSetName = 'DateInterval', Mandatory = $false)]
   [int] $Minutes,

   [Parameter(ParameterSetName = 'DateInterval', Mandatory = $false)]
   [int] $Seconds,

   [Switch] $Force = $false
)

if (-Not $MyInvocation.BoundParameters.ContainsKey('ErrorAction')) {
   $script:ErrorActionPreference = 'Stop'
}
if (-Not $MyInvocation.BoundParameters.ContainsKey('InformationAction')) {
   $script:InformationPreference = 'Continue'
}

function Install-TeamViewerModule {
   $module = Get-Module TeamViewerPS

   if (!$module) {
      Install-Module TeamViewerPS
   }
   elseif ($module.Version -lt '2.4.0') {
      Update-Module TeamViewerPS
   }
}

function Remove-TeamViewerOutdatedDeviceV2 {
   [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
   param($expiryDate, [bool]$force)

   $devices = @((Get-TeamViewerManagedDevice -ApiToken $ApiToken) | Where-Object { !$_.IsOnline -And $_.LastSeenAt -And $_.LastSeenAt -le $expiryDate })

   Write-Information "Found $($devices.Count) devices that have been offline since $expiryDate"

   if ($devices.Count -gt 0 -And -Not $WhatIfPreference -And -Not $force -And -Not $PSCmdlet.ShouldContinue('Do you really want to remove those devices?', $devices)) {
      Write-Information 'Aborting...'

      exit
   }

   ForEach ($device in $devices) {
      $status = 'Unchanged'

      if ($force -Or $PSCmdlet.ShouldProcess($device.Name)) {
         try {
            Remove-TeamViewerManagedDeviceManagement -ApiToken $ApiToken -Device $device

            $status = 'Removed'
         }
         catch {
            Write-Warning "Failed to remove device '$($device.Name)': $_"

            $status = 'Failed'
         }
      }
      Write-Output ([pscustomobject]@{
            Name     = $device.Name
            DeviceId = $device.Id
            LastSeen = $device.LastSeenAt
            Status   = $status
         })
   }
}

if ($MyInvocation.InvocationName -ne '.') {
   Install-TeamViewerModule

   $now = (Get-Date)

   if ($ExpiryInterval) {
      $ExpiryDate = $now.AddDays(-1 * $Days).AddHours(-1 * $Hours).AddMinutes(-1 * $Minutes).AddSeconds(-1 * $Seconds)
   }

   if ($ExpiryDate -ge $now) {
      Throw "Invalid expiry date specified: $ExpiryDate"
   }

   Remove-TeamViewerOutdatedDeviceV2 -expiryDate $ExpiryDate -force $Force
}
