<#
 .SYNOPSIS
    Removes TeamViewer duplicate devices (MDv2) based on their alias.

 .DESCRIPTION
    Removes TeamViewer devices (MDv2) that have a duplicate counterpart in the same company.
    The script fetches a list of TeamViewer devices (MDv2) of the TeamViewer company that corresponds to a given API token.
    The list will be searched for devices that have the same name (alias). Duplicate devices will be sorted by their last seen timestamp,
    and the older ones will be removed.

 .PARAMETER ApiToken
    The TeamViewer API token to use.
    Must be a user access token.
    The token requires the following access permissions: company admin

 .PARAMETER Force
    If set, the script will NOT ask the user for confirmation of the removal.
    The default value is `false`, causing the script to ask the user one more time before starting to remove devices.

 .EXAMPLE
    Remove-TeamViewerDuplicateDevicesV2'

 .EXAMPLE
    Remove-TeamViewerDuplicateDevicesV2 -WhatIf

 .EXAMPLE
    Remove-TeamViewerDuplicateDevicesV2 -Force

 .NOTES
    This script requires the TeamViewerPS module to be installed.
    This can be done using the following command:

    ```
    Install-Module TeamViewerPS
    ```

    Copyright (c) 2019-2024 TeamViewer Germany GmbH
    See file LICENSE
    Version 2.1
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
   [Parameter(Mandatory = $true)]
   [securestring] $ApiToken,

   [switch] $Force = $false
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
   elseif ($module.Version -lt '2.1.0') {
      Update-Module TeamViewerPS
   }
}

function Remove-TeamViewerDuplicateDevicesV2 {
   [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
   param([bool]$force, [bool]$is_verbose)

   $devices = @(Get-TeamViewerCompanyManagedDevice -ApiToken $ApiToken)

   $name_to_device_map = @{}
   ForEach ($device in $devices) {
      if ($null -eq $name_to_device_map[$device.Name]) {
         $name_to_device_map[$device.Name] = New-Object System.Collections.Generic.List[System.Object]
      }
      $name_to_device_map[$device.Name].Add($device)
   }

   $name_to_device_map_sorted = @{}
   $name_to_device_map.GetEnumerator() | ForEach-Object {
      # Sort duplicate devices by LastSeenAt.
      # Older devices should go first.
      $offline_duplicate_devices = @(($_.Value | Where-Object { !$_.IsOnline -and $_.LastSeenAt }) | Sort-Object { $_.LastSeenAt })

      if ($offline_duplicate_devices.Count -gt 0) {
         if ($offline_duplicate_devices.Count -lt $_.Value.Count) {
            # There were some online duplicate devices --> remove all of the offline
            $name_to_device_map_sorted.Add($_.Key, $offline_duplicate_devices)
         }
         else {
            # No online duplicate devices --> the last one is the "good" device --> skip it
            $devices_to_remove = $offline_duplicate_devices | Select-Object -SkipLast 1
            if ($null -ne $devices_to_remove) {
               $name_to_device_map_sorted.Add($_.Key, $devices_to_remove)
            }
         }
      }
   }

   if ($is_verbose) {
      Write-Information 'All company devices:'
      Write-Information ($devices | Format-List | Out-String)
   }

   if (!$name_to_device_map_sorted.Count) {
      Write-Information 'No duplicate devices found. Exiting...'

      exit
   }

   Write-Information 'Found the following devices that have a duplicate alias to other devices in your company, and have been offline for longer:'
   Write-Information ($name_to_device_map_sorted | Format-List | Out-String)

   if ($name_to_device_map_sorted.Count -gt 0 -And
      !$WhatIfPreference -And
      !$force -And
      !$PSCmdlet.ShouldContinue('Do you really want to remove those devices?', 'Remove managed devices')) {
      Write-Information 'Aborting...'

      exit
   }

   $name_to_device_map_sorted.GetEnumerator() | ForEach-Object {
      $duplicate_devices_to_be_deleted = $_.Value

      ForEach ($device_to_be_deleted in $duplicate_devices_to_be_deleted) {
         $status = 'Unchanged'

         if ($force -Or $PSCmdlet.ShouldProcess($device_to_be_deleted.TeamViewerId, 'Remove device')) {
            try {
               Remove-TeamViewerManagedDeviceManagement -ApiToken $ApiToken -Device $device_to_be_deleted

               $status = 'Removed'
            }
            catch {
               Write-Warning "Failed to remove device '$($device_to_be_deleted.Name)' with TeamViewerID: '$($device_to_be_deleted.TeamViewerId)'"

               $status = 'Failed'
            }
         }
         Write-Output ([pscustomobject]@{
               Name         = $device_to_be_deleted.Name
               ManagementId = $device_to_be_deleted.Id
               LastSeen     = $device_to_be_deleted.LastSeenAt
               TeamViewerID = $device_to_be_deleted.TeamViewerId
               Status       = $status
            })
      }
   }
}

if ($MyInvocation.InvocationName -ne '.') {
   Install-TeamViewerModule

   $is_verbose = $PSBoundParameters.ContainsKey('Verbose')

   Remove-TeamViewerDuplicateDevicesV2 -force $Force -is_verbose $is_verbose
}
