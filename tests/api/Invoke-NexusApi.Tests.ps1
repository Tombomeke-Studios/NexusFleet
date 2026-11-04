[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: a fake token, never a real secret.')]
param()

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/api/Invoke-NexusApi.ps1')

    $plainToken = 'nxi_FakeTokenForTests123'
    $token = ConvertTo-SecureString -String $plainToken -AsPlainText -Force
    # Most tests use https; the 'unencrypted http' tests use $api, which is http to another host.
    $https = @{ BaseUrl = 'https://panel.test'; Token = $token; RetryDelayMilliseconds = 0 }
    $api = @{ BaseUrl = 'http://panel.test:9400'; Token = $token; RetryDelayMilliseconds = 0 }

    # Builds the error Invoke-RestMethod throws for an HTTP error status, including the JSON body
    # NexusInfra sends ({ "error": "..." }), which PowerShell puts in ErrorDetails.
    function Get-TestHttpError {
        param([int]$Status, [string]$ServerMessage = 'server says no')
        $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
        $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Status.", $response)
        $record = [System.Management.Automation.ErrorRecord]::new($exception, 'WebCmdletWebResponseException', 'InvalidOperation', $null)
        $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new("{""error"":""$ServerMessage""}")
        $record
    }
}

Describe 'Invoke-NexusApi' {
    BeforeEach {
        $state = @{ Calls = 0 }
        Mock -CommandName Start-Sleep -MockWith { }
    }

    Context 'successful requests' {
        It 'sends a GET with the bearer token, the time-out and the full URL, and returns the answer' {
            Mock -CommandName Invoke-RestMethod -MockWith { @([pscustomobject]@{ id = 'node-a' }) }

            $result = Invoke-NexusApi @https -Method GET -Path '/nodes' -TimeoutSeconds 15

            $result.id | Should -Be 'node-a'
            Should -Invoke -CommandName Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and $Uri -eq 'https://panel.test/nodes' -and
                $Authentication -eq 'Bearer' -and $Token -is [securestring] -and $TimeoutSec -eq 15
            }
        }

        It 'does not double the slash when the base URL ends with one' {
            Mock -CommandName Invoke-RestMethod -MockWith { }

            Invoke-NexusApi -BaseUrl 'https://panel.test/' -Token $token -Method GET -Path '/me'

            Should -Invoke -CommandName Invoke-RestMethod -ParameterFilter { $Uri -eq 'https://panel.test/me' }
        }

        It 'sends a body as JSON' {
            Mock -CommandName Invoke-RestMethod -MockWith { }

            Invoke-NexusApi @https -Method POST -Path '/nodes' -Body @{ id = 'node-a'; agentUrl = 'http://10.0.0.5:9100' }

            Should -Invoke -CommandName Invoke-RestMethod -ParameterFilter {
                $ContentType -eq 'application/json' -and ($Body | ConvertFrom-Json).agentUrl -eq 'http://10.0.0.5:9100'
            }
        }
    }

    Context 'HTTP errors become clear errors' {
        It 'turns <Status> into error id <ErrorId> with an explanation and the server message' -ForEach @(
            @{ Status = 401; ErrorId = 'NexusApi.Unauthorized'; Text = '*401*token*invalid*expired*' }
            @{ Status = 403; ErrorId = 'NexusApi.Forbidden'; Text = '*403*permission*' }
            @{ Status = 404; ErrorId = 'NexusApi.NotFound'; Text = '*404*not found*' }
            @{ Status = 409; ErrorId = 'NexusApi.Conflict'; Text = '*409*conflict*' }
            @{ Status = 429; ErrorId = 'NexusApi.RateLimited'; Text = '*429*rate limit*' }
            @{ Status = 503; ErrorId = 'NexusApi.Unavailable'; Text = '*503*temporarily unavailable*' }
            @{ Status = 500; ErrorId = 'NexusApi.HttpError'; Text = '*500*unexpected answer from the panel*' }
            @{ Status = 400; ErrorId = 'NexusApi.HttpError'; Text = '*400*unexpected answer from the panel*' }
        ) {
            Mock -CommandName Invoke-RestMethod -MockWith { throw (Get-TestHttpError -Status $Status -ServerMessage 'detail from NexusInfra') }

            { Invoke-NexusApi @https -Method GET -Path '/nodes/x' } |
                Should -Throw -ErrorId "$ErrorId*" -ExpectedMessage $Text
            { Invoke-NexusApi @https -Method GET -Path '/nodes/x' } |
                Should -Throw -ExpectedMessage '*detail from NexusInfra*'
        }

        It 'shows NexusInfra''s answer as it is when it is not JSON' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                $record = Get-TestHttpError -Status 502
                $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('<html>Bad Gateway</html>')
                throw $record
            }

            { Invoke-NexusApi @https -Method POST -Path '/nodes' } | Should -Throw -ErrorId 'NexusApi.Unavailable*' -ExpectedMessage '*<html>Bad Gateway</html>*'
        }
        It 'does not retry a 403, because asking again will not help' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw (Get-TestHttpError -Status 403) }

            { Invoke-NexusApi @https -Method GET -Path '/nodes' -RetryCount 2 } | Should -Throw
            Should -Invoke -CommandName Invoke-RestMethod -Times 1 -Exactly
        }

        It 'never puts the token in an error message' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw (Get-TestHttpError -Status 401) }

            $message = try { Invoke-NexusApi @https -Method GET -Path '/me'; '' } catch { $_.Exception.Message }

            $message | Should -Not -BeNullOrEmpty
            $message | Should -Not -Match ([regex]::Escape($plainToken))
        }
    }

    Context 'retries' {
        It 'retries a GET after a network error and returns the answer when it works again' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                $state.Calls++
                if ($state.Calls -le 2) { throw [System.Net.Http.HttpRequestException]::new('No such host is known.') }
                'ok'
            }

            Invoke-NexusApi @https -Method GET -Path '/nodes' -RetryCount 2 | Should -Be 'ok'
            Should -Invoke -CommandName Invoke-RestMethod -Times 3 -Exactly
        }

        It 'retries a GET after 503 (service unavailable)' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                $state.Calls++
                if ($state.Calls -eq 1) { throw (Get-TestHttpError -Status 503) }
                'ok'
            }

            Invoke-NexusApi @https -Method GET -Path '/nodes' -RetryCount 1 | Should -Be 'ok'
        }

        It 'retries a GET after 429 (the gateway''s rate limit), so many hosts polling at once do not fail' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                $state.Calls++
                if ($state.Calls -eq 1) { throw (Get-TestHttpError -Status 429) }
                'ok'
            }

            Invoke-NexusApi @https -Method GET -Path '/nodes' -RetryCount 1 | Should -Be 'ok'
            Should -Invoke -CommandName Invoke-RestMethod -Times 2 -Exactly
        }

        It 'never retries a changing request (POST) after 429' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw (Get-TestHttpError -Status 429) }

            { Invoke-NexusApi @https -Method POST -Path '/nodes' -Body @{ id = 'a' } -RetryCount 2 } | Should -Throw -ErrorId 'NexusApi.RateLimited*'
            Should -Invoke -CommandName Invoke-RestMethod -Times 1 -Exactly
        }

        It 'gives up after RetryCount extra attempts and says the panel is unreachable' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw [System.Net.Http.HttpRequestException]::new('No such host is known.') }

            { Invoke-NexusApi @https -Method GET -Path '/nodes' -RetryCount 2 } |
                Should -Throw -ErrorId 'NexusApi.Unreachable*' -ExpectedMessage '*cannot reach*panel.test*3 attempt*'
            Should -Invoke -CommandName Invoke-RestMethod -Times 3 -Exactly
        }

        It 'does not present PowerShell''s text as a message from NexusInfra when there was no HTTP answer' {
            # PowerShell also fills ErrorDetails for network errors; that is not NexusInfra speaking.
            Mock -CommandName Invoke-RestMethod -MockWith {
                $record = [System.Management.Automation.ErrorRecord]::new(
                    [System.Net.Http.HttpRequestException]::new('Connection refused.'), 'WebCmdletWebResponseException', 'ConnectionError', $null)
                $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('Connection refused.')
                throw $record
            }

            $message = try { Invoke-NexusApi @https -Method GET -Path '/nodes' -RetryCount 0; '' } catch { $_.Exception.Message }

            $message | Should -Match 'Connection refused'
            $message | Should -Not -Match 'NexusInfra says'
        }

        It 'includes the reason of the network error in the message' {
            # Regression: inside a switch block $_ is the switch value, not the caught error,
            # so the reason came out empty ("...after 1 attempt(s): .").
            Mock -CommandName Invoke-RestMethod -MockWith { throw [System.Net.Http.HttpRequestException]::new('No such host is known.') }

            { Invoke-NexusApi @https -Method GET -Path '/nodes' -RetryCount 0 } |
                Should -Throw -ExpectedMessage '*attempt(s): No such host is known.*'
        }

        It 'never retries a changing request (POST), even after a network error' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw [System.Net.Http.HttpRequestException]::new('Connection reset.') }

            { Invoke-NexusApi @https -Method POST -Path '/nodes' -Body @{ id = 'a' } -RetryCount 2 } | Should -Throw -ErrorId 'NexusApi.Unreachable*'
            Should -Invoke -CommandName Invoke-RestMethod -Times 1 -Exactly
        }
    }

    Context 'unencrypted http' {
        It 'allows http:// to the own machine (<BaseUrl>) and tells Invoke-RestMethod so' -ForEach @(
            @{ BaseUrl = 'http://localhost:9400' }
            @{ BaseUrl = 'http://127.0.0.1:9400' }
            @{ BaseUrl = 'http://[::1]:9400' }
        ) {
            Mock -CommandName Invoke-RestMethod -MockWith { }

            Invoke-NexusApi -BaseUrl $BaseUrl -Token $token -Method GET -Path '/me'

            Should -Invoke -CommandName Invoke-RestMethod -ParameterFilter { $AllowUnencryptedAuthentication -eq $true }
        }

        It 'refuses http:// to another host unless it is allowed, before anything is sent' {
            Mock -CommandName Invoke-RestMethod -MockWith { }

            { Invoke-NexusApi @api -Method GET -Path '/me' } |
                Should -Throw -ErrorId 'NexusApi.UnencryptedNotAllowed*' -ExpectedMessage '*http://panel.test:9400*AllowUnencryptedHttp*'
            Should -Invoke -CommandName Invoke-RestMethod -Times 0 -Exactly
        }

        It 'sends over http:// to another host when allowed, with a warning' {
            Mock -CommandName Invoke-RestMethod -MockWith { }

            Invoke-NexusApi @api -Method GET -Path '/me' -AllowUnencryptedHttp -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings | Should -HaveCount 1
            "$($warnings[0])" | Should -Match 'unencrypted'
            Should -Invoke -CommandName Invoke-RestMethod -ParameterFilter { $AllowUnencryptedAuthentication -eq $true }
        }

        It 'never needs the exception for https://' {
            Mock -CommandName Invoke-RestMethod -MockWith { }

            Invoke-NexusApi -BaseUrl 'https://panel.test' -Token $token -Method GET -Path '/me'

            Should -Invoke -CommandName Invoke-RestMethod -ParameterFilter { -not $AllowUnencryptedAuthentication }
        }
    }

    Context 'other failures' {
        It 'does not call an error that is not a network error "unreachable", and does not retry it' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw [System.InvalidOperationException]::new('Something else went wrong.') }

            { Invoke-NexusApi @https -Method GET -Path '/nodes' -RetryCount 2 } |
                Should -Throw -ErrorId 'NexusApi.RequestFailed*' -ExpectedMessage '*Something else went wrong.*'
            Should -Invoke -CommandName Invoke-RestMethod -Times 1 -Exactly
        }

        It 'treats a time-out as a network error and retries it' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                $state.Calls++
                if ($state.Calls -eq 1) { throw [System.Threading.Tasks.TaskCanceledException]::new('The request was canceled due to the configured HttpClient.Timeout.') }
                'ok'
            }

            Invoke-NexusApi @https -Method GET -Path '/nodes' -RetryCount 1 | Should -Be 'ok'
        }
    }

    Context 'parameter validation' {
        It 'refuses a base URL without http(s)://' {
            { Invoke-NexusApi -BaseUrl 'panel.test' -Token $token -Method GET -Path '/nodes' } | Should -Throw
        }

        It 'refuses a path that does not start with /' {
            { Invoke-NexusApi @https -Method GET -Path 'nodes' } | Should -Throw
        }

        It 'refuses an unknown HTTP method' {
            { Invoke-NexusApi @https -Method FETCH -Path '/nodes' } | Should -Throw
        }
    }
}
