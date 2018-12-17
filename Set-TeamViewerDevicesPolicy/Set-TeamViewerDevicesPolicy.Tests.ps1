# Copyright (c) 2019 TeamViewer GmbH
# See file LICENSE.txt

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut" -ApiToken "test" -InformationAction SilentlyContinue

Describe 'Set-TeamViewerDevicesPolicy' {

    Mock Get-TeamViewerDevice { @{
            devices = @(
                [pscustomobject]@{ device_id = 'device1'; group_id = 'group1'; assigned_to = 'true' },
                [pscustomobject]@{ device_id = 'device2'; group_id = 'group2'; assigned_to = 'true' },
                [pscustomobject]@{ device_id = 'device3'; group_id = 'group3'; assigned_to = 'true' })
        }}

    Mock Get-TeamViewerDevice -ParameterFilter { $groupId -eq 'group1' } { @{
            devices = @([pscustomobject]@{ device_id = 'device1'; group_id = 'group1'; assigned_to = 'true' })
        }}

    Mock Get-TeamViewerDevice -ParameterFilter { $groupId -eq 'group2' } { @{
            devices = @([pscustomobject]@{ device_id = 'device2'; group_id = 'group2'; assigned_to = 'true' })
        }}

    Mock Get-TeamViewerDevice -ParameterFilter { $groupId -eq 'group3' } { @{
            devices = @([pscustomobject]@{ device_id = 'device3'; group_id = 'group3'; assigned_to = 'true' })
        }}

    Mock Get-TeamViewerDevice -ParameterFilter { $groupId -eq 'group4' } { @{
            devices = @(
                [pscustomobject]@{ device_id = 'device4'; group_id = 'group4'; assigned_to = 'false' }
                [pscustomobject]@{ device_id = 'device4a'; group_id = 'group4'; assigned_to = 'true' })
        }}

    Mock Get-TeamViewerGroup -ParameterFilter { $name -eq 'GroupName' } { @{
            groups = @(
                [pscustomobject]@{ id = 'group1'; name = 'GroupName1' },
                [pscustomobject]@{ id = 'group2'; name = 'GroupName2' }
                [pscustomobject]@{ id = 'group3'; name = 'GroupName3' })
        }}

    Mock Get-TeamViewerGroup -ParameterFilter { $name -eq 'GroupName1' } { @{
            groups = @([pscustomobject]@{ id = 'group1'; name = 'GroupName1' })
        }}

    Mock Get-TeamViewerGroup -ParameterFilter { $name -eq 'GroupName2' } { @{
            groups = @([pscustomobject]@{ id = 'group2'; name = 'GroupName2' })
        }}

    Mock Get-TeamViewerGroup -ParameterFilter { $name -eq 'GroupName3' } { @{
            groups = @([pscustomobject]@{ id = 'group3'; name = 'GroupName3' })
        }}

    Mock Edit-TeamViewerDevicePolicy {}

    It 'Should set policy for all devices' {
        $result = (Set-TeamViewerDevicesPolicy 'TestToken' 'inherit')
        $result | Should -HaveCount 3
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It
        Assert-MockCalled Get-TeamViewerGroup -Times 0 -Scope It
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 3 -Scope It
    }

    It 'Should set policy for devices in groups if group-name filter given' {
        $result = (Set-TeamViewerDevicesPolicy 'TestToken' 'inherit' -groupNames 'GroupName1', 'GroupName2')
        $result | Should -HaveCount 2
        Assert-MockCalled Get-TeamViewerGroup -Times 2 -Scope It
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $groupId -eq 'group1' }
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $groupId -eq 'group2' }
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 1 -Scope It `
            -ParameterFilter { $deviceId -eq 'device1' }
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 1 -Scope It `
            -ParameterFilter { $deviceId -eq 'device2' }
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 0 -Scope It `
            -ParameterFilter { $deviceId -eq 'device3' }
    }

    It 'Should set policy for devices in groups if group-id filter given' {
        $result = (Set-TeamViewerDevicesPolicy 'TestToken' 'inherit' -groupIds 'group1', 'group2')
        $result | Should -HaveCount 2
        Assert-MockCalled Get-TeamViewerGroup -Times 0 -Scope It
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $groupId -eq 'group1' }
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $groupId -eq 'group2' }
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 1 -Scope It `
            -ParameterFilter { $deviceId -eq 'device1' }
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 1 -Scope It `
            -ParameterFilter { $deviceId -eq 'device2' }
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 0 -Scope It `
            -ParameterFilter { $deviceId -eq 'device3' }
    }

    It 'Should use the exact group name for filtering' {
        $result = (Set-TeamViewerDevicesPolicy 'TestToken' 'inherit' -groupNames 'GroupName')
        $result | Should -HaveCount 0
        Assert-MockCalled Get-TeamViewerGroup -Times 1 -Scope It
        Assert-MockCalled Get-TeamViewerDevice -Times 0 -Scope It
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 0 -Scope It
    }

    It 'Should set the device policy to the given policy ID' {
        $result = (Set-TeamViewerDevicesPolicy 'TestToken' 'policy123')
        $result | Should -HaveCount 3
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 3 -Scope It `
            -ParameterFilter { $policyId -eq 'policy123' }
    }

    It 'Should not set the policy for excluded devices' {
        $result = (Set-TeamViewerDevicesPolicy 'TestToken' 'inherit' -excludedDeviceIds @('device1'))
        $result | Should -HaveCount 2
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 0 -Scope It `
            -ParameterFilter { $deviceId -eq 'device1' }
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 1 -Scope It `
            -ParameterFilter { $deviceId -eq 'device2' }
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 1 -Scope It `
            -ParameterFilter { $deviceId -eq 'device3' }
    }

    It 'Should not set the policy for devices that are not assigned to the user' {
        $result = (Set-TeamViewerDevicesPolicy 'TestToken' 'inherit' -groupIds 'group4')
        $result | Should -HaveCount 1
        Assert-MockCalled Get-TeamViewerGroup -Times 0 -Scope It
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $groupId -eq 'group4' }
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 0 -Scope It `
            -ParameterFilter { $deviceId -eq 'device4' }
        Assert-MockCalled Edit-TeamViewerDevicePolicy -Times 1 -Scope It `
            -ParameterFilter { $deviceId -eq 'device4a' }
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

