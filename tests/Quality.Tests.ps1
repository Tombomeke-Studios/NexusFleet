# Tests about the tests: they find gaps that a reviewer would otherwise have to spot by hand.
#   - every value in config/nexusinfra.psd1 has a validation rule: a wrong type and a missing value are refused,
#     with the key named in the message (so a new config key without a rule fails here)
#   - every error id that src/ can raise (NexusFleet.* and NexusApi.*) is asserted by at least one test
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeDiscovery are used in It blocks; the analyzer does not look across script blocks.')]
param()

BeforeDiscovery {
    $root = Join-Path -Path $PSScriptRoot -ChildPath '..'

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

Describe 'Every error id is tested' {
    It '<Id> is asserted by at least one test' -ForEach $errorIds {
        $testText | Should -Match ([regex]::Escape($Id)) -Because "a test should prove when $Id is raised"
    }
}
