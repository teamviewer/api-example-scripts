<#
 .SYNOPSIS
    Adds users from provided CSV file to SSO exclusion list of their respective domain

 .DESCRIPTION
    The script fetches a list of SSO domains you have configured, loads the CSV file, 
    will check for email addresses for each of your domains in the CSV and add them to the exclusion list of their repective domain
    emails not matching to any of your domains will be skipped

 .PARAMETER ApiToken
    The TeamViewer API token to use.
    Must be a user access token.
    The token requires the following access permissions:
        - `Manage SSO domains > View details about domains, add and remove email exclusions`

 .PARAMETER CSVPath
    Path of .csv file that contains the emails

 .PARAMETER HeaderName
    Column name where to find emails in imported csv file

 .EXAMPLE
    $apiToken = 'SecretToken123' | ConvertTo-SecureString -AsPlainText -Force
    .\Add-SsoExclusionsFromCSV -csvPath 'c:\ps playground\test.csv' -HeaderName 'Email' -WhatIf

 .NOTES
     This script requires the TeamViewerPS module to be installed.
    This can be done using the following command:

    ```
    Install-Module TeamViewerPS
    ```

    Copyright (c) 2019-2023 TeamViewer GmbH
    See file LICENSE.txt
    Version 2.0
#>

[CmdletBinding(DefaultParameterSetName = "csvPath", SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [securestring] $ApiToken,

    [Parameter(Mandatory = $true)]
    [string] $csvPath,

    [Parameter(Mandatory = $true)]
    [string] $HeaderName
)

if (-Not $MyInvocation.BoundParameters.ContainsKey('ErrorAction')) { $script:ErrorActionPreference = 'Stop' }
if (-Not $MyInvocation.BoundParameters.ContainsKey('InformationAction')) { $script:InformationPreference = 'Continue' }

function Install-TeamViewerModule { if (!(Get-Module TeamViewerPS)) { Install-Module TeamViewerPS } }

function Add-SsoExclusionsFromCSV {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param($csvPath, $HeaderName)

    #import emails fom csv
    $csvRows = Import-Csv -Path $csvPath
	
    if ($csvRows.Count -eq 0) {
        Write-Information "No entries found in CSV file"
        exit
    }
    else {
        Write-Information "Found $($csvRows.Count) rows in CSV file"
    }
	
    $emails = $csvRows | Select-Object -ExpandProperty $HeaderName
	
    if ($emails.Count -eq 0) {
        Write-Information "No valid emails found in CSV file"
        exit
    }
    else {
        Write-Information "Found $($emails.Count) emails in CSV file"
    }
	
    $domains = Get-TeamViewerSsoDomain -ApiToken $apiToken
	
    if ($domains.Count -eq 0) {
        Write-Information "No valid sso domains found"
        exit
    }
	
    foreach ($domain in $domains) {
        $domainUsers = $emails | Where-Object -FilterScript { $_.Split("@")[1] -eq $domain.Name }
        Write-Information "Adding $($domainUsers.Count) email exclusions for $($domain.Name)"
        if ($domainUsers.Count -gt 0 -And -Not $WhatIfPreference) {
            Add-TeamViewerSsoExclusion -ApiToken $apiToken -DomainId $domain.Id -Email $domainUsers
            Write-Information "Completed for domain $($domain.Name)"
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Install-TeamViewerModule
    Add-SsoExclusionsFromCSV -csvPath $csvPath -HeaderName $HeaderName
}
