# Copyright (c) 2019 TeamViewer GmbH
# See file LICENSE.txt

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut" -ApiToken "testApiToken" -Path "testPath" -InformationAction 'SilentlyContinue'

Describe 'Import-TeamViewerUser' {
    Mock Invoke-TeamViewerPing { $true }
    Mock Get-TeamViewerUser { }
    Mock Add-TeamViewerUser { }
    Mock Edit-TeamViewerUser { }
    $testUser = @{ email = 'user1@example.test'; name = 'Test User' }

    It 'Should check the connection to the TeamViewer API' {
        { Import-TeamViewerUser 'TestAccessToken' } | Should -Not -Throw
        Assert-MockCalled Invoke-TeamViewerPing -Times 1 -Scope It
    }

    Context 'TeamViewer API not reachable' {
        Mock Invoke-TeamViewerPing { $false }

        It 'Should abort if TeamViewer API is not reachable' {
            { Import-TeamViewerUser 'TestAccessToken' -ErrorAction Stop } | Should -Throw
        }
    }

    It 'Should check for existence of a user' {
        $testUser | Import-TeamViewerUser 'TestAccessToken'
        Assert-MockCalled Get-TeamViewerUser -Times 1 -Scope It -ParameterFilter {
            $email -And $email -eq $testUser.email
        }
    }

    Context 'User already exists' {
        Mock Get-TeamViewerUser { @{ id = 1234; email = $testUser.email; name = 'Old Name' } }

        It 'Should update the existing user' {
            $result = ($testUser | Import-TeamViewerUser 'TestAccessToken')
            $result | Should -Not -BeNullOrEmpty
            $result.Updated | Should -Be 1
            $result.Created | Should -Be 0
            Assert-MockCalled Edit-TeamViewerUser -Times 1 -Scope It -ParameterFilter {
                $userId -And $userId -eq 1234 -And
                $user -And $user -eq $testUser
            }
        }
    }

    Context 'User does NOT exist' {
        It 'Should create a new user' {
            $result = ($testUser | Import-TeamViewerUser 'TestAccessToken')
            $result | Should -Not -BeNullOrEmpty
            $result.Created | Should -Be 1
            $result.Updated | Should -Be 0
            Assert-MockCalled Add-TeamViewerUser -Times 1 -Scope It -ParameterFilter {
                $user -And $user -eq $testUser
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
function Invoke-TeamViewerRestMethod($Uri, $Method, $Headers, $Body) { }

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
        Get-TeamViewerUser 'TestAccessToken' 'test1@example.test'
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And ([System.Uri]$Uri).PathAndQuery -eq '/api/v1/users' -And
            $Method -And $Method -eq 'Get'
            $Body -And $Body.email -eq 'test1@example.test'
        }
    }

    It 'Should return a single user' {
        $result = (Get-TeamViewerUser 'TestAccessToken' 'test1@example.test')
        $result | Should -HaveCount 1
        $result.email | Should -Be 'test1@example.test'
    }

    It 'Should set the authorization header' {
        Get-TeamViewerUser 'TestAccessToken' 'test1@example.test'
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Add-TeamViewerUser' {
    $testUser = @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test' }
    $lastMockParams = @{ }
    Mock Invoke-TeamViewerRestMethod {
        $lastMockParams.Body = $Body
        return $testUser
    }

    It 'Should call the API users endpoint' {
        $input = @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test'; 'language' = 'en' }
        Add-TeamViewerUser 'TestAccessToken' $input | Should -Be $testUser
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And ([System.Uri]$Uri).PathAndQuery -eq '/api/v1/users' -And
            $Method -And $Method -eq 'Post'
        }
    }

    It 'Should throw if required fields are missing' {
        $inputs = @(
            @{ 'email' = 'test1@example.test'; 'language' = 'en' }, # missing 'name'
            @{ 'name' = 'Test User 1'; 'language' = 'en' }, # missing 'email'
            @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test' } # missing 'language'
        )
        $inputs | ForEach-Object { { Add-TeamViewerUser 'TestAccessToken' $_ } | Should -Throw }
    }

    It 'Should encode the payload using UTF-8' {
        $input = @{ 'name' = 'Test User Müller'; 'email' = 'test1@example.test'; 'language' = 'en' }
        Add-TeamViewerUser 'TestAccessToken' $input
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter { $Body }
        { [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) } | Should -Not -Throw
        { [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json } | Should -Not -Throw
        ([System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json).name | Should -Be 'Test User Müller'
    }

    It 'Should set the authorization header' {
        $input = @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test'; 'language' = 'en' }
        Add-TeamViewerUser 'TestAccessToken' $input
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Edit-TeamViewerUser' {
    $testUser = @{ 'id' = '1234'; 'name' = 'Test User 1'; 'email' = 'test1@example.test' }
    Mock Invoke-TeamViewerRestMethod { $testUser }

    It 'Should call the API users endpoint' {
        $input = @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test' }
        $result = (Edit-TeamViewerUser 'TestAccessToken' 1234 $input)
        $result.id | Should -Be $testUser.id
        $result.name | Should -Be $testUser.name
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And ([System.Uri]$Uri).PathAndQuery -eq '/api/v1/users/1234' -And
            $Method -And $Method -eq 'Put'
        }
    }

    It 'Should set the authorization header' {
        $input = @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test' }
        Edit-TeamViewerUser 'TestAccessToken' 1234 $input
        Assert-MockCalled Invoke-TeamViewerRestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}