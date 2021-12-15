# Copyright (c) 2019-2021 TeamViewer GmbH
# See file LICENSE.txt

BeforeAll {
    $testApiToken = [securestring]@{}
    . "$PSScriptRoot\Invoke-TeamViewerGroupPerUserSync.ps1" `
        -ApiToken $testApiToken `
        -MappingFilePath "example.csv" `
        -IgnoreSourceGroup `
        -NoLogFile `
        -InformationAction SilentlyContinue

    Mock Invoke-TeamViewerPing { $true }
    Mock Get-TeamViewerUser { @() }
    Mock Get-TeamViewerGroup { @() }
    Mock Get-TeamViewerDevice { @() }
    Mock New-TeamViewerGroup { }
    Mock Set-TeamViewerDevice -RemoveParameterValidation 'Device', 'Group' { }
    Mock Publish-TeamViewerGroup -RemoveParameterValidation 'User', 'Group' { }
}

Describe 'Invoke-TeamViewerGroupPerUserSync' {

    It 'Should check the connection to the TeamViewer API' {
        { Invoke-TeamViewerGroupPerUserSync -sourceGroupName '' -ignoreSourceGroup $true -mappingData @() } | Should -Not -Throw
        Assert-MockCalled Invoke-TeamViewerPing -Times 1 -Scope It
    }

    Context 'TeamViewer API not reachable' {
        BeforeAll {
            Mock Invoke-TeamViewerPing { $false }
        }
        It 'Should abort if TeamViewer API is not reachable' {
            { Invoke-TeamViewerGroupPerUserSync -sourceGroupName '' -ignoreSourceGroup $true -mappingData @() } | Should -Throw
        }
    }

    It 'Should get users, groups and devices' {
        { Invoke-TeamViewerGroupPerUserSync -sourceGroupName '' -ignoreSourceGroup $true -mappingData @() } | Should -Not -Throw
        Assert-MockCalled Get-TeamViewerUser -Times 1 -Scope It
        Assert-MockCalled Get-TeamViewerGroup -Times 1 -Scope It
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It
    }

    It 'Should abort if source group does not exist' {
        { Invoke-TeamViewerGroupPerUserSync -sourceGroupName 'Non-existing group' -ignoreSourceGroup $false -mappingData @() } | Should -Throw
    }

    Context 'Happy Path' {
        BeforeAll {
            Mock Get-TeamViewerUser { @(
                    @{Id = 'TestUser1'; Email = 'user@example.test' }
                ) }
            Mock Get-TeamViewerDevice { @(
                    @{Id = '007'; Name = "TestDevice1"; TeamViewerId = "1234" }
                ) }
            Mock New-TeamViewerGroup { @{
                    Id = 'newgroupid1'; Name = 'Devices of user@example.test'
                } }
        }

        It 'Should create the group, add the device to the group and share the group with the user' {
            $mappingData = @(
                @{email = 'user@example.test'; device = 'TestDevice1' }
            )
            $result = Invoke-TeamViewerGroupPerUserSync  -sourceGroupName '' -ignoreSourceGroup $true -mappingData $mappingData
            $result.Statistics.Failed | Should -Be 0
            $result.Statistics.Unchanged | Should -Be 0
            $result.Statistics.Updated | Should -Be 1

            Assert-MockCalled New-TeamViewerGroup -Times 1 -Scope It -ParameterFilter {
                $Name -Eq 'Devices of user@example.test'
            }
            Assert-MockCalled Set-TeamViewerDevice -Times 1 -Scope It -ParameterFilter {
                $Device -And $Device.Id -Eq "007" -And `
                    $Group -And $Group.Id -Eq 'newgroupid1'
            }
            Assert-MockCalled Publish-TeamViewerGroup -Times 1 -Scope It -ParameterFilter {
                $Group -And $Group.Id -Eq 'newgroupid1' -And `
                    $User -And $User.Id -Eq 'TestUser1' -And `
                    $Permissions -Eq 'readwrite'
            }
        }

        It 'Should do the lookup via TeamViewer ID' {
            $mappingData = @(
                @{email = 'user@example.test'; teamviewerid = '1234' }
            )
            $result = Invoke-TeamViewerGroupPerUserSync -sourceGroupName '' -ignoreSourceGroup $true -mappingData $mappingData
            $result.Statistics.Failed | Should -Be 0
            $result.Statistics.Unchanged | Should -Be 0
            $result.Statistics.Updated | Should -Be 1

            Assert-MockCalled New-TeamViewerGroup -Times 1 -Scope It -ParameterFilter {
                $Name -Eq 'Devices of user@example.test'
            }
            Assert-MockCalled Set-TeamViewerDevice -Times 1 -Scope It -ParameterFilter {
                $Device -And $Device.Id -Eq "007" -And `
                    $Group -And $Group.Id -Eq 'newgroupid1'
            }
            Assert-MockCalled Publish-TeamViewerGroup -Times 1 -Scope It -ParameterFilter {
                $Group -And $Group.Id -Eq 'newgroupid1' -And `
                    $User -And $User.Id -Eq 'TestUser1' -And `
                    $Permissions -Eq 'readwrite'
            }
        }
    }
}
