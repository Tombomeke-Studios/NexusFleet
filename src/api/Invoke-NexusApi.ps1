function Invoke-NexusApi {
    <#
    .SYNOPSIS
    Calls the NexusInfra REST API. The only function in NexusFleet that does.

    .DESCRIPTION
    Sends the API token as a bearer token (kept as a SecureString), with a time-out. A 429 (the gateway's
    rate limit) is retried for every method: the gateway refused it before NexusInfra saw it. After a network error
    or 502/503/504 only GET requests are retried: a POST that half succeeded must never be sent twice. HTTP errors 401, 403, 404, 409, 429 and 502-504 become errors with their
    own id (NexusApi.Unauthorized, NexusApi.Forbidden, NexusApi.NotFound, NexusApi.Conflict, NexusApi.RateLimited,
    NexusApi.Unavailable), an explanation, and NexusInfra's own message.
    A panel that cannot be reached gives NexusApi.Unreachable.

    The token is only sent over plain http:// to the own machine (localhost, 127.0.0.1, ::1). For any other
    http:// address the caller must pass -AllowUnencryptedHttp (config: Api.AllowUnencryptedHttp), and a
    warning is shown; otherwise the request is refused before anything is sent (NexusApi.UnencryptedNotAllowed).

    .PARAMETER BaseUrl
    The address of the panel, e.g. http://localhost:9400 (from the config, Api.BaseUrl).

    .PARAMETER Token
    The API token (nxi_...) as a SecureString.

    .PARAMETER Method
    GET, POST, PATCH, PUT or DELETE.

    .PARAMETER Path
    The API path, starting with /, e.g. /nodes.

    .PARAMETER Body
    Optional data to send; converted to JSON.

    .PARAMETER TimeoutSeconds
    Time-out per attempt (config: Api.TimeoutSeconds).

    .PARAMETER RetryCount
    Extra attempts for GET requests (config: Api.RetryCount).

    .PARAMETER RetryDelayMilliseconds
    Wait before a retry; doubles with every attempt (1 s, 2 s, ...).

    .PARAMETER AllowUnencryptedHttp
    Allow sending the token over http:// to a host other than this machine (config: Api.AllowUnencryptedHttp).

    .EXAMPLE
    Invoke-NexusApi -BaseUrl $config.Api.BaseUrl -Token $token -Method GET -Path '/nodes'

    .EXAMPLE
    Invoke-NexusApi -BaseUrl $config.Api.BaseUrl -Token $token -Method POST -Path '/nodes' -Body @{ id = 'node-a'; name = 'A' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https?://\S+$')]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [securestring]$Token,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [ValidatePattern('^/')]
        [string]$Path,

        [object]$Body,

        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30,

        [ValidateRange(0, 10)]
        [int]$RetryCount = 2,

        [ValidateRange(0, 60000)]
        [int]$RetryDelayMilliseconds = 1000,

        [switch]$AllowUnencryptedHttp
    )

    $uri = $BaseUrl.TrimEnd('/') + $Path
    $request = @{
        Method         = $Method
        Uri            = $uri
        Authentication = 'Bearer'
        Token          = $Token
        TimeoutSec     = $TimeoutSeconds
        ErrorAction    = 'Stop'
    }
    # PowerShell refuses to send a token over http:// unless told to (AllowUnencryptedAuthentication).
    # To the own machine that is harmless; to any other host only when explicitly allowed.
    $baseUri = [uri]$BaseUrl
    if ($baseUri.Scheme -eq 'http') {
        if (-not $baseUri.IsLoopback) {
            if (-not $AllowUnencryptedHttp) {
                $exception = [System.InvalidOperationException]::new(
                    "NexusFleet refuses to send the API token unencrypted to $BaseUrl. Use https://, or set " +
                    "Api.AllowUnencryptedHttp = `$true in config/nexusinfra.local.psd1 if this network is trusted.")
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        $exception, 'NexusApi.UnencryptedNotAllowed', 'SecurityError', $BaseUrl))
            }
            Write-Warning "Sending the API token unencrypted (http://) to $($baseUri.Host)."
        }
        $request.AllowUnencryptedAuthentication = $true
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.Body = $Body | ConvertTo-Json -Depth 10 -Compress
        $request.ContentType = 'application/json'
    }

    $maxAttempts = 1 + $RetryCount

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            # Invoke-RestMethod writes a JSON list as one object. Put in a variable and written out, the list
            # is sent item by item, as every PowerShell command does with a list (found in the node lab).
            $response = Invoke-RestMethod @request
            return $response
        }
        catch {
            # Keep the error in its own variable: inside the switch below, $_ means the switch value.
            $caught = $_
            $status = if ($caught.Exception.Response) { [int]$caught.Exception.Response.StatusCode } else { $null }
            # No HTTP answer at all: a network problem (no route, refused, DNS, time-out) or something else.
            $isNetworkError = $null -eq $status -and (
                $caught.Exception -is [System.Net.Http.HttpRequestException] -or
                $caught.Exception -is [System.Threading.Tasks.TaskCanceledException] -or
                $caught.Exception -is [System.TimeoutException])
            # 429: the gateway's rate limit per token. Many hosts polling at once can reach it; a moment later it
            # lets the request through again. The gateway refuses it before NexusInfra sees it, so even a changing
            # request (POST) may be sent again. After a network error or a 502-504 only reading is safe to repeat:
            # NexusInfra may have done the change already, and the answer got lost.
            $isTransient = $isNetworkError -or ($status -in 429, 502, 503, 504)
            $mayRepeat = $status -eq 429 -or ($Method -eq 'GET' -and $isTransient)

            if ($mayRepeat -and $attempt -lt $maxAttempts) {
                Write-Verbose "NexusInfra API: $Method $Path failed (attempt $attempt of $maxAttempts), retrying."
                Start-Sleep -Milliseconds ($RetryDelayMilliseconds * [math]::Pow(2, $attempt - 1))
                continue
            }

            # NexusInfra answers errors as { "error": "..." }; PowerShell keeps that body in ErrorDetails.
            # Only when there was an HTTP answer: for network errors PowerShell fills ErrorDetails itself.
            $serverMessage = ''
            if ($status -and $caught.ErrorDetails.Message) {
                $serverMessage = try { ($caught.ErrorDetails.Message | ConvertFrom-Json).error } catch { $caught.ErrorDetails.Message }
            }

            $kind = if ($status) { "$status" } elseif ($isNetworkError) { 'network' } else { 'other' }
            $errorId, $category, $explanation = switch ($kind) {
                '401' { 'NexusApi.Unauthorized', 'AuthenticationError', 'the API token is invalid, expired or revoked' }
                '403' { 'NexusApi.Forbidden', 'PermissionDenied', 'the account or the token lacks permission (node routes need a platform administrator and a token with the write and admin scopes)' }
                '404' { 'NexusApi.NotFound', 'ObjectNotFound', 'not found (NexusInfra also answers 404 when you have no access)' }
                '409' { 'NexusApi.Conflict', 'ResourceExists', 'conflict with the current state (for example a node that still hosts a running deployment)' }
                '429' { 'NexusApi.RateLimited', 'LimitsExceeded', "the panel's rate limit for this token was reached (lower -ThrottleLimit, or raise Health.PollIntervalSeconds)" }
                { $_ -in '502', '503', '504' } { 'NexusApi.Unavailable', 'ResourceUnavailable', 'the panel is temporarily unavailable' }
                'network' { 'NexusApi.Unreachable', 'ConnectionError', "cannot reach the panel at $BaseUrl after $attempt attempt(s): $($caught.Exception.Message)" }
                'other' { 'NexusApi.RequestFailed', 'InvalidOperation', "the request could not be sent: $($caught.Exception.Message)" }
                default { 'NexusApi.HttpError', 'InvalidResult', 'unexpected answer from the panel' }
            }

            $statusText = if ($status) { " $status" } else { '' }
            $message = "NexusInfra API $Method $Path failed$($statusText): $explanation."
            if ($serverMessage) {
                $message += " NexusInfra says: $serverMessage"
            }

            $exception = [System.InvalidOperationException]::new($message, $caught.Exception)
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new($exception, $errorId, $category, $uri))
        }
    }
}
