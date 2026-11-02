# Invoke-NexusApi against a real HTTP server on this machine (no external hosts). The mocked tests in
# Invoke-NexusApi.Tests.ps1 check the logic; these check what Invoke-RestMethod really does. They found
# three problems the mocks could not: the refusal to send a token over http://, the empty reason of a
# network error, and PowerShell's text shown as a message from NexusInfra.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: a fake token, never a real secret.')]
param()

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/api/Invoke-NexusApi.ps1')

    # A free port: let the system pick one, then release it for the listener.
    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $port = $probe.LocalEndpoint.Port
    $probe.Stop()

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$port/")
    $listener.Start()

    # Answers requests until the listener is stopped in AfterAll. A thread job runs in the same process,
    # so $using:listener is the same object: stopping it in AfterAll ends the loop.
    $server = Start-ThreadJob -ScriptBlock {
        $httpListener = $using:listener
        while ($httpListener.IsListening) {
            try { $context = $httpListener.GetContext() } catch { break }
            switch ($context.Request.Url.AbsolutePath) {
                '/nodes' { $code = 403; $body = '{"error":"this API token does not have the admin scope"}' }
                '/busy' { $code = 503; $body = '{"error":"starting up"}' }
                default { $code = 200; $body = (@{ authorization = $context.Request.Headers['Authorization'] } | ConvertTo-Json -Compress) }
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $context.Response.StatusCode = $code
            $context.Response.ContentType = 'application/json'
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $context.Response.Close()
        }
    }

    $token = ConvertTo-SecureString -String 'nxi_LocalHttpTestToken' -AsPlainText -Force
    $api = @{ BaseUrl = "http://localhost:$port"; Token = $token; RetryDelayMilliseconds = 0 }
}

AfterAll {
    $listener.Stop()
    $null = Wait-Job -Job $server -Timeout 5
    Remove-Job -Job $server -Force
}

Describe 'Invoke-NexusApi against a local HTTP server' -Tag 'LocalHttp' {
    It 'sends the token as a bearer token over http:// to localhost and returns the JSON answer' {
        $answer = Invoke-NexusApi @api -Method GET -Path '/me'

        $answer.authorization | Should -Be 'Bearer nxi_LocalHttpTestToken'
    }

    It 'turns a real 403 with a JSON body into NexusApi.Forbidden with NexusInfra''s message' {
        { Invoke-NexusApi @api -Method POST -Path '/nodes' -Body @{ id = 'node-a' } } |
            Should -Throw -ErrorId 'NexusApi.Forbidden*' -ExpectedMessage '*NexusInfra says: this API token does not have the admin scope*'
    }

    It 'turns a real 503 into NexusApi.Unavailable' {
        { Invoke-NexusApi @api -Method GET -Path '/busy' -RetryCount 0 } |
            Should -Throw -ErrorId 'NexusApi.Unavailable*' -ExpectedMessage '*temporarily unavailable*starting up*'
    }

    It 'reports a closed port as unreachable, with the reason, and not as a message from NexusInfra' {
        $message = try {
            Invoke-NexusApi -BaseUrl 'http://127.0.0.1:1' -Token $token -Method GET -Path '/nodes' -RetryCount 0
            ''
        }
        catch {
            "$($_.FullyQualifiedErrorId) $($_.Exception.Message)"
        }

        $message | Should -Match '^NexusApi\.Unreachable'
        $message | Should -Match 'attempt\(s\): \S'
        $message | Should -Not -Match 'NexusInfra says'
    }
}
