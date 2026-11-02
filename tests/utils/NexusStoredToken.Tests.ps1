[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: a fake token, never a real secret.')]
param()

# Get-NexusStoredToken and Save-NexusStoredToken: the only two functions that call SecretManagement.
BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Get-NexusStoredToken.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Save-NexusStoredToken.ps1')
    Import-Module -Name Microsoft.PowerShell.SecretManagement

    $token = ConvertTo-SecureString -String 'nxi_StoredTokenForTests' -AsPlainText -Force
}

Describe 'Get-NexusStoredToken' {
    It 'returns the token stored under the secret name' {
        Mock -CommandName Get-Secret -MockWith { $token }

        $result = Get-NexusStoredToken -SecretName 'NexusFleet-ApiToken'

        $result | Should -BeOfType [securestring]
        Should -Invoke -CommandName Get-Secret -ParameterFilter { $Name -eq 'NexusFleet-ApiToken' }
    }

    It 'explains how to store a token when none is found' {
        Mock -CommandName Get-Secret -MockWith { throw 'The secret NexusFleet-ApiToken was not found.' }

        { Get-NexusStoredToken -SecretName 'NexusFleet-ApiToken' } |
            Should -Throw -ErrorId 'NexusFleet.TokenNotStored*' -ExpectedMessage '*NexusFleet-ApiToken*Connect-NexusInfra*-Save*'
    }

    It 'refuses a stored secret that is not a SecureString' {
        Mock -CommandName Get-Secret -MockWith { 'plain text' }

        { Get-NexusStoredToken -SecretName 'NexusFleet-ApiToken' } | Should -Throw -ExpectedMessage '*not a SecureString*'
    }

    It 'explains how to install SecretManagement when it is missing' {
        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'Get-Secret' } -MockWith { $null }

        { Get-NexusStoredToken -SecretName 'NexusFleet-ApiToken' } |
            Should -Throw -ErrorId 'NexusFleet.SecretManagementMissing*' -ExpectedMessage '*Install-Module Microsoft.PowerShell.SecretManagement*'
    }
}

Describe 'Save-NexusStoredToken' {
    It 'stores the token under the secret name' {
        Mock -CommandName Set-Secret -MockWith { }

        Save-NexusStoredToken -SecretName 'NexusFleet-ApiToken' -Token $token

        Should -Invoke -CommandName Set-Secret -ParameterFilter { $Name -eq 'NexusFleet-ApiToken' -and $SecureStringSecret -is [securestring] }
    }

    It 'explains how to register a vault when storing fails' {
        Mock -CommandName Set-Secret -MockWith { throw 'There are currently no extension vaults registered.' }

        { Save-NexusStoredToken -SecretName 'NexusFleet-ApiToken' -Token $token } |
            Should -Throw -ErrorId 'NexusFleet.TokenNotSaved*' -ExpectedMessage '*Register-SecretVault*no extension vaults registered*'
    }
}
