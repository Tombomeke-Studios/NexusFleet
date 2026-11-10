@{
    # The script file that holds the module's code (the loader).
    RootModule           = 'NexusFleet.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '384b398f-7c0f-423b-b83b-f9bcdf95dec8'
    Author               = 'Tom Dekoning'
    CompanyName          = 'Tombomeke Studios'
    Copyright            = '(c) 2026 Tom Dekoning. All rights reserved.'
    Description          = 'Turns Linux hosts into NexusInfra nodes and manages them as a fleet.'

    # PowerShell 7.6 (LTS, supported until November 2028); decision K4 in docs/ontwerpkeuzes.md.
    # 7.4+ is needed anyway to pipe secrets as bytes to ssh (experiment E1).
    PowerShellVersion    = '7.6'
    CompatiblePSEditions = @('Core')

    # Explicit lists, never '*': only the public cmdlets are visible to the user.
    # Each public cmdlet is added here when it lands in src/public/.
    FunctionsToExport    = @(
        'Connect-NexusInfra'
        'Import-NexusInventory'
        'Test-NexusHost'
        'Install-NexusNode'
        'Get-NexusFleetStatus'
        'Export-NexusFleetStatus'
        'Remove-NexusNode'
        'Get-NexusServer'
        'Invoke-NexusFleetAction'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('NexusInfra', 'Fleet', 'Docker', 'SSH', 'Automation', 'Linux')
            ProjectUri = 'https://github.com/Tombomeke-Studios/NexusFleet'
        }
    }
}
