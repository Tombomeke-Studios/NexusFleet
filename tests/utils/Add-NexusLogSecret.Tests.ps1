[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeEach are used in It blocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Initialize-NexusRunContext.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Add-NexusLogSecret.ps1')
}

Describe 'Add-NexusLogSecret' {
    BeforeEach {
        $context = Initialize-NexusRunContext -LogRoot $TestDrive -Secret 'short'
    }

    It 'adds the secret, longest first' {
        Add-NexusLogSecret -Context $context -Secret 'a-much-longer-secret'

        $context.Secrets | Should -Be @('a-much-longer-secret', 'short')
    }

    It 'ignores an empty secret' {
        Add-NexusLogSecret -Context $context -Secret ''

        $context.Secrets | Should -Be @('short')
    }

    It 'keeps every secret when many runspaces add one at the same time (#115)' {
        # The hosts of a run share the run context. Without the lock, two runspaces that read the list at the same
        # moment both write back their own version, and one secret is lost.
        $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1'

        1..40 | ForEach-Object -Parallel {
            $module = Import-Module -Name $using:manifest -PassThru -Force
            & $module { param($Context, $Number) Add-NexusLogSecret -Context $Context -Secret "link-token-$Number" } $using:context $_
        } -ThrottleLimit 20

        $context.Secrets | Should -HaveCount 41
        foreach ($number in 1..40) {
            $context.Secrets | Should -Contain "link-token-$number"
        }
    }
}
