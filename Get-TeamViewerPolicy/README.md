# Get-TeamViewerPolicy

Get a list of TeamViewer policies.

The script fetches TeamViewer policies for the account that corresponds
to the given API token.
It outputs the policy ID and name.
Use this script in conjunction with the `Set-TeamViewerDevicesPolicy`
example script to set the policy of certain devices.

## Example

```
.\Get-TeamViewerPolicy.ps1
```

## More help

To get further help about the script and its parameters, execute the
`Get-Help` PowerShell cmdlet:

```
Get-Help -Detailed .\Get-TeamViewersPolicy.ps1
```
