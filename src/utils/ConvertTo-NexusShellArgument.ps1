function ConvertTo-NexusShellArgument {
    <#
    .SYNOPSIS
    Quotes a value so a POSIX shell (bash on the host) reads it as one literal word.

    .DESCRIPTION
    Wraps the value in single quotes. Inside single quotes the shell expands nothing ($, `, \, spaces are plain
    text); a single quote in the value itself becomes '\'' (end the quote, an escaped quote, start again).
    Every value NexusFleet puts into a remote command goes through this function, even values that were
    validated before: then a mistake in a validation rule cannot turn into a command on the host.

    .PARAMETER Value
    The text to quote.

    .EXAMPLE
    ConvertTo-NexusShellArgument -Value "it's"

    Returns 'it'\''s'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    "'" + $Value.Replace("'", "'\''") + "'"
}
