# Copyright (c) 2019-2024 TeamViewer Germany GmbH
# See file LICENSE

BeforeAll {
    $testApiToken = [securestring]@{}

    . "$PSScriptRoot\Remove-TeamViewerDuplicateDevicesV2.ps1" -ApiToken $testApiToken -InformationAction SilentlyContinue

    Mock Get-TeamViewerCompanyManagedDevice { @(
            [pscustomobject]@{ TeamViewerId = '123456789'; Name = 'unique device'; LastSeenAt = [datetime]'2024-12-16' },
            [pscustomobject]@{ TeamViewerId = 'older device A'; Name = 'duplicate device A'; LastSeenAt = [datetime]'2024-12-17' },
            [pscustomobject]@{ TeamViewerId = 'online device A'; Name = 'duplicate device A'; IsOnline = $True },
            [pscustomobject]@{ TeamViewerId = 'newer device B'; Name = 'duplicate device B'; LastSeenAt = [datetime]'2024-12-18' },
            [pscustomobject]@{ TeamViewerId = 'newer device A'; Name = 'duplicate device A'; LastSeenAt = [datetime]'2024-12-19' },
            [pscustomobject]@{ TeamViewerId = 'older device B'; Name = 'duplicate device B'; LastSeenAt = [datetime]'2024-12-17' }
        ) }

    Mock Remove-TeamViewerManagedDeviceManagement -RemoveParameterValidation 'Device' {}
}

Describe 'Remove-TeamViewerDuplicateDevicesV2' {

    It 'Should not remove any devices if -WhatIf parameter has been set' {
        $result = (Remove-TeamViewerDuplicateDevicesV2 -force:$false -WhatIf)
        $result | Should -HaveCount 3
        $result[0].TeamViewerId | Should -Be 'older device A'
        $result[0].Status | Should -Be 'Unchanged'
        $result[1].TeamViewerId | Should -Be 'newer device A'
        $result[1].Status | Should -Be 'Unchanged'
        $result[2].TeamViewerId | Should -Be 'older device B'
        $result[2].Status | Should -Be 'Unchanged'

        Assert-MockCalled Get-TeamViewerCompanyManagedDevice -Times 1 -Scope It
        Assert-MockCalled Remove-TeamViewerManagedDeviceManagement -Times 0 -Scope It
    }

    It 'Should remove duplicate devices with an older last-seen timestamp' {
        $result = (Remove-TeamViewerDuplicateDevicesV2 -force:$true)
        $result | Should -HaveCount 3
        $result[0].TeamViewerId | Should -Be 'older device A'
        $result[0].Status | Should -Be 'Removed'
        $result[1].TeamViewerId | Should -Be 'newer device A'
        $result[1].Status | Should -Be 'Removed'
        $result[2].TeamViewerId | Should -Be 'older device B'
        $result[2].Status | Should -Be 'Removed'

        Assert-MockCalled Get-TeamViewerCompanyManagedDevice -Times 1 -Scope It
        Assert-MockCalled Remove-TeamViewerManagedDeviceManagement -Times 3 -Scope It
    }
}
