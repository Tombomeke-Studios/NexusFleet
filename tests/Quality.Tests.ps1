# Tests about the tests: they find gaps that a reviewer would otherwise have to spot by hand.
#   - every value in config/nexusinfra.psd1 has a validation rule: a wrong type and a missing value are refused,
#     with the key named in the message (so a new config key without a rule fails here)
#   - every error id that src/ can raise (NexusFleet.* and NexusApi.*) is asserted by at least one test
#   - every cmdlet that starts a run passes the log settings of the config
#   - every action a workflow uses is pinned to a full commit SHA (a tag can be moved, a commit cannot)
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeDiscovery are used in It blocks; the analyzer does not look across script blocks.')]
param()

BeforeDiscovery {
    $root = Join-Path -Path $PSScriptRoot -ChildPath '..'

    # Every 'uses:' of another repository's action in the workflows and in our own composite actions.
    $actionFiles = @(Get-ChildItem -Path (Join-Path -Path $root -ChildPath '.github') -Include '*.yml' -Recurse -File |
            Where-Object { $_.FullName -match '[\\/](workflows|actions)[\\/]' })
    $actionUses = foreach ($file in $actionFiles) {
        $number = 0
        foreach ($line in Get-Content -Path $file.FullName) {
            $number++
            if ($line -match '^\s*(-\s*)?uses:\s*(?<ref>[^\s#]+)(\s*#\s*(?<comment>.*))?$' -and $Matches.ref -notlike './*') {
                @{ File = $file.Name; Line = $number; Ref = $Matches.ref; Comment = $Matches.comment }
            }
        }
    }

    # Every leaf of the default config as a dotted key, e.g. Agent.EnvNames.NodeId.
    function Get-LeafKey {
        param([hashtable]$Table, [string]$Prefix = '')
        foreach ($key in $Table.Keys) {
            $path = if ($Prefix) { "$Prefix.$key" } else { $key }
            if ($Table[$key] -is [hashtable]) { Get-LeafKey -Table $Table[$key] -Prefix $path } else { $path }
        }
    }
    $configKeys = @(Get-LeafKey -Table (Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'config/nexusinfra.psd1')) |
            Sort-Object | ForEach-Object { @{ Key = $_ } })

    # Error ids are the 'NexusFleet.X' and 'NexusApi.X' texts in src/ that are not type names (PSTypeName).
    $errorIds = @(Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'src') -Filter '*.ps1' -Recurse |
            Get-Content | Where-Object { $_ -notmatch 'PSTypeName' } |
            ForEach-Object { [regex]::Matches($_, "'(Nexus(Fleet|Api)\.[A-Za-z]+)'") | ForEach-Object { $_.Groups[1].Value } } |
            Sort-Object -Unique | ForEach-Object { @{ Id = $_ } })

    # Every call of Initialize-NexusRunContext in a public cmdlet, read from the code (AST), not run.
    $runCalls = foreach ($file in Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'src/public') -Filter '*.ps1') {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
        $isRunCall = {
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Initialize-NexusRunContext'
        }
        foreach ($call in $ast.FindAll($isRunCall, $true)) {
            $parameters = $call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] }
            @{ File = $file.Name; Line = $call.Extent.StartLineNumber; Parameters = @($parameters.ParameterName) }
        }
    }
    $runCalls = @($runCalls)
}

BeforeAll {
    $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
    . (Join-Path -Path $root -ChildPath 'src/utils/Merge-NexusHashtable.ps1')
    . (Join-Path -Path $root -ChildPath 'src/utils/Get-NexusConfig.ps1')
    $defaultConfig = Join-Path -Path $root -ChildPath 'config/nexusinfra.psd1'
    $noLocal = Join-Path -Path $TestDrive -ChildPath 'none.local.psd1'

    # Writes the default config with one key changed: -Value $null removes the key.
    function Write-ChangedConfig {
        param([string]$Key, [object]$Value, [switch]$Remove)
        $config = Import-PowerShellDataFile -Path $defaultConfig
        $parts = $Key.Split('.')
        $table = $config
        foreach ($part in $parts[0..($parts.Count - 2)]) { $table = $table[$part] }
        if ($Remove) { $table.Remove($parts[-1]) } else { $table[$parts[-1]] = $Value }

        # A small writer for the psd1 format: hashtables, arrays, strings, numbers and booleans.
        function ConvertTo-Psd1 {
            param([object]$Item)
            if ($Item -is [hashtable]) { return '@{ ' + (($Item.Keys | ForEach-Object { "$_ = $(ConvertTo-Psd1 $Item[$_])" }) -join '; ') + ' }' }
            if ($Item -is [array]) { return '@(' + (($Item | ForEach-Object { ConvertTo-Psd1 $_ }) -join ', ') + ')' }
            if ($Item -is [bool]) { return "`$$($Item.ToString().ToLower())" }
            if ($Item -is [int] -or $Item -is [long]) { return "$Item" }
            return "'" + "$Item".Replace("'", "''") + "'"
        }
        $path = Join-Path -Path $TestDrive -ChildPath "$([guid]::NewGuid().ToString('N')).psd1"
        Set-Content -Path $path -Value (ConvertTo-Psd1 $config)
        $path
    }

    $testText = (Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'tests') -Filter '*.Tests.ps1' -Recurse |
            Where-Object Name -NE 'Quality.Tests.ps1' | Get-Content -Raw) -join "`n"
}

