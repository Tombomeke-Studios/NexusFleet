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

        # Write commands with the casing they are defined with (Get-ChildItem, not get-childitem).
        PSUseCorrectCasing         = @{
            Enable = $true
        }

        # The module targets PowerShell 7.2+ only: flag syntax that 7.2 does not understand.
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('7.2')
        }
    }
}
