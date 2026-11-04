function ConvertFrom-NexusFactLine {
    <#
    .SYNOPSIS
    Turns the key=value lines a host printed into a hashtable.

    .DESCRIPTION
    The preflight and the status each send one small script to a host that prints what it found as key=value lines
    (os=ubuntu, sudo=yes, ...). One connection then answers every question. This function reads that answer back.

    Only the first = separates key and value, so a value may contain = itself. Keys and values are trimmed, which
    also removes the carriage return of Windows line endings. A line without a key is skipped; a key without a value
    gets an empty string. A key that appears twice keeps its last value.

    .PARAMETER Text
    The output of the host (StdOut of a NexusFleet.CommandResult). Empty or $null gives an empty hashtable.

    .EXAMPLE
    $facts = ConvertFrom-NexusFactLine -Text "os=ubuntu`nsudo=yes"
    $facts.os

    Returns ubuntu.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    $facts = @{}
    foreach ($line in $Text -split "`n") {
        $key, $value = $line -split '=', 2
        if ($key.Trim()) {
            $facts[$key.Trim()] = "$value".Trim()
        }
    }
    $facts
}
