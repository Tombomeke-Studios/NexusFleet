[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $checkScript = Join-Path -Path $PSScriptRoot -ChildPath '../../tools/Test-NexusCommitMessage.ps1'
}

Describe 'Test-NexusCommitMessage' {
    It 'accepts a message that follows the rules: <Message>' -ForEach @(
        @{ Message = 'feat(steps): add agent container step with rollback' }
        @{ Message = 'fix(api): retry a 429 for every method' }
        @{ Message = 'ci(ci): bump actions/checkout from 7.0.0 to 7.1.0' }
        @{ Message = "docs(docs): explain the demo job`n`nThe body may say anything." }
        @{ Message = 'Merge pull request #127 from Tombomeke-Studios/feature/ci-demo' }
        @{ Message = "Merge remote-tracking branch 'origin/dev' into feature/ci-demo" }
        @{ Message = "Merge branch 'dev' into feature/x" }
        @{ Message = 'test(lab): E3 prove mocks do not reach -Parallel runspaces' }
    ) {
        $result = & $checkScript -Message $Message

        $result.Valid | Should -BeTrue
        $result.Reason | Should -BeNullOrEmpty
    }

    It 'refuses <Why>' -ForEach @(
        @{ Message = 'Fix six findings of the code review'; Why = 'a message without type and scope'; Reason = '*type(scope): summary*' }
        @{ Message = 'feature(steps): add a step'; Why = 'an unknown type'; Reason = "*type 'feature'*feat, fix*" }
        @{ Message = 'feat(gui): add a window'; Why = 'an unknown scope'; Reason = "*scope 'gui'*core, steps*" }
        @{ Message = 'feat(steps): add a step.'; Why = 'a summary that ends with a full stop'; Reason = '*full stop*' }
        @{ Message = 'feat(steps):add a step'; Why = 'no space after the colon'; Reason = '*type(scope): summary*' }
        @{ Message = "feat(steps): $('x' * 90)"; Why = 'a first line longer than 100 characters'; Reason = '*100*' }
    ) {
        $result = & $checkScript -Message $Message

        $result.Valid | Should -BeFalse
        $result.Reason | Should -BeLike $Reason
    }

    It 'gives the type and the scope of a valid message, and none for a merge or an invalid one' {
        $results = & $checkScript -Message 'fix(api): retry a 429', 'Merge pull request #1 from x/y', 'no rules here'

        $results[0].Type | Should -Be 'fix'
        $results[0].Scope | Should -Be 'api'
        $results[1].Type | Should -BeNullOrEmpty
        $results[2].Type | Should -BeNullOrEmpty
    }

    It 'checks every message it gets, also from the pipeline, and keeps only the first line in the result' {
        $results = "fix(core): a`nbody", 'bad message' | & $checkScript

        $results | Should -HaveCount 2
        $results[0].Message | Should -Be 'fix(core): a'
        $results.Valid | Should -Be @($true, $false)
    }

    It 'reads the commits of a range from git, without the merge commits' {
        $repo = Join-Path -Path $TestDrive -ChildPath 'repo'
        $null = New-Item -Path $repo -ItemType Directory
        Push-Location -Path $repo
        try {
            git init -q -b main
            git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m 'chore(ci): start'
            git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m 'feat(steps): add a step'
            git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m 'wip'
            git checkout -q -b side HEAD~1
            git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m 'fix(core): on the side'
            git checkout -q main
            git -c user.name=t -c user.email=t@example.com merge -q --no-ff -m 'Merge side into main, by hand' side

            $results = & $checkScript -Range 'HEAD~1~2..HEAD'
        }
        finally {
            Pop-Location
        }

        # The hand-written merge message is left out; the commits of both lines are checked.
        # (In which order the two lines come depends on the commit times, which are equal here.)
        $results | Should -HaveCount 3
        ($results | Where-Object { -not $_.Valid }).Message | Should -Be 'wip'
        $results.Message | Should -Contain 'fix(core): on the side'
        $results.Message | Should -Not -Contain 'Merge side into main, by hand'
    }
}
