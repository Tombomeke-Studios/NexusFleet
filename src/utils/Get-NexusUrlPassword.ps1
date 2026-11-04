function Get-NexusUrlPassword {
    <#
    .SYNOPSIS
    Returns the password inside a URL such as amqp://user:password@host:5672, or nothing.

    .DESCRIPTION
    The broker URL (RABBITMQ_URL) is a secret, and it contains the broker's password. An error message can show that
    password without the rest of the URL, so Install-NexusNode registers it as a secret of its own and the log hides
    it too. The password is returned decoded (%40 becomes @), as a program would print it.

    A URL without a password, or a text that is not a URL, returns nothing and never an error: there is then simply
    no extra secret to hide.

    .PARAMETER Url
    The URL, as plain text.

    .EXAMPLE
    Get-NexusUrlPassword -Url 'amqp://fleet:Br0ker-pass@broker:5672'

    Returns Br0ker-pass.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url
    )

    $uri = $null
    if (-not [uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) {
        return
    }
    # UserInfo is 'user:password'; only the first ':' separates the two.
    $null, $password = $uri.UserInfo -split ':', 2
    if ($password) {
        [uri]::UnescapeDataString($password)
    }
}
