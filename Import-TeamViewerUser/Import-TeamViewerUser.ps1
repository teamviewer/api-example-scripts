<#
 .SYNOPSIS
    Imports a set of users to a TeamViewer company.

 .DESCRIPTION
    The script imports and updates a set of users to the TeamViewer company that
    corresponds to a given API token. By default, the users will be loaded from
    a given CSV-formatted file. There is also an option to pipeline userdata to
    this script.
    In contrast to the definition of the "Import-" verb for Powershell, this
    script does *NOT* import the users from TeamViewer to Powershell but
    performs the reverse operation, by creating/updating TeamViewer users.

 .PARAMETER ApiToken
    The TeamViewer API token to use.
    Must be a user access token.
    The token requires the following access permissions:
        - `User management: Create users, view users, edit users`

 .PARAMETER Path
    Path to the CSV-formatted file to load the user data from.
    The file is expected to have a header-line, indicating column names.

 .PARAMETER Users
    Can be used to pipe userdata directly from the Powershell to this script.
    Cannot be used in combination with the `Path` CSV option.

 .PARAMETER Delimiter
    The optional delimiter that is used when loading CSV data from the given
    file path. Only works in combination with the `Path` option.

 .PARAMETER DefaultUserLanguage
    The fallback language code used for creating new users. This will be used
    for the welcome email. This value is only considered if not given in the CSV
    or pipeline user data.

 .PARAMETER DefaultUserPassword
    The fallback user password used for creating new users. This value is only
    considered if not given in the CSV or pipeline user data.

 .PARAMETER DefaultUserPermissions
    The fallback user permissions used for creating new users. This value is
    only considered if not given in the CSV or pipeline user data.
    Must be a comma-separated list of user permissions.
    See the "TeamViewer API Documentation" for valid inputs.

 .PARAMETER DefaultSsoCustomerId
    The fallback SSO customer ID, used for creating new users that are already
    enabled and activated for SSO logins. This value is only considered if not
    given in the CSV or pipeline user data.

 .EXAMPLE
    .\Import-TeamViewerUser 'example.csv'

 .EXAMPLE
    .\Import-TeamViewerUser -Path 'example.csv' -Delimiter ';'

 .EXAMPLE
    $pwd = Read-Host -Prompt 'Enter default password' -AsSecureString
    .\Import-TeamViewerUser 'example.csv' -DefaultUserPassword $pwd

 .EXAMPLE
    $users = @(
        @{email = 'user1@example.test'; name = 'Test User 1'},
        @{email = 'user2@example.test'; name = 'Test User 2'; password = 'AnotherPassword123'},
        @{email = 'user3@example.test'; name = 'Test User 3'}
    )
    $pwd = Read-Host -Prompt 'Enter default password' -AsSecureString
    $users | .\Import-TeamViewerUser -DefaultUserPassword $pwd

 .EXAMPLE
    .\Import-TeamViewerUser 'example.csv' -WhatIf

 .NOTES
    This script requires the TeamViewerPS module to be installed.
    This can be done using the following command:

    ```
    Install-Module TeamViewerPS
    ```

    Copyright (c) 2019-2021 TeamViewer GmbH
    See file LICENSE.txt
    Version 2.0
#>

[CmdletBinding(DefaultParameterSetName = 'File', SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [securestring] $ApiToken,

    [Parameter(ParameterSetName = 'File', Mandatory = $true, Position = 0)]
    [string] $Path,

    [Parameter(ParameterSetName = 'Pipeline', ValueFromPipeline = $true)]
    [object[]] $Users,

    [Parameter(ParameterSetName = 'File', Mandatory = $false)]
    [char] $Delimiter = ',',

    [Parameter(Mandatory = $false)]
    [cultureinfo] $DefaultUserLanguage = 'en',

    [Parameter(Mandatory = $false)]
    [securestring] $DefaultUserPassword,

    [Parameter(Mandatory = $false)]
    [string[]] $DefaultUserPermissions = @('ShareOwnGroups', 'EditConnections', 'EditFullProfile', 'ViewOwnConnections'),

    [Parameter(Mandatory = $false)]
    [securestring] $DefaultSsoCustomerId
)

if (-Not $MyInvocation.BoundParameters.ContainsKey('ErrorAction')) { $script:ErrorActionPreference = 'Stop' }
if (-Not $MyInvocation.BoundParameters.ContainsKey('InformationAction')) { $script:InformationPreference = 'Continue' }

function Install-TeamViewerModule { if (!(Get-Module TeamViewerPS)) { Install-Module TeamViewerPS } }

function Import-TeamViewerUser {
    Begin {
        Write-Information "Checking connection to TeamViewer API."
        if (!(Invoke-TeamViewerPing $ApiToken)) {
            Write-Error "Failed to contact TeamViewer API. Token or connection problem."
        }
        $statistics = @{ Created = 0; Updated = 0; Failed = 0; }
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    }
    Process {
        if (!$_) { return }

        # Convert the input object to a hashtable
        $user = $_
        if (!($_ -is [System.Collections.Hashtable]) -and $_ -is [psobject]) {
            $user = @{ }
            $_.psobject.Properties | ForEach-Object { $user."$($_.Name)" = $_.Value } | Out-Null
        }

        try {
            # Check if the user already exists on the TeamViewer-side
            $existingUser = (Get-TeamViewerUser -ApiToken $ApiToken -Email $user.email)
            if ($existingUser) {
                # Update the existing user.
                Write-Information "User with email '$($user.email)' found. Updating user."
                Set-TeamViewerUser -ApiToken $ApiToken -User $existingUser -Property $user | Out-Null
                $statistics.Updated++
            }
            else {
                # Create a new user
                Write-Information "No user with email '$($user.email)' found. Creating user."
                $additionalParameters = @{}

                if ($user.password) {
                    $additionalParameters['Password'] = $user.password | ConvertTo-SecureString -AsPlainText -Force
                }
                elseif ($DefaultUserPassword) {
                    $additionalParameters['Password'] = $DefaultUserPassword
                }
                else {
                    $additionalParameters['WithoutPassword'] = $true
                }

                if ($user.permissions) {
                    $additionalParameters['Permissions'] = $user.permissions -split ','
                }
                elseif ($DefaultUserPermissions) {
                    $additionalParameters['Permissions'] = $DefaultUserPermissions
                }

                if ($user.language) {
                    $additionalParameters['Culture'] = [cultureinfo]$user.language
                }
                elseif ($DefaultUserLanguage) {
                    $additionalParameters['Culture'] = $DefaultUserLanguage
                }

                if ($user.sso_customer_id) {
                    $additionalParameters['SsoCustomerIdentifier'] = $user.sso_customer_id | ConvertTo-SecureString -AsPlainText -Force
                }
                elseif ($DefaultSsoCustomerId) {
                    $additionalParameters['SsoCustomerIdentifier'] = $DefaultSsoCustomerId
                }

                New-TeamViewerUser `
                    -ApiToken $ApiToken `
                    -Name $user.name `
                    -Email $user.email `
                    @additionalParameters | Out-Null
                $statistics.Created++
            }
        }
        catch {
            Write-Information "Failed to process user with email '$($user.email)': $_"
            $statistics.Failed++
        }
    }
    End {
        # Output some statistics
        $stopwatch.Stop()
        $statistics.Duration = $stopwatch.Elapsed
        Write-Output $statistics
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Install-TeamViewerModule
    $Users = if ($Path) { Get-Content $Path | ConvertFrom-Csv -Delimiter $Delimiter } else { $Users }
    $Users | Import-TeamViewerUser
}
