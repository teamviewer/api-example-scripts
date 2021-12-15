# Copyright (c) 2019-2021 TeamViewer GmbH
# See file LICENSE.txt

BeforeAll {
    $testApiToken = [securestring]@{}
    . "$PSScriptRoot\Set-TeamViewerDevicesPolicy.ps1" `
        -ApiToken $testApiToken `
        -InformationAction SilentlyContinue

    Mock Get-TeamViewerDevice `
        -RemoveParameterValidation 'Group' `
        -ParameterFilter { ($Group -and $Group.Id -eq 'g001') -or ($GroupId -and $GroupId -eq 'g001') } { @(
            [pscustomobject]@{ Id = 'd001'; GroupId = 'g001'; IsAssignedToCurrentAccount = 'true' }
        ) }

    Mock Get-TeamViewerDevice `
        -RemoveParameterValidation 'Group' `
        -ParameterFilter { ($Group -and $Group.Id -eq 'g002') -or ($GroupId -and $GroupId -eq 'g002') } { @(
            [pscustomobject]@{ Id = 'd002'; GroupId = 'g002'; IsAssignedToCurrentAccount = 'true' }
        ) }

    Mock Get-TeamViewerDevice `
        -RemoveParameterValidation 'Group' `
        -ParameterFilter { ($Group -and $Group.Id -eq 'g003') -or ($GroupId -and $GroupId -eq 'g003') } { @(
            [pscustomobject]@{ Id = 'd003'; GroupId = 'g003'; IsAssignedToCurrentAccount = 'true' }
        ) }

    Mock Get-TeamViewerDevice `
        -RemoveParameterValidation 'Group' `
        -ParameterFilter { ($Group -and $Group.Id -eq 'g004') -or ($GroupId -and $GroupId -eq 'g004') } { @(
            [pscustomobject]@{ Id = 'd004'; GroupId = 'g004'; IsAssignedToCurrentAccount = 'false' }
            [pscustomobject]@{ Id = 'd004a'; GroupId = 'g004'; IsAssignedToCurrentAccount = 'true' }
        ) }

    Mock Get-TeamViewerDevice { @(
            [pscustomobject]@{ Id = 'd001'; GroupId = 'g001'; IsAssignedToCurrentAccount = 'true' },
            [pscustomobject]@{ Id = 'd002'; GroupId = 'g002'; IsAssignedToCurrentAccount = 'true' },
            [pscustomobject]@{ Id = 'd003'; GroupId = 'g003'; IsAssignedToCurrentAccount = 'true' }
        ) }

    Mock Get-TeamViewerGroup -ParameterFilter { $Name -eq 'GroupName1' } { @(
            [pscustomobject]@{ Id = 'g001'; Name = 'GroupName1' }
        ) }

    Mock Get-TeamViewerGroup -ParameterFilter { $Name -eq 'GroupName2' } { @(
            [pscustomobject]@{ Id = 'g002'; Name = 'GroupName2' }
        ) }

    Mock Get-TeamViewerGroup -ParameterFilter { $Name -eq 'GroupName3' } { @(
            [pscustomobject]@{ Id = 'g003'; Name = 'GroupName3' }
        ) }

    Mock Get-TeamViewerGroup -ParameterFilter { $Name -eq 'GroupName' } { @(
            [pscustomobject]@{ Id = 'g001'; Name = 'GroupName1' },
            [pscustomobject]@{ Id = 'g002'; Name = 'GroupName2' }
            [pscustomobject]@{ Id = 'g003'; Name = 'GroupName3' }
        ) }

    Mock Set-TeamViewerDevice -RemoveParameterValidation 'Device', 'Policy' {}
}

Describe 'Set-TeamViewerDevicesPolicy' {

    It 'Should set policy for all devices' {
        $result = (Set-TeamViewerDevicesPolicy 'inherit')
        $result | Should -HaveCount 3
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It
        Assert-MockCalled Get-TeamViewerGroup -Times 0 -Scope It
        Assert-MockCalled Set-TeamViewerDevice -Times 3 -Scope It
    }

    It 'Should set policy for devices in groups if group-name filter given' {
        $result = (Set-TeamViewerDevicesPolicy 'inherit' -groupNames 'GroupName1', 'GroupName2')
        $result | Should -HaveCount 2
        Assert-MockCalled Get-TeamViewerGroup -Times 2 -Scope It
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $Group.Id -eq 'g001' }
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $Group.Id -eq 'g002' }
        Assert-MockCalled Set-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd001' }
        Assert-MockCalled Set-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd002' }
        Assert-MockCalled Set-TeamViewerDevice -Times 0 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd003' }
    }

    It 'Should set policy for devices in groups if group-id filter given' {
        $result = (Set-TeamViewerDevicesPolicy 'inherit' -groupIds 'g001', 'g002')
        $result | Should -HaveCount 2
        Assert-MockCalled Get-TeamViewerGroup -Times 0 -Scope It
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $GroupId -eq 'g001' }
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $GroupId -eq 'g002' }
        Assert-MockCalled Set-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd001' }
        Assert-MockCalled Set-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd002' }
        Assert-MockCalled Set-TeamViewerDevice -Times 0 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd003' }
    }

    It 'Should use the exact group name for filtering' {
        $result = (Set-TeamViewerDevicesPolicy 'inherit' -groupNames 'GroupName')
        $result | Should -HaveCount 0
        Assert-MockCalled Get-TeamViewerGroup -Times 1 -Scope It
        Assert-MockCalled Get-TeamViewerDevice -Times 0 -Scope It
        Assert-MockCalled Set-TeamViewerDevice -Times 0 -Scope It
    }

    It 'Should set the device policy to the given policy ID' {
        $result = (Set-TeamViewerDevicesPolicy 'policy123')
        $result | Should -HaveCount 3
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It
        Assert-MockCalled Set-TeamViewerDevice -Times 3 -Scope It `
            -ParameterFilter { $Policy -eq 'policy123' }
    }

    It 'Should not set the policy for excluded devices' {
        $result = (Set-TeamViewerDevicesPolicy 'inherit' -excludedDeviceIds @('d001'))
        $result | Should -HaveCount 2
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It
        Assert-MockCalled Set-TeamViewerDevice -Times 0 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd001' }
        Assert-MockCalled Set-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd002' }
        Assert-MockCalled Set-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd003' }
    }

    It 'Should not set the policy for devices that are not assigned to the user' {
        $result = (Set-TeamViewerDevicesPolicy 'inherit' -groupIds 'g004')
        $result | Should -HaveCount 2
        $result | Where-Object { $_.DeviceId -eq 'd004' } | `
            Select-Object -ExpandProperty 'Status' | Should -Be 'Skipped'
        Assert-MockCalled Get-TeamViewerGroup -Times 0 -Scope It
        Assert-MockCalled Get-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $GroupId -eq 'g004' }
        Assert-MockCalled Set-TeamViewerDevice -Times 0 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd004' }
        Assert-MockCalled Set-TeamViewerDevice -Times 1 -Scope It `
            -ParameterFilter { $Device.Id -eq 'd004a' }
    }
}
