$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut" -ApiToken "testApiToken" -MappingFilePath "testMappingFilePath" -IgnoreSourceGroup -NoLogFile -InformationAction 'SilentlyContinue'

Describe 'Invoke-TeamViewerGroupPerUserSync' {
    Mock Invoke-WebRequest { }
    Mock Invoke-TeamViewerRestMethod { }
    Mock Invoke-TeamViewerPing { $true }
    Mock Get-TeamViewerUser { @() }
    Mock Get-TeamViewerGroup { @() }
    Mock Add-TeamViewerGroup { }
    Mock Add-TeamViewerGroupShare { }
    Mock Get-TeamViewerDevice { @() }
    Mock Edit-TeamViewerDevice { }

    It 'Should check the connection to the TeamViewer API' {
        { Invoke-TeamViewerGroupPerUserSync -apiToken 'TestAccessToken' -sourceGroupName '' -ignoreSourceGroup $true -mappingData @() } | Should -Not -Throw
        Assert-MockCalled Invoke-TeamViewerPing -Times 1 -Scope It
    }

    Context 'TeamViewer API not reachable' {
        Mock Invoke-TeamViewerPing { $false }

        It 'Should abort if TeamViewer API is not reachable' {
            { Invoke-TeamViewerGroupPerUserSync -apiToken 'TestAccessToken' -sourceGroupName '' -ignoreSourceGroup $true -mappingData @() } | Should -Throw
        }
    }

    It 'Should get users, groups and devices' {
        { Invoke-TeamViewerGroupPerUserSync -apiToken 'TestAccessToken' -sourceGroupName '' -ignoreSourceGroup $true -mappingData @() } | Should -Not -Throw
        Assert-MockCalled Get-TeamViewerUser -Times 1 -Scope It
        Assert-MockCalled Get-TeamViewerGroup -Times 1 -Scope It
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It
    }

    It 'Should abort if source group does not exist' {
        { Invoke-TeamViewerGroupPerUserSync -apiToken 'TestAccessToken' -sourceGroupName 'Non-existing group' -ignoreSourceGroup $false -mappingData @() } | Should -Throw
    }

    Context 'Happy Path' {
        Mock Get-TeamViewerUser { @(
                @{id = 'TestUser1'; email = 'user@example.test' }
            ) }
        Mock Get-TeamViewerDevice { @(
                @{device_id = '007'; alias = "TestDevice1"; remotecontrol_id = "r1234" }
            ) }
        Mock Add-TeamViewerGroup { @{
                id = 'newgroupid1'; name = 'Devices of user@example.test'
            } }

        It 'Should create the group, add the device to the group and share the group with the user' {
            $mappingData = @(
                @{email = 'user@example.test'; device = 'TestDevice1' }
            )
            $result = Invoke-TeamViewerGroupPerUserSync -apiToken 'TestAccessToken' -sourceGroupName '' -ignoreSourceGroup $true -mappingData $mappingData
            $result.Statistics.Failed | Should -Be 0
            $result.Statistics.Unchanged | Should -Be 0
            $result.Statistics.Updated | Should -Be 1

            Assert-MockCalled Add-TeamViewerGroup -Times 1 -Scope It -ParameterFilter {
                $group -And $group.name -Eq 'Devices of user@example.test'
            }
            Assert-MockCalled Edit-TeamViewerDevice -Times 1 -Scope It -ParameterFilter {
                $deviceId -Eq '007' -And $device -And $device.groupid -Eq 'newgroupid1'
            }
            Assert-MockCalled Add-TeamViewerGroupShare -Times 1 -Scope It -ParameterFilter {
                $groupId -Eq 'newgroupid1' -And $user -And $user.userid -Eq 'TestUser1' -And $user.permissions -Eq 'full'
            }
        }

        It 'Should do the lookup via TeamViewer ID' {
            $mappingData = @(
                @{email = 'user@example.test'; teamviewerid = '1234' }
            )
            $result = Invoke-TeamViewerGroupPerUserSync -apiToken 'TestAccessToken' -sourceGroupName '' -ignoreSourceGroup $true -mappingData $mappingData
            $result.Statistics.Failed | Should -Be 0
            $result.Statistics.Unchanged | Should -Be 0
            $result.Statistics.Updated | Should -Be 1

            Assert-MockCalled Add-TeamViewerGroup -Times 1 -Scope It -ParameterFilter {
                $group -And $group.name -Eq 'Devices of user@example.test'
            }
            Assert-MockCalled Edit-TeamViewerDevice -Times 1 -Scope It -ParameterFilter {
                $deviceId -Eq '007' -And $device -And $device.groupid -Eq 'newgroupid1'
            }
            Assert-MockCalled Add-TeamViewerGroupShare -Times 1 -Scope It -ParameterFilter {
                $groupId -Eq 'newgroupid1' -And $user -And $user.userid -Eq 'TestUser1' -And $user.permissions -Eq 'full'
            }
        }
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
    Mock Invoke-WebRequest { @{Content = '{"foo": "bar"}' } }

    It 'Should call Invoke-WebRequest and convert the result from JSON' {
        $result = Invoke-TeamViewerRestMethod -Uri 'http://example.test'
        $result.foo | Should -Be 'bar'
        Assert-MockCalled Invoke-WebRequest `
            -ParameterFilter { $Uri -eq 'http://example.test' } -Times 1 -Scope It
    }
}

# Redefine `Invoke-TeamViewerRestMethod` for mocking purposes
function Invoke-TeamViewerRestMethod($Uri, $Method, $Headers, $ContentType, $Body) { }

Describe 'Invoke-TeamViewerPing' {
    It 'Should call the API ping REST endpoint' {
        Mock Invoke-TeamViewerRestMethod { @{token_valid = $true } }
        Invoke-TeamViewerPing 'TestAccessToken' | Should -Be $true
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And ([System.Uri]$Uri).PathAndQuery -eq '/api/v1/ping' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should return false for invalid tokens' {
        Mock Invoke-TeamViewerRestMethod { @{token_valid = $false } }
        Invoke-TeamViewerPing 'TestAccessToken' | Should -Be $false
    }

    It 'Should set the authorization header' {
        Mock Invoke-TeamViewerRestMethod { @{token_valid = $true } }
        Invoke-TeamViewerPing 'TestAccessToken'
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Get-TeamViewerUser' {
    Mock Invoke-TeamViewerRestMethod { @{
            'users' = @(
                @{ email = 'test1@example.test'; name = 'Test User1' }
            )
        } }

    It 'Should call the API users endpoint' {
        Get-TeamViewerUser 'TestAccessToken'
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And ([System.Uri]$Uri).PathAndQuery -eq '/api/v1/users' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should return a single user' {
        $result = (Get-TeamViewerUser 'TestAccessToken')
        $result | Should -HaveCount 1
        $result.email | Should -Be 'test1@example.test'
    }

    It 'Should set the authorization header' {
        Get-TeamViewerUser 'TestAccessToken'
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Get-TeamViewerGroup' {
    Mock Invoke-TeamViewerRestMethod { @{
            'groups' = @(
                @{ id = 'testgroup123'; name = 'Test Group1' },
                @{ id = 'testgroup456'; name = 'Test Group2' }
            )
        } }

    It 'Should call the API groups endpoint' {
        Get-TeamViewerGroup 'TestAccessToken'
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And ([System.Uri]$Uri).PathAndQuery -eq '/api/v1/groups' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should return the group objects' {
        $result = (Get-TeamViewerGroup 'TestAccessToken')
        $result | Should -HaveCount 2
    }

    It 'Should set the authorization header' {
        Get-TeamViewerGroup 'TestAccessToken'
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Add-TeamViewerGroup' {
    $testGroup = @{ 'name' = 'Test Group 1'; 'id' = '007' }
    $lastMockParams = @{ }
    Mock Invoke-TeamViewerRestMethod {
        $lastMockParams.Body = $Body
        return $testGroup
    }

    It 'Should call the API groups endpoint' {
        Add-TeamViewerGroup 'TestAccessToken' @{ 'name' = 'Test Group 1' }
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And ([System.Uri]$Uri).PathAndQuery -eq '/api/v1/groups' -And
            $Method -And $Method -eq 'Post'
        }
    }

    It 'Should throw if required fields are missing' {
        { { Add-TeamViewerGroup'TestAccessToken' @{ } } | Should -Throw }
    }

    It 'Should encode the payload using UTF-8' {
        $input = @{ 'name' = 'Test Group Müller' }
        Add-TeamViewerGroup 'TestAccessToken' $input
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter { $Body }
        { [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) } | Should -Not -Throw
        { [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json } | Should -Not -Throw
        ([System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json).name | Should -Be 'Test Group Müller'
    }

    It 'Should set the authorization header' {
        $input = @{ 'name' = 'Test Group 1' }
        Add-TeamViewerGroup 'TestAccessToken' $input
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Add-TeamViewerGroupShare' {
    Mock Invoke-TeamViewerRestMethod { }

    It 'Should call the API share_group endpoint' {
        Add-TeamViewerGroupShare 'TestAccessToken' 'TestGroupId1' @{ userid = 'TestUser1'; permissions = 'full' }
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And ([System.Uri]$Uri).PathAndQuery -eq '/api/v1/groups/TestGroupId1/share_group' -And
            $Method -And $Method -eq 'Post'
        }
    }

    It 'Should throw if required fields are missing' {
        { { Add-TeamViewerGroupShare'TestAccessToken' 'TestGroupId1' @{ } } | Should -Throw }
    }

    It 'Should set the authorization header' {
        Add-TeamViewerGroupShare 'TestAccessToken' 'TestGroupId1' @{ userid = 'TestUser1'; permissions = 'full' }
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Get-TeamViewerDevice' {
    Mock Invoke-TeamViewerRestMethod { @{
            'devices' = @(
                @{ device_id = 'testdevice1'; alias = 'Test Device1'; groupid = "TestGroup1" },
                @{ device_id = 'testdevice2'; alias = 'Test Device2'; groupid = "TestGroup1" }
            )
        } }

    It 'Should call the API devices endpoint' {
        Get-TeamViewerDevice 'TestAccessToken'
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And ([System.Uri]$Uri).PathAndQuery -eq '/api/v1/devices' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should return the devices list' {
        $result = (Get-TeamViewerDevice 'TestAccessToken')
        $result | Should -HaveCount 2
        $result[0].device_id | Should -Be 'testdevice1'
    }

    It 'Should set the authorization header' {
        Get-TeamViewerDevice 'TestAccessToken'
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Edit-TeamViewerDevice' {
    $lastMockParams = @{ }
    Mock Invoke-TeamViewerRestMethod {
        $lastMockParams.Body = $Body
    }

    It 'Should call the API devices endpoint' {
        Edit-TeamViewerDevice 'TestAccessToken' 'TestDeviceId' @{groupid = 'TestGroup' }
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And ([System.Uri]$Uri).PathAndQuery -eq '/api/v1/devices/TestDeviceId' -And
            $Method -And $Method -eq 'Put'
        }
    }

    It 'Should set the authorization header' {
        Edit-TeamViewerDevice 'TestAccessToken' 'TestDeviceId' @{groupid = 'TestGroup' }
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}
