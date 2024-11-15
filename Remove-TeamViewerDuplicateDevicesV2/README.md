# Remove-TeamViewerDuplicateDevicesV2

Removes TeamViewer devices (MDv2) that have a duplicate counterpart in the same company.

The script fetches a list of TeamViewer devices (MDv2) of the TeamViewer company that corresponds to a given API token.
The list will be searched for devices that have the same name (alias). Duplicate devices will be sorted by their last seen timestamp,
and the older ones will be removed.

## Prerequisites

This script requires the `TeamViewerPS` powershell module to be installed in at least Version 2.1.0.

```powershell
Install-Module TeamViewerPS
```

## Examples

### List removal candidate devices

```powershell
Remove-TeamViewerDuplicateDevicesV2 -WhatIf
```

### Remove old duplicate devices. User needs to confirm

```powershell
Remove-TeamViewerDuplicateDevicesV2
```

### Remove old duplicate devices without further confirmation

```powershell
Remove-TeamViewerDuplicateDevicesV2 -Force
```

## More help

To get further help about the script and its parameters, execute the
`Get-Help` PowerShell cmdlet:

```powershell
Get-Help -Detailed .\Remove-TeamViewerDuplicateDevicesV2.ps1
```
