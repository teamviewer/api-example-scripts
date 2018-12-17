# Set-TeamViewerDevicesPolicy

Sets the policy for a list of TeamViewer devices.

The script fetches TeamViewer devices from the TeamViewer company that
corresponds to the given API token. It will set the policy of those devices
to either inherit from their parent group or to a policy with the given ID.
An optional group filter restricts the operation to only those devices that
are member of the groups with the given names or IDs.
There is also the option to exclude specific devices by their device ID.

## Examples

### Set the policy of all devices in a company to "inherit"

```
.\Set-TeamViewerDevicesPolicy.ps1
```

### Set the policy of devices in group "Group1" to policy with ID "Pol123"

```
.\Set-TeamViewerDevicesPolicy.ps1 -PolicyId "Pol123" -FilterGroupNames "Group1"
```

## More help

To get further help about the script and its parameters, execute the
`Get-Help` PowerShell cmdlet:

```
Get-Help -Detailed .\Set-TeamViewerDevicesPolicy.ps1
```
