# Remove-TeamViewerOutdatedDevice

Removes TeamViewer devices that didn't appear online for a given time.

The script fetches a list of TeamViewer devices of the TeamViewer company
that corresponds to a given API token. The list will be filtered by
devices being offline for a certain amount of time. These devices will
be removed.
The expiration can either be specified by a specific date or by interval.

## Prerequisites

This script requires the `TeamViewerPS` powershell module to be installed.

```powershell
Install-Module TeamViewerPS
```

## Examples

### List removal candidate devices that have been offline since at least 2018-12-18 00:00:00

```powershell
.\Remove-TeamViewerOutdatedDevice -ExpiryDate 2018-12-18 -WhatIf
```

### List removal candidate devices that have been offline since at least 2018-12-17 17:00:00

```powershell
.\Remove-TeamViewerOutdatedDevice -ExpiryDate '2018-12-17T17:00:00' -WhatIf
```

### List removal candidate devices that have been offline since at least 10 days

```powershell
.\Remove-TeamViewerOutdatedDevice -ExpiryInterval -Days 10 -WhatIf
```

### Remove devices that have been offline since at least 30 days. User needs to confirm

```powershell
.\Remove-TeamViewerOutdatedDevice -ExpiryInterval -Days 30
```

### Remove devices that have been offline since at least 12 hours without further confirmation

```powershell
.\Remove-TeamViewerOutdatedDevice -ExpiryInterval -Hours 12 -Force
```

## More help

To get further help about the script and its parameters, execute the
`Get-Help` PowerShell cmdlet:

```powershell
Get-Help -Detailed .\Remove-TeamViewerOutdatedDevice.ps1
```
