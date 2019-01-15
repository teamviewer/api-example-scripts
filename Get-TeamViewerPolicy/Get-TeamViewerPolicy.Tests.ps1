# Copyright (c) 2019 TeamViewer GmbH
# See file LICENSE.txt

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut" -ApiToken "test" -InformationAction SilentlyContinue

Describe 'Get-TeamViewerPolicy' {
    Mock Invoke-WebRequest { @{Content = '{"policies": [
        {"policy_id": "foo", "name": "bar", "settings": {}},
        {"policy_id": "hello", "name": "world", "settings": {}}
    ]}'} }

    It 'Should call the "teamviewerpolicies" Web API endpoint' {
        Get-TeamViewerPolicy 'TestToken'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/teamviewerpolicies' -And
            $Method -And $Method -eq 'Get' -And -Not $Body
        }
    }

    It 'Should set the authorization header' {
        Get-TeamViewerPolicy 'TestToken'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And `
                $Headers.authorization -eq 'Bearer TestToken'
        }
    }

    It 'Should filter-out policy ID and name' {
        $result = (Get-TeamViewerPolicy 'TestToken')
        $result | Should -HaveCount 2
        $result[0].PSObject.Properties | Should -HaveCount 2
        $result[0].policy_id | Should -Be "foo"
        $result[0].name | Should -Be "bar"
        $result[1].PSObject.Properties | Should -HaveCount 2
        $result[1].policy_id | Should -Be "hello"
        $result[1].name | Should -Be "world"
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
