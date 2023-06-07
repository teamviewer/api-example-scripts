# Copyright (c) 2019-2023 TeamViewer Germany GmbH
# See file LICENSE

BeforeAll {
    $testApiToken = [securestring]@{}

    . "$PSScriptRoot\Import-TeamViewerUser.ps1" -ApiToken $testApiToken -Path 'testPath' -InformationAction 'SilentlyContinue'

    Mock Invoke-TeamViewerPing { $true }
    Mock Get-TeamViewerUser {}
    Mock New-TeamViewerUser -RemoveParameterValidation 'Culture' {}
    Mock Set-TeamViewerUser -RemoveParameterValidation 'User' {}

    $testUser = @{ email = 'user1@example.test'; name = 'Test User' }
    $null = $testUser
}

Describe 'Import-TeamViewerUser' {
    It 'Should check the connection to the TeamViewer API' {
        { Import-TeamViewerUser } | Should -Not -Throw

        Assert-MockCalled Invoke-TeamViewerPing -Times 1 -Scope It
    }

    It 'Should abort if TeamViewer API is not reachable' {
        Mock Invoke-TeamViewerPing { $false }

        { Import-TeamViewerUser -ErrorAction Stop } | Should -Throw
    }

    It 'Should check for existence of a user' {
        $testUser | Import-TeamViewerUser

        Assert-MockCalled Get-TeamViewerUser -Times 1 -Scope It -ParameterFilter {
            $Email -And $Email -eq $testUser.email
        }
    }

    Context 'User already exists' {
        BeforeAll {
            Mock Get-TeamViewerUser {
                @{
                    Id    = 'u1234'
                    Email = $testUser.email
                    Name  = 'Old Name'
                }
            }
        }

        It 'Should update the existing user' {
            $result = ($testUser | Import-TeamViewerUser)
            $result | Should -Not -BeNullOrEmpty
            $result.Updated | Should -Be 1
            $result.Created | Should -Be 0

            Assert-MockCalled Set-TeamViewerUser -Times 1 -Scope It -ParameterFilter {
                $User -And $User.Id -eq 'u1234' -And
                $Property -And $Property -eq $testUser
            }
        }

        It 'Should acknowledge errors and continue' {
            Mock Set-TeamViewerUser { Write-Error 'test failure' }

            $result = ($testUser | Import-TeamViewerUser)
            $result | Should -Not -BeNullOrEmpty
            $result.Updated | Should -Be 0
            $result.Created | Should -Be 0
            $result.Failed | Should -Be 1
        }
    }

    Context 'User does NOT exist' {
        It 'Should create a new user' {
            $result = ($testUser | Import-TeamViewerUser)
            $result | Should -Not -BeNullOrEmpty
            $result.Created | Should -Be 1
            $result.Updated | Should -Be 0

            Assert-MockCalled New-TeamViewerUser -Times 1 -Scope It -ParameterFilter {
                $Email -And $Email -eq $testUser.email -And
                $Name -And $Name -eq $testUser.name -And
                $WithoutPassword
            }
        }

        It 'Should set additional parameters' {
            $testUser2 = @{
                email           = 'user2@example.test'
                name            = 'Test User 2'
                language        = 'de'
                password        = 'test123'
                sso_customer_id = 'foobar'
            }

            $result = ($testUser2 | Import-TeamViewerUser)
            $result | Should -Not -BeNullOrEmpty
            $result.Created | Should -Be 1
            $result.Updated | Should -Be 0

            Assert-MockCalled New-TeamViewerUser -Times 1 -Scope It -ParameterFilter {
                $Email -eq $testUser2.email -And
                $Name -eq $testUser2.name -And
                $Culture -eq [cultureinfo]'de' -And
                $Password -And
                $SsoCustomerIdentifier
            }
        }

        It 'Should acknowledge errors and continue' {
            Mock New-TeamViewerUser { Write-Error 'test failure' }

            $result = ($testUser | Import-TeamViewerUser)
            $result | Should -Not -BeNullOrEmpty
            $result.Updated | Should -Be 0
            $result.Created | Should -Be 0
            $result.Failed | Should -Be 1
        }
    }
}
