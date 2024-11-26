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

        $result_names = $result | ForEach-Object { $_.TeamViewerId }
        $result_names | Should -Contain 'older device A'
        $result_names | Should -Contain 'newer device A'
        $result_names | Should -Contain 'older device B'

        $result_statuses = $result | ForEach-Object { $_.Status }
        $result_statuses[0] | Should -Be 'Unchanged'
        $result_statuses[1] | Should -Be 'Unchanged'
        $result_statuses[2] | Should -Be 'Unchanged'

        Assert-MockCalled Get-TeamViewerCompanyManagedDevice -Times 1 -Exactly -Scope It
        Assert-MockCalled Remove-TeamViewerManagedDeviceManagement -Times 0 -Exactly -Scope It
    }

    It 'Should remove duplicate devices with an older last-seen timestamp' {
        $result = (Remove-TeamViewerDuplicateDevicesV2 -force:$true)
        $result | Should -HaveCount 3

        $result_names = $result | ForEach-Object { $_.TeamViewerId }
        $result_names | Should -Contain 'older device A'
        $result_names | Should -Contain 'newer device A'
        $result_names | Should -Contain 'older device B'

        $result_statuses = $result | ForEach-Object { $_.Status }
        $result_statuses[0] | Should -Be 'Removed'
        $result_statuses[1] | Should -Be 'Removed'
        $result_statuses[2] | Should -Be 'Removed'

        Assert-MockCalled Get-TeamViewerCompanyManagedDevice -Times 1 -Exactly -Scope It
        Assert-MockCalled Remove-TeamViewerManagedDeviceManagement -Times 3 -Exactly -Scope It
    }
}
