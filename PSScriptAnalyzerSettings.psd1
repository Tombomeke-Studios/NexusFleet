@{
    # Report every severity: the goal is zero findings, not only zero errors.
    Severity            = @('Error', 'Warning', 'Information')

    # All built-in rules (approved verbs, no aliases, ShouldProcess, ...) plus the
    # formatting rules below, which are off by default.
    IncludeDefaultRules = $true

    Rules               = @{
        # One code style: 4 spaces, opening brace on the same line, closing brace on its own line.
        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        # The = inside hashtables is aligned by PSAlignAssignmentStatement, so the
        # one-space-around-operators check skips it there (otherwise the two rules conflict).
        PSUseConsistentWhitespace  = @{
            Enable                                  = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckSeparator                          = $true
            CheckInnerBrace                         = $true
            CheckPipe                               = $true
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }

        # PSUseCorrectCasing stays off on purpose: with PSScriptAnalyzer 1.24/1.25 it makes about one
        # run in ten fail with "Get-Command is not recognized" or a NullReferenceException (race in the
        # analyzer's command lookup, see PowerShell/PSScriptAnalyzer#2205). Without it: 0 failures in
        # 105 runs. Casing is cosmetic; re-enable when the bug is fixed (#12, docs/ontwerpkeuzes.md K2).
        # Lint with ./tools/Invoke-NexusLint.ps1, which retries the analyzer's own internal errors.

        # The module targets PowerShell 7.6+ only: flag syntax that 7.6 does not understand.
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('7.6')
        }
    }
}
