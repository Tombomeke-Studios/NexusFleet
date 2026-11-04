[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: a fake token, never a real secret.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru

    $plainToken = 'nxi_ConnectTestToken123'
    $token = ConvertTo-SecureString -String $plainToken -AsPlainText -Force
    $config = @{
        Api = @{ BaseUrl = 'https://panel.test'; TimeoutSeconds = 30; RetryCount = 2; AllowUnencryptedHttp = $false; SecretName = 'NexusFleet-ApiToken' }
    }

    # Builds the error Invoke-NexusApi throws, with the given error id.
    function Get-ApiError {
        param([string]$ErrorId, [string]$Message)
        [System.Management.Automation.ErrorRecord]::new([System.InvalidOperationException]::new($Message), $ErrorId, 'PermissionDenied', $null)
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Connect-NexusInfra' {
    BeforeEach {
        # Logs go to TestDrive, not to ./logs.
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -ParameterFilter { $Path -eq '/me' } -MockWith {
            [pscustomobject]@{ id = 'user-1'; email = 'tom@example.com'; platformRole = 'owner' }
        }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -ParameterFilter { $Path -eq '/users' } -MockWith { @() }
        Mock -ModuleName NexusFleet -CommandName Save-NexusStoredToken -MockWith { }
        Mock -ModuleName NexusFleet -CommandName Get-NexusStoredToken -MockWith { $token }
        & $module { $script:NexusSession = $null }
    }

    It 'checks the account with GET /me and the admin scope with GET /users' {
        $null = Connect-NexusInfra -Token $token

        Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/me' -and $Method -eq 'GET' -and $BaseUrl -eq 'https://panel.test' -and $Token -is [securestring]
        }
        Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter { $Path -eq '/users' }
    }

    It 'returns a connection object without the token and keeps the session in the module' {
        $connection = Connect-NexusInfra -Token $token

        $connection.PSObject.TypeNames | Should -Contain 'NexusFleet.Connection'
        $connection.BaseUrl | Should -Be 'https://panel.test'
        $connection.User | Should -Be 'tom@example.com'
        $connection.PlatformRole | Should -Be 'owner'
        $connection.PSObject.Properties.Name | Should -Not -Contain 'Token'

        $session = & $module { Get-NexusSession }
        $session.Token | Should -Be $token
        $session.User | Should -Be 'tom@example.com'
    }

    It 'uses -BaseUrl instead of the configured address when given' {
        $null = Connect-NexusInfra -BaseUrl 'https://other.test' -Token $token

        Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -ParameterFilter { $BaseUrl -eq 'https://other.test' }
    }

    It 'takes the token from SecretManagement when -Token is not given' {
        $null = Connect-NexusInfra

        Should -Invoke -ModuleName NexusFleet -CommandName Get-NexusStoredToken -Times 1 -Exactly -ParameterFilter { $SecretName -eq 'NexusFleet-ApiToken' }
    }

    It 'refuses an account that is not a platform administrator, and does not connect' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -ParameterFilter { $Path -eq '/me' } -MockWith {
            [pscustomobject]@{ email = 'guest@example.com'; platformRole = 'user' }
        }

        { Connect-NexusInfra -Token $token } |
            Should -Throw -ErrorId 'NexusFleet.NotPlatformAdmin*' -ExpectedMessage '*guest@example.com*platform administrator*'
        { & $module { Get-NexusSession } } | Should -Throw -ErrorId 'NexusFleet.NotConnected*'
    }

    It 'explains that the token needs the admin scope when GET /users is forbidden' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -ParameterFilter { $Path -eq '/users' } -MockWith {
            throw (Get-ApiError -ErrorId 'NexusApi.Forbidden' -Message 'NexusInfra API GET /users failed 403')
        }

        { Connect-NexusInfra -Token $token } |
            Should -Throw -ErrorId 'NexusFleet.TokenMissingAdminScope*' -ExpectedMessage '*admin scope*write*admin*'
    }

    It 'passes other API errors on with their own id (for example an invalid token)' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -ParameterFilter { $Path -eq '/me' } -MockWith {
            throw (Get-ApiError -ErrorId 'NexusApi.Unauthorized' -Message 'NexusInfra API GET /me failed 401: the API token is invalid')
        }

        { Connect-NexusInfra -Token $token } | Should -Throw -ErrorId 'NexusApi.Unauthorized*'
    }

    It 'passes a failure of GET /users other than 403 on unchanged (here: the panel went away)' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -ParameterFilter { $Path -eq '/users' } -MockWith {
            throw (Get-ApiError -ErrorId 'NexusApi.Unreachable' -Message 'cannot reach the panel at https://panel.test')
        }

        { Connect-NexusInfra -Token $token } | Should -Throw -ErrorId 'NexusApi.Unreachable*' -ExpectedMessage '*cannot reach the panel*'
        & $module { $script:NexusSession } | Should -BeNullOrEmpty
    }

    It 'stores the token with -Save' {
        $connection = Connect-NexusInfra -Token $token -Save

        Should -Invoke -ModuleName NexusFleet -CommandName Save-NexusStoredToken -Times 1 -Exactly -ParameterFilter { $SecretName -eq 'NexusFleet-ApiToken' }
        $connection.TokenSaved | Should -BeTrue
    }

    It 'does not store the token with -Save -WhatIf' {
        $connection = Connect-NexusInfra -Token $token -Save -WhatIf

        Should -Invoke -ModuleName NexusFleet -CommandName Save-NexusStoredToken -Times 0 -Exactly
        $connection.TokenSaved | Should -BeFalse
    }

    It 'logs the connection, and never the token' {
        $null = Connect-NexusInfra -Token $token

        $log = Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'run.log') -Raw
        $log | Should -Match 'Connected to https://panel.test as tom@example.com'
        $log | Should -Not -Match $plainToken
    }
}
