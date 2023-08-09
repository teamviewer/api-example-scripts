# Copyright (c) 2019-2021 TeamViewer GmbH
# See file LICENSE.txt

BeforeAll {
    $testApiToken = [securestring]@{}
    . "$PSScriptRoot\Add-SsoExclusionsFromCSV.ps1" `
        -ApiToken $testApiToken `
        -csvPAth "testPath" `
        -HeaderName "Email" `
        -InformationAction 'SilentlyContinue'

    Mock Invoke-TeamViewerPing { $true }
    Mock Get-TeamViewerSsoDomain { @(
            [PSCustomObject]@{Id = '9602c5f4-2779-4f9a-80e8-4829531789fe'; Name = "example1.org" },
            [PSCustomObject]@{Id = '33ad81bb-e88b-46d0-92e1-b4f1663abf31'; Name = "example2.org" }
        )
    }
    Mock Add-TeamViewerSsoExclusion {}

    Mock Import-Csv { ConvertFrom-Csv -InputObject @'
        "EMail","Name"
        "user1@example1.org","User1"
        "user2@example1.org","User2"
        "user3@example2.org","User3"
        "user4@example2.org","User4" 
        "user5@example2.org","User5"
        "user5@example3.org","User6" 
'@
    }

    function Resolve-TeamViewerSsoDomainId {
        param(
            [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
            [object]
            $Domain
        )
        Process {
            if ($Domain.PSObject.TypeNames -contains 'TeamViewerPS.SsoDomain') {
                return [guid]$Domain.Id
            }
            elseif ($Domain -is [string]) {
                return [guid]$Domain
            }
            elseif ($Domain -is [guid]) {
                return $Domain
            }
            else {
                throw "Invalid SSO domain identifier '$Domain'. Must be either a [TeamViewerPS.SsoDomain], [guid] or [string]."
            }
        }
    }
}

Describe 'Add-SsoExclusionsFromCSV' {

    It 'Should blah' {
        Add-SsoExclusionsFromCSV -csvPath "example.csv" -HeaderName "Email"

        Assert-MockCalled Get-TeamViewerSsoDomain -Times 1 -Scope It
        Assert-MockCalled Add-TeamViewerSsoExclusion -Times 1 -Scope It -ParameterFilter {
            $ApiToken -eq $testApiToken -And `
                $DomainId -eq [guid]'9602c5f4-2779-4f9a-80e8-4829531789fe' -And `
                $Email.Count -eq 2 }
        Assert-MockCalled Add-TeamViewerSsoExclusion -Times 1 -Scope It -ParameterFilter {
            $ApiToken -eq $testApiToken -And `
                $DomainId -eq [guid]'33ad81bb-e88b-46d0-92e1-b4f1663abf31' -And `
                $Email.Count -eq 3 }
    }
}
