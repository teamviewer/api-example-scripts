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
    .\Import-TeamViewerUser -ApiToken 'SecretToken123' -Path 'example.csv' -Delimiter ';'

 .EXAMPLE
    $pwd = ConvertTo-SecureString 'MyPassword123' -AsPlainText -Force
    .\Import-TeamViewerUser 'example.csv' -DefaultUserPassword $pwd

 .EXAMPLE
    $users = @(
        @{email = 'user1@example.test'; name = 'Test User 1'},
        @{email = 'user2@example.test'; name = 'Test User 2'; password = 'AnotherPassword123'},
        @{email = 'user3@example.test'; name = 'Test User 3'}
    )
    $pwd = ConvertTo-SecureString 'MyPassword123' -AsPlainText -Force
    $users | .\Import-TeamViewerUser -DefaultUserPassword $pwd

 .EXAMPLE
    .\Import-TeamViewerUser 'example.csv' -WhatIf

 .NOTES
    Copyright (c) 2019 TeamViewer GmbH
    See file LICENSE.txt
    Version 1.0.0
#>

[CmdletBinding(DefaultParameterSetName = 'File', SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $ApiToken,

    [Parameter(ParameterSetName = 'File', Mandatory = $true, Position = 0)]
    [string] $Path,

    [Parameter(ParameterSetName = 'Pipeline', ValueFromPipeline = $true)]
    [object[]] $Users,

    [Parameter(ParameterSetName = 'File', Mandatory = $false)]
    [char] $Delimiter = ',',

    [Parameter(Mandatory = $false)]
    [ValidateSet(
        'bg', 'cs', 'da', 'de', 'el', 'en', 'es', 'fi', 'fr', 'hr', 'hu', 'id', 'it',
        'ja', 'ko', 'lt', 'nl', 'no', 'pl', 'pt', 'ro', 'ru', 'sk', 'sr', 'sv', 'th',
        'tr', 'uk', 'vi', 'zh_CN', 'zh_TW')]
    [string] $DefaultUserLanguage = 'en',

    [Parameter(Mandatory = $false)]
    [System.Security.SecureString] $DefaultUserPassword,

    [Parameter(Mandatory = $false)]
    [string[]] $DefaultUserPermissions = @('ShareOwnGroups', 'EditConnections', 'EditFullProfile', 'ViewOwnConnections'),

    [Parameter(Mandatory = $false)]
    [string] $DefaultSsoCustomerId
)

if (-Not $MyInvocation.BoundParameters.ContainsKey('ErrorAction')) { $script:ErrorActionPreference = 'Stop' }
if (-Not $MyInvocation.BoundParameters.ContainsKey('InformationAction')) { $script:InformationPreference = 'Continue' }

$tvApiVersion = 'v1'
$tvApiBaseUrl = 'https://webapi.teamviewer.com'

function ConvertTo-TeamViewerRestError {
    param([parameter(ValueFromPipeline)]$err)
    try { return ($err | Out-String | ConvertFrom-Json) }
    catch { return $err }
}

function Invoke-TeamViewerRestMethod {
    # Using `Invoke-WebRequest` instead of `Invoke-RestMethod`:
    # There is a known issue for PUT and DELETE operations to hang on Windows Server 2012.
    try { return ((Invoke-WebRequest -UseBasicParsing @args).Content | ConvertFrom-Json) }
    catch [System.Net.WebException] {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $reader.BaseStream.Position = 0
        Throw ($reader.ReadToEnd() | ConvertTo-TeamViewerRestError)
    }
}

function Invoke-TeamViewerPing($accessToken) {
    $result = Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/ping" -Method Get -Headers @{authorization = "Bearer $accessToken" }
    return $result.token_valid
}

function Get-TeamViewerUser($accessToken, $email) {
    $result = Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users" -Method Get -Headers @{authorization = "Bearer $accessToken" } `
        -Body @{full_list = $true; email = $email }
    return $result.users | Select-Object -First 1
}

function Add-TeamViewerUser {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param($accessToken, $user)
    $missingFields = (@('name', 'email', 'language') | Where-Object { !$user[$_] })
    if ($missingFields.Count -gt 0) {
        Throw "Cannot create user! Missing required fields [$missingFields]!"
    }
    $payload = @{ }
    @('email', 'password', 'permissions', 'name', 'language', 'sso_customer_id') | Where-Object { $user[$_] } | ForEach-Object { $payload[$_] = $user[$_] }
    if ($PSCmdlet.ShouldProcess($user.email)) {
        return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users" -Method Post -Headers @{authorization = "Bearer $accessToken" } `
            -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
    }
}

function Edit-TeamViewerUser {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param($accessToken, $userId, $user)
    $payload = @{ }
    @('email', 'name', 'permissions', 'password', 'active') | Where-Object { $user[$_] } | ForEach-Object { $payload[$_] = $user[$_] }
    if ($PSCmdlet.ShouldProcess($user.email)) {
        return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users/$userId" -Method Put -Headers @{authorization = "Bearer $accessToken" } `
            -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
    }
}

function Import-TeamViewerUser {
    param($apiToken)
    Begin {
        Write-Information "Checking connection to TeamViewer API."
        if (!(Invoke-TeamViewerPing $apiToken)) {
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
            $existingUser = (Get-TeamViewerUser -accessToken $apiToken -email $user.email)
            if ($existingUser) {
                # Update the existing user.
                Write-Information "User with email '$($user.email)' found. Updating user."
                Edit-TeamViewerUser -accessToken $apiToken -userId $existingUser.id -user $user | Out-Null
                $statistics.Updated++
            }
            else {
                # Create a new user
                Write-Information "No user with email '$($user.email)' found. Creating user."
                if (!$user.password -and $DefaultUserPassword) {
                    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DefaultUserPassword)
                    $user.password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
                }
                if (!$user.permissions -and $DefaultUserPermissions) {
                    $user.permissions = $DefaultUserPermissions -join ','
                }
                if (!($user.language) -and $DefaultUserLanguage) {
                    $user.language = $DefaultUserLanguage
                }
                if (!$user.sso_customer_id -and $DefaultSsoCustomerId) {
                    $user.sso_customer_id = $DefaultSsoCustomerId
                }
                Add-TeamViewerUser -accessToken $apiToken -user $user | Out-Null
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
    $Users = if ($Path) { Get-Content $Path | ConvertFrom-Csv -Delimiter $Delimiter } else { $Users }
    $Users | Import-TeamViewerUser $ApiToken
}
