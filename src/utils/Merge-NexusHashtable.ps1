function Merge-NexusHashtable {
    <#
    .SYNOPSIS
    Returns a copy of a hashtable with the values of an override applied, also in nested hashtables.

    .DESCRIPTION
    Used to apply config/nexusinfra.local.psd1 on top of config/nexusinfra.psd1: the override only needs
    the keys that change. The base is never modified. A key in the override that the base does not have
    is probably a typo, so it gives a warning (and is still added).

    .PARAMETER Base
    The complete hashtable.

    .PARAMETER Override
    The values to apply.

    .PARAMETER KeyPrefix
    Used internally for the warning text of nested keys (e.g. "Api.").

    .EXAMPLE
    Merge-NexusHashtable -Base @{ Api = @{ BaseUrl = 'http://a'; TimeoutSeconds = 30 } } -Override @{ Api = @{ BaseUrl = 'https://b' } }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Base,

        [Parameter(Mandatory)]
        [hashtable]$Override,

        [string]$KeyPrefix = ''
    )

    $result = @{}
    foreach ($key in $Base.Keys) {
        $result[$key] = $Base[$key]
    }

    foreach ($key in $Override.Keys) {
        if (-not $Base.ContainsKey($key)) {
            Write-Warning "Unknown config key '$KeyPrefix$key' (not in the base config); check the spelling."
            $result[$key] = $Override[$key]
        }
        elseif ($Base[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            # Both sides are tables: merge them, key by key.
            $result[$key] = Merge-NexusHashtable -Base $Base[$key] -Override $Override[$key] -KeyPrefix "$KeyPrefix$key."
        }
        else {
            $result[$key] = $Override[$key]
        }
    }

    $result
}
