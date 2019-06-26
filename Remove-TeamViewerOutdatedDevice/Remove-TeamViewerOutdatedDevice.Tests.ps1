# Copyright (c) 2019 TeamViewer GmbH
# See file LICENSE.txt

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut" -ApiToken "test" -ExpiryDate (Get-Date) -InformationAction 'SilentlyContinue'

Describe '.\Remove-TeamViewerOutdatedDevice' {
    Mock Get-TeamViewerDevice {@{
            devices = @(
                [pscustomobject]@{ device_id = 'device1'; alias = 'device1'; last_seen = '2018-12-16' },
                [pscustomobject]@{ device_id = 'device2'; alias = 'device2'; last_seen = '2018-12-17' },
                [pscustomobject]@{ device_id = 'device3'; alias = 'device3'; last_seen = '2018-12-18' },
                [pscustomobject]@{ device_id = 'device4'; alias = 'device4'; last_seen = '2018-12-19' })
        }}
    Mock Remove-TeamViewerDevice {}

    It 'Should list devices that are offline since the expiration date' {
        $result = (Remove-TeamViewerOutdatedDevice 'TestToken' ([DateTime]'2018-12-18') -force:$false -WhatIf)
        $result | Should -HaveCount 3
        $result[0].DeviceId | Should -Be 'device1'
        $result[0].Status | Should -Be 'Unchanged'
        $result[1].DeviceId | Should -Be 'device2'
        $result[1].Status | Should -Be 'Unchanged'
        $result[2].DeviceId | Should -Be 'device3'
        $result[2].Status | Should -Be 'Unchanged'
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It
        Assert-MockCalled Remove-TeamViewerDevice -Times 0 -Scope It
    }

    It 'Should remove devices that are offline since the expiration date' {
        $result = (Remove-TeamViewerOutdatedDevice 'TestToken' ([DateTime]'2018-12-18') -force:$true)
        $result | Should -HaveCount 3
        $result[0].DeviceId | Should -Be 'device1'
        $result[0].Status | Should -Be 'Removed'
        $result[1].DeviceId | Should -Be 'device2'
        $result[1].Status | Should -Be 'Removed'
        $result[2].DeviceId | Should -Be 'device3'
        $result[2].Status | Should -Be 'Removed'
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It
        Assert-MockCalled Remove-TeamViewerDevice -Times 3 -Scope It
    }
}

Describe 'ConvertTo-TeamViewerRestError' {
    It 'Should convert from JSON' {
        $result = ('{"foo": "bar"}' | ConvertTo-TeamViewerRestError)
        $result.foo | Should -Be 'bar'
    }

    It 'Should return input object for invalid JSON' {
        $result = ('garbage' | ConvertTo-TeamViewerRestError)
        $result | Should -Be 'garbage'
    }
}

Describe 'Invoke-TeamViewerRestMethod' {
    Mock Invoke-WebRequest { @{Content = '{"foo": "bar"}'} }

    It 'Should call Invoke-WebRequest and convert the result from JSON' {
        $result = Invoke-TeamViewerRestMethod -Uri 'http://example.test'
        $result.foo | Should -Be 'bar'
        Assert-MockCalled Invoke-WebRequest `
            -ParameterFilter { $Uri -eq 'http://example.test' }-Times 1 -Scope It
    }
}

Describe 'Get-TeamViewerDevice' {
    Mock Invoke-WebRequest { @{Content = '{}'} }

    It 'Should call the "devices" TeamViewer Web API endpoint' {
        Get-TeamViewerDevice 'TestToken'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/devices' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should set specified "online_state" parameter' {
        Get-TeamViewerDevice 'TestToken' 'offline'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/devices' -And
            $Method -And $Method -eq 'Get' -And
            $Body -And $Body.online_state -eq 'offline'
        }
    }

    It 'Should set the authorization header' {
        Get-TeamViewerDevice 'TestToken'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And `
                $Headers.authorization -eq 'Bearer TestToken'
        }
    }
}

Describe 'Remove-TeamViewerDevice' {
    Mock Invoke-WebRequest { @{Content = '{}'} }

    It 'Should call the "devices" TeamViewer Web API endpoint' {
        Remove-TeamViewerDevice 'TestToken' 'device1'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/devices/device1' -And
            $Method -And $Method -eq 'Delete'
        }
    }

    It 'Should set the authorization header' {
        Remove-TeamViewerDevice 'TestToken' 'device1'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And `
                $Headers.authorization -eq 'Bearer TestToken'
        }
    }
}
