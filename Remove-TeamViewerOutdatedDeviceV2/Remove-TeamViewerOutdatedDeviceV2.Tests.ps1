# Copyright (c) 2019-2023 TeamViewer Germany GmbH
# See file LICENSE

BeforeAll {
    $testApiToken = [securestring]@{}

    . "$PSScriptRoot\Remove-TeamViewerOutdatedDeviceV2.ps1" -ApiToken $testApiToken -ExpiryDate (Get-Date) -InformationAction SilentlyContinue

    Mock Get-TeamViewerManagedDevice { @(
            [pscustomobject]@{ Id = 'device1'; Name = 'device1'; LastSeenAt = [datetime]'2018-12-16' },
            [pscustomobject]@{ Id = 'device2'; Name = 'device2'; LastSeenAt = [datetime]'2018-12-17' },
            [pscustomobject]@{ Id = 'device3'; Name = 'device3'; LastSeenAt = [datetime]'2018-12-18' },
            [pscustomobject]@{ Id = 'device4'; Name = 'device4'; LastSeenAt = [datetime]'2018-12-19' }
        ) }

    Mock Remove-TeamViewerManagedDeviceManagement -RemoveParameterValidation 'Device' {}
}

Describe 'Remove-TeamViewerOutdatedDeviceV2' {

    It 'Should list devices that are offline since the expiration date' {
        $result = (Remove-TeamViewerOutdatedDeviceV2 ([DateTime]'2018-12-18') -force:$false -WhatIf)
        $result | Should -HaveCount 3
        $result[0].DeviceId | Should -Be 'device1'
        $result[0].Status | Should -Be 'Unchanged'
        $result[1].DeviceId | Should -Be 'device2'
        $result[1].Status | Should -Be 'Unchanged'
        $result[2].DeviceId | Should -Be 'device3'
        $result[2].Status | Should -Be 'Unchanged'

        Assert-MockCalled Get-TeamViewerManagedDevice -Times 1 -Scope It
        Assert-MockCalled Remove-TeamViewerManagedDeviceManagement -Times 0 -Scope It
    }

    It 'Should remove devices that are offline since the expiration date' {
        $result = (Remove-TeamViewerOutdatedDeviceV2 ([DateTime]'2018-12-18') -force:$true)
        $result | Should -HaveCount 3
        $result[0].DeviceId | Should -Be 'device1'
        $result[0].Status | Should -Be 'Removed'
        $result[1].DeviceId | Should -Be 'device2'
        $result[1].Status | Should -Be 'Removed'
        $result[2].DeviceId | Should -Be 'device3'
        $result[2].Status | Should -Be 'Removed'

        Assert-MockCalled Get-TeamViewerManagedDevice -Times 1 -Scope It
        Assert-MockCalled Remove-TeamViewerManagedDeviceManagement -Times 3 -Scope It
    }
}
