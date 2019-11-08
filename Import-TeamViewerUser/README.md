# Import-TeamViewerUser

Imports a set of users to a TeamViewer company.

The script imports and updates a set of users to the TeamViewer company
that corresponds to a given API token. By default, the users will be loaded from
a given CSV-formatted file. There is also an option to pipeline userdata to this
script. In contrast to the definition of the "Import-" verb for Powershell, this
script does *NOT* import the users from TeamViewer to Powershell but performs
the reverse operation, by creating/updating TeamViewer users.

## Examples

### Import users from a CSV file

```powershell
.\Import-TeamViewerUser 'example.csv'
```

### Import users from a CSV file that uses semi-colon as delimiter. Use the given API token

```powershell
.\Import-TeamViewerUser -ApiToken 'SecretToken123' -Path 'example.csv' -Delimiter ';'
```

### Import users from a CSV file and use the given fallback password (if not specified in the CSV data)

```powershell
$pwd = ConvertTo-SecureString 'MyPassword123' -AsPlainText -Force
.\Import-TeamViewerUser 'example.csv' -DefaultUserPassword $pwd
```

### Import users from Powershell data. Use the given default password as fallback.

```powershell
$users = @(
    @{email = 'user1@example.test'; name = 'Test User 1'},
    @{email = 'user2@example.test'; name = 'Test User 2'; password = 'AnotherPassword123'},
    @{email = 'user3@example.test'; name = 'Test User 3'}
)
$pwd = ConvertTo-SecureString 'MyPassword123' -AsPlainText -Force
$users | .\Import-TeamViewerUser -DefaultUserPassword $pwd
```

### Run the import script in "Test Mode" to see the changes that would be made.

```powershell
.\Import-TeamViewerUser 'example.csv' -WhatIf
```

## More help

To get further help about the script and its parameters, execute the
`Get-Help` PowerShell cmdlet:

```powershell
Get-Help -Detailed .\Import-TeamViewerUser.ps1
```