Describe 'Get-TeamViewerGroup' {
    Mock Invoke-WebRequest { @{Content = '{}'} }

    It 'Should call the "groups" TeamViewer Web API endpoint' {
        Get-TeamViewerGroup 'TestToken'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/groups' -And
            $Method -And $Method -eq 'Get' -And -Not $Body
        }
    }

    It 'Should filter by group name if specified' {
        Get-TeamViewerGroup 'TestToken' 'group1'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/groups' -And
            $Method -And $Method -eq 'Get' -And
            $Body -And $Body.name -eq 'group1'
        }
    }

    It 'Should set the authorization header' {
        Get-TeamViewerGroup 'TestToken'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And `
                $Headers.authorization -eq 'Bearer TestToken'
        }
    }
}

Describe 'Get-TeamViewerDevice' {
    Mock Invoke-WebRequest { @{Content = '{}'} }

    It 'Should call the "devices" TeamViewer Web API endpoint' {
        Get-TeamViewerDevice 'TestToken'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/devices' -And
            $Method -And $Method -eq 'Get' -And
            -Not $Body
        }
    }

    It 'Should filter by group ID if specified' {
        Get-TeamViewerDevice 'TestToken' 'group1'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/devices' -And
            $Method -And $Method -eq 'Get' -And
            $Body -And $Body.groupid -eq 'group1'
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

Describe 'Edit-TeamViewerDevicePolicy' {
    Mock Invoke-WebRequest { @{Content = '{}'} }

    It 'Should call the "devices" TeamViewer Web API endpoint' {
        Edit-TeamViewerDevicePolicy 'TestToken' 'dev123' 'inherit'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/devices/dev123' -And
            $Method -And $Method -eq 'Put'
        }
    }

    It 'Should set the authorization header' {
        Edit-TeamViewerDevicePolicy 'TestToken' 'dev123' 'inherit'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And `
                $Headers.authorization -eq 'Bearer TestToken'
        }
    }

    It 'Should set the JSON content type' {
        Edit-TeamViewerDevicePolicy 'TestToken' 'dev123' 'inherit'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $ContentType -match 'application/json'
        }
    }

    It 'Should send the policy ID in a JSON-formatted object' {
        $expectedBody = [System.Text.Encoding]::UTF8.GetBytes(
            (@{policy_id = 'inherit'} | ConvertTo-Json))
        Edit-TeamViewerDevicePolicy 'TestToken' 'dev123' 'inherit'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Body -And (Compare-Object $Body $expectedBody).Length -eq 0
        }
    }
}
