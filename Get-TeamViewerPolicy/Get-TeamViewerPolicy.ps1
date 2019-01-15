<#
 .SYNOPSIS
    Get a list of TeamViewer policies.

 .DESCRIPTION
    The script fetches TeamViewer policies for the account that corresponds
    to the given API token.
    It outputs the policy ID and name.
    Use this script in conjunction with the `Set-TeamViewerDevicesPolicy`
    example script to set the policy of certain devices.

 .PARAMETER ApiToken
    The TeamViewer API token to use.
    The token requires the following access permissions:
        - `View TeamViewer policies`

 .EXAMPLE
    .\Get-TeamViewerPolicy.ps1

 .NOTES
    Copyright (c) 2019 TeamViewer GmbH
    See file LICENSE.txt
    Version 1.0.0
#>

param(
    [Parameter(Mandatory = $true)]
    [string] $ApiToken
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

function Get-TeamViewerPolicy($accessToken) {
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/teamviewerpolicies" `
        -Method Get -Headers @{authorization = "Bearer $accessToken"} | `
        Select-Object -ExpandProperty 'policies' |
        Select-Object -Property 'name','policy_id'
}

if ($MyInvocation.InvocationName -ne '.') {
    Get-TeamViewerPolicy $ApiToken
}
