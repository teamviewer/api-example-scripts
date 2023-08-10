# Add-SsoExclusionsFromCSV

Adds users from a CSV file to the TeamViewer SSO exclusion list of their respective domain.

## Prerequisites

This script requires the `TeamViewerPS` powershell module to be installed.

```powershell
Install-Module TeamViewerPS
```

## Examples

### Import users from a CSV file

```powershell
.\Add-SsoExclusionsFromCSV -Path 'c:\Example.csv' -HeaderName 'Email'
```

### Import users from a CSV file and use the given API token

```powershell
$apiToken = 'SecretToken123' | ConvertTo-SecureString -AsPlainText -Force
.\Add-SsoExclusionsFromCSV -Path 'c:\Example.csv' -HeaderName 'Email'
```

### Run the import script in "Test Mode" to see the changes that would be made

```powershell
.\Add-SsoExclusionsFromCSV -Path 'c:\Example.csv' -HeaderName 'Email' -WhatIf
```

## More help

To get further help about the script and its parameters, execute the
`Get-Help` PowerShell cmdlet:

```powershell
Get-Help -Detailed .\Add-SsoExclusionsFromCSV.ps1
```