Describe 'Every config value has a validation rule' {
    It 'the unchanged default config is valid (the writer in this test keeps it intact)' {
        { Get-NexusConfig -Path (Write-ChangedConfig -Key 'Api.TimeoutSeconds' -Value 30) -LocalPath $noLocal } | Should -Not -Throw
    }

    It '<Key>: a value of the wrong type is refused, naming the key' -ForEach $configKeys {
        # A hashtable is never a valid leaf value, whatever the rule expects.
        $path = Write-ChangedConfig -Key $Key -Value @{ wrong = 'type' }

        { Get-NexusConfig -Path $path -LocalPath $noLocal } | Should -Throw -ExpectedMessage "*$Key must be*"
    }

    It '<Key>: a missing value is refused, naming the key' -ForEach $configKeys {
        $path = Write-ChangedConfig -Key $Key -Remove

        { Get-NexusConfig -Path $path -LocalPath $noLocal } | Should -Throw -ExpectedMessage "*$Key is missing*"
    }
}

Describe 'Every link in the documentation works' {
    BeforeDiscovery {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        $markdownFiles = @(Get-ChildItem -Path $root -Filter '*.md' -Recurse -File |
                Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|out|TestResults|logs)[\\/]' } |
                ForEach-Object { @{ File = $_.FullName; Name = [System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/') } })
    }

    BeforeAll {
        # The anchor GitHub makes of a heading: lowercase, spaces to dashes, punctuation dropped.
        function Get-Anchor {
            param([string]$Heading)
            ($Heading.Trim().ToLowerInvariant() -replace '[^\w\- ]', '' -replace ' ', '-')
        }
        function Get-HeadingAnchor {
            param([string]$Path)
            @(Get-Content -Path $Path | Where-Object { $_ -match '^#{1,6} ' } | ForEach-Object { Get-Anchor -Heading ($_ -replace '^#+ ', '') })
        }
    }

    It '<Name>: every relative link points to a file (and heading) that exists' -ForEach $markdownFiles {
        $text = Get-Content -Path $File -Raw
        # [text](target) outside code: links to http(s), mail or a pure anchor are not checked here.
        $withoutCode = [regex]::Replace($text, '(?s)```.*?```', '')
        $withoutCode = [regex]::Replace($withoutCode, '`[^`\n]*`', '')
        foreach ($match in [regex]::Matches($withoutCode, '\]\(([^)\s]+)\)')) {
            $target = $match.Groups[1].Value
            if ($target -match '^(https?:|mailto:|#)') { continue }
            $path, $anchor = $target -split '#', 2
            $resolved = Join-Path -Path (Split-Path -Path $File -Parent) -ChildPath ([uri]::UnescapeDataString($path))
            Test-Path -Path $resolved | Should -BeTrue -Because "$Name links to '$target'"
            if ($anchor -and $resolved -like '*.md') {
                Get-HeadingAnchor -Path $resolved | Should -Contain $anchor -Because "$Name links to the heading '#$anchor' in '$path'"
            }
        }
    }

    It 'every online link in the cmdlet help points to an existing document and heading' {
        $helpLinks = Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'src/public') -Filter '*.ps1' | Get-Content |
            ForEach-Object { [regex]::Match($_, 'NexusFleet/blob/dev/(docs/[\w.-]+\.md)(#[\w-]+)?') } | Where-Object Success
        $helpLinks | Should -Not -BeNullOrEmpty
        foreach ($link in $helpLinks) {
            $document = Join-Path -Path $root -ChildPath $link.Groups[1].Value
            Test-Path -Path $document | Should -BeTrue -Because "the help links to $($link.Value)"
            if ($link.Groups[2].Success) {
                Get-HeadingAnchor -Path $document | Should -Contain $link.Groups[2].Value.TrimStart('#') -Because "the help links to $($link.Value)"
            }
        }
    }
}

Describe 'Every run uses the log settings of the config' {
    It 'there is a run context call in every cmdlet that logs (the AST search works)' -ForEach @{ Count = $runCalls.Count } {
        $Count | Should -BeGreaterOrEqual 5
    }

    It '<File>:<Line> passes -LogRoot from the config' -ForEach $runCalls {
        $Parameters | Should -Contain 'LogRoot' -Because 'Log.Directory decides where the logs go'
    }
}

Describe 'Every error id is tested' {
    It '<Id> is asserted by at least one test' -ForEach $errorIds {
        $testText | Should -Match ([regex]::Escape($Id)) -Because "a test should prove when $Id is raised"
    }
}

Describe 'Every action is pinned to a commit' {
    It 'the search finds the actions the workflows use' -ForEach @{ Count = @($actionUses).Count } {
        $Count | Should -BeGreaterThan 5
    }

    It '<File>:<Line> <Ref> is a full commit SHA with its version as a comment' -ForEach $actionUses {
        $Ref | Should -Match '@[0-9a-f]{40}$' -Because 'a tag like @v4 can be moved by whoever owns the action; a commit cannot'
        $Comment | Should -Match '^v\d+' -Because 'the comment says which version the SHA is, for people and for Dependabot'
    }
}
