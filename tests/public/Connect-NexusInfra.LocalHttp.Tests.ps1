# Connect-NexusInfra through the real Invoke-NexusApi against an HTTP server on this machine that answers
# like NexusInfra. Only the config and the log folder are replaced; nothing on the API path is mocked.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: fake tokens, never real secrets.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru

    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$port/")
    $listener.Start()

    # Answers like NexusInfra: the token decides who you are and which scopes you have.
    $server = Start-ThreadJob -ScriptBlock {
        $httpListener = $using:listener
        while ($httpListener.IsListening) {
            try { $context = $httpListener.GetContext() } catch { break }
            $auth = "$($context.Request.Headers['Authorization'])"
            $path = $context.Request.Url.AbsolutePath
            $code = 200
            if ($auth -notmatch '^Bearer nxi_') {
                $code = 401; $body = '{"error":"authentication required"}'
            }
            elseif ($path -eq '/me' -and $auth -match 'nxi_guest') {
                $body = '{"id":"u2","email":"guest@example.com","platformRole":"user"}'
            }
            elseif ($path -eq '/me') {
                $body = '{"id":"u1","email":"tom@example.com","platformRole":"owner"}'
            }
            elseif ($path -eq '/users' -and $auth -match 'nxi_writeonly') {
                $code = 403; $body = '{"error":"this API token does not have the admin scope"}'
            }
            else {
                $body = '[]'
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $context.Response.StatusCode = $code
            $context.Response.ContentType = 'application/json'
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $context.Response.Close()
        }
    }

    $baseUrl = "http://localhost:$port"
    $config = @{ Api = @{ BaseUrl = $baseUrl; TimeoutSeconds = 5; RetryCount = 0; AllowUnencryptedHttp = $false; SecretName = 'NexusFleet-ApiToken' } }
}

AfterAll {
    $listener.Stop()
    $null = Wait-Job -Job $server -Timeout 5
    Remove-Job -Job $server -Force
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Connect-NexusInfra against a local panel' -Tag 'LocalHttp' {
    BeforeEach {
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
    }

    It 'connects with an admin token and keeps the session' {
        $token = ConvertTo-SecureString -String 'nxi_owner_write_admin' -AsPlainText -Force

        $connection = Connect-NexusInfra -Token $token

        $connection.User | Should -Be 'tom@example.com'
        (& $module { Get-NexusSession }).BaseUrl | Should -Be $baseUrl
    }

    It 'refuses a token of an account that is not a platform administrator' {
        $token = ConvertTo-SecureString -String 'nxi_guest' -AsPlainText -Force

        { Connect-NexusInfra -Token $token } | Should -Throw -ErrorId 'NexusFleet.NotPlatformAdmin*'
    }

    It 'refuses a token without the admin scope' {
        $token = ConvertTo-SecureString -String 'nxi_writeonly' -AsPlainText -Force

        { Connect-NexusInfra -Token $token } | Should -Throw -ErrorId 'NexusFleet.TokenMissingAdminScope*'
    }
}
