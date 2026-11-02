<#
.SYNOPSIS
Experiment E1: compares native ssh, PowerShell remoting over SSH and Posh-SSH against the lab targets.

.DESCRIPTION
Run ./lab/E1-transport/Start-LabTarget.ps1 first. For every transport the script measures:
  - Connect   : time to open a connection (or, for ssh, one complete call)
  - 10 calls  : average time per command over 10 commands
  - ExitCode  : whether a failing command's exit code (7) comes back
  - Stdin     : whether a secret sent on stdin arrives intact (compared by SHA-256)
  - WrongKey  : what happens with a key the host does not accept
  - Unreachable: what happens with an address that does not answer (connect time-out 5 s)
Every call that could hang runs in a thread job with a time-out, so a waiting prompt is reported as
"hangs" instead of blocking the experiment.

The targets are addressed as 127.0.0.1, not localhost: on this Windows machine "localhost" first tries
IPv6 (::1), which costs about 2 s per connection because the lab ports listen on IPv4 only.

.EXAMPLE
./lab/E1-transport/Measure-Transport.ps1 | Format-Table -AutoSize
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$Calls = 10,

    [ValidateRange(5, 120)]
    [int]$GuardSeconds = 30
)

$keyFolder = Join-Path -Path $PSScriptRoot -ChildPath '.keys'
$key = Join-Path -Path $keyFolder -ChildPath 'id_ed25519'
$wrongKey = Join-Path -Path $keyFolder -ChildPath 'wrong_ed25519'
$knownHosts = Join-Path -Path $keyFolder -ChildPath 'known_hosts'
$unreachable = '10.255.255.1'
$secret = 'S3cr3t-value-for-E1'
$secretHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($secret))) -Algorithm SHA256).Hash.ToLower()

# Runs a script block in a thread job and stops waiting after $GuardSeconds.
function Invoke-Guarded {
    param([scriptblock]$ScriptBlock, [object[]]$ArgumentList, [int]$TimeoutSeconds)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $job = Start-ThreadJob -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    $finished = Wait-Job -Job $job -Timeout $TimeoutSeconds
    $stopwatch.Stop()
    if (-not $finished) {
        Stop-Job -Job $job
        Remove-Job -Job $job -Force
        return [pscustomobject]@{ Seconds = $stopwatch.Elapsed.TotalSeconds; Output = "hangs (> $TimeoutSeconds s)" }
    }
    $output = try {
        Receive-Job -Job $job -ErrorAction Stop
    }
    catch {
        # -ErrorAction Stop wraps the real error; show the original message.
        $original = if ($_.Exception.ErrorRecord) { $_.Exception.ErrorRecord.Exception } else { $_.Exception }
        "error: $($original.Message)"
    }
    Remove-Job -Job $job -Force
    [pscustomobject]@{ Seconds = $stopwatch.Elapsed.TotalSeconds; Output = ($output -join ' ') }
}

function ConvertTo-E1Row {
    param([string]$Transport, [string]$Test, [double]$Seconds, [string]$Result)
    [pscustomobject]@{
        Transport = $Transport
        Test      = $Test
        Seconds   = [math]::Round($Seconds, 3)
        Result    = if ($Result.Length -gt 90) { $Result.Substring(0, 90) + '...' } else { $Result }
    }
}

# --- Native ssh -------------------------------------------------------------------------------
$sshOptions = @('-p', '2222', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
    '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$knownHosts")

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$null = ssh -i $key @sshOptions fleet@127.0.0.1 'true'
ConvertTo-E1Row -Transport 'ssh' -Test 'Connect' -Seconds $stopwatch.Elapsed.TotalSeconds -Result "exit $LASTEXITCODE (one full call)"

$stopwatch.Restart()
foreach ($i in 1..$Calls) { $null = ssh -i $key @sshOptions fleet@127.0.0.1 'true' }
ConvertTo-E1Row -Transport 'ssh' -Test "$Calls calls" -Seconds ($stopwatch.Elapsed.TotalSeconds / $Calls) -Result 'new connection per call'

$null = ssh -i $key @sshOptions fleet@127.0.0.1 'exit 7'
ConvertTo-E1Row -Transport 'ssh' -Test 'ExitCode' -Seconds 0 -Result "LASTEXITCODE = $LASTEXITCODE"

# A string piped to a native command gets [Environment]::NewLine appended: CRLF on Windows.
$received = $secret | ssh -i $key @sshOptions fleet@127.0.0.1 'IFS= read -r s; printf %s "$s" | sha256sum | cut -d" " -f1'
ConvertTo-E1Row -Transport 'ssh' -Test 'Stdin (string)' -Seconds 0 -Result $(if ($received -eq $secretHash) { 'secret arrived intact' } else { 'WRONG: a string pipe appends CR+LF on Windows' })

# Piping bytes (PowerShell 7.4+) sends exactly these bytes, without a line ending.
$bytes = [System.Text.Encoding]::UTF8.GetBytes($secret)
$received = $bytes | ssh -i $key @sshOptions fleet@127.0.0.1 'IFS= read -r s; printf %s "$s" | sha256sum | cut -d" " -f1'
ConvertTo-E1Row -Transport 'ssh' -Test 'Stdin (byte[])' -Seconds 0 -Result $(if ($received -eq $secretHash) { 'secret arrived intact' } else { "mismatch: $received" })

$guarded = Invoke-Guarded -TimeoutSeconds $GuardSeconds -ArgumentList $wrongKey, $sshOptions -ScriptBlock {
    param($wrongKey, $sshOptions)
    $text = ssh -i $wrongKey @sshOptions fleet@127.0.0.1 'true' 2>&1
    "exit $LASTEXITCODE; $text"
}
ConvertTo-E1Row -Transport 'ssh' -Test 'WrongKey' -Seconds $guarded.Seconds -Result $guarded.Output

$guarded = Invoke-Guarded -TimeoutSeconds $GuardSeconds -ArgumentList $key, $unreachable, $knownHosts -ScriptBlock {
    param($key, $unreachable, $knownHosts)
    $text = ssh -i $key -o BatchMode=yes -o ConnectTimeout=5 -o "UserKnownHostsFile=$knownHosts" "fleet@$unreachable" 'true' 2>&1
    "exit $LASTEXITCODE; $text"
}
ConvertTo-E1Row -Transport 'ssh' -Test 'Unreachable' -Seconds $guarded.Seconds -Result $guarded.Output

# --- PowerShell remoting over SSH --------------------------------------------------------------
$psrOptions = @{ StrictHostKeyChecking = 'accept-new'; UserKnownHostsFile = $knownHosts; BatchMode = 'yes' }

$stopwatch.Restart()
$session = New-PSSession -HostName 127.0.0.1 -Port 2223 -UserName fleet -KeyFilePath $key -Options $psrOptions -ErrorAction Stop
ConvertTo-E1Row -Transport 'PSRemoting' -Test 'Connect' -Seconds $stopwatch.Elapsed.TotalSeconds -Result "session state: $($session.State)"

$stopwatch.Restart()
foreach ($i in 1..$Calls) { $null = Invoke-Command -Session $session -ScriptBlock { $true } }
ConvertTo-E1Row -Transport 'PSRemoting' -Test "$Calls calls" -Seconds ($stopwatch.Elapsed.TotalSeconds / $Calls) -Result 'one session reused'

$code = Invoke-Command -Session $session -ScriptBlock { bash -c 'exit 7'; $LASTEXITCODE }
ConvertTo-E1Row -Transport 'PSRemoting' -Test 'ExitCode' -Seconds 0 -Result "remote LASTEXITCODE returned as object = $code"

$received = Invoke-Command -Session $session -ScriptBlock {
    $using:secret | bash -c 'IFS= read -r s; printf %s "$s" | sha256sum | cut -d" " -f1'
}
ConvertTo-E1Row -Transport 'PSRemoting' -Test 'Stdin (argument)' -Seconds 0 -Result $(if ($received -eq $secretHash) { 'secret arrived intact (argument -> stdin on host)' } else { "mismatch: $received" })
Remove-PSSession -Session $session

$guarded = Invoke-Guarded -TimeoutSeconds $GuardSeconds -ArgumentList $wrongKey, $psrOptions -ScriptBlock {
    param($wrongKey, $psrOptions)
    $s = New-PSSession -HostName 127.0.0.1 -Port 2223 -UserName fleet -KeyFilePath $wrongKey -Options $psrOptions -ErrorAction Stop
    "connected?! $($s.State)"
}
ConvertTo-E1Row -Transport 'PSRemoting' -Test 'WrongKey' -Seconds $guarded.Seconds -Result $guarded.Output

$guarded = Invoke-Guarded -TimeoutSeconds $GuardSeconds -ArgumentList $key, $unreachable, $psrOptions -ScriptBlock {
    param($key, $unreachable, $psrOptions)
    $s = New-PSSession -HostName $unreachable -UserName fleet -KeyFilePath $key -Options $psrOptions -ConnectingTimeout 5000 -ErrorAction Stop
    "connected?! $($s.State)"
}
ConvertTo-E1Row -Transport 'PSRemoting' -Test 'Unreachable' -Seconds $guarded.Seconds -Result $guarded.Output

# --- Posh-SSH ----------------------------------------------------------------------------------
Import-Module -Name Posh-SSH -ErrorAction Stop
$credential = [pscredential]::new('fleet', [securestring]::new())

$stopwatch.Restart()
$ssh = New-SSHSession -ComputerName 127.0.0.1 -Port 2222 -Credential $credential -KeyFile $key -AcceptKey -ConnectionTimeout 5 -ErrorAction Stop
ConvertTo-E1Row -Transport 'Posh-SSH' -Test 'Connect' -Seconds $stopwatch.Elapsed.TotalSeconds -Result "connected: $($ssh.Connected)"

$stopwatch.Restart()
foreach ($i in 1..$Calls) { $null = Invoke-SSHCommand -SSHSession $ssh -Command 'true' }
ConvertTo-E1Row -Transport 'Posh-SSH' -Test "$Calls calls" -Seconds ($stopwatch.Elapsed.TotalSeconds / $Calls) -Result 'one session reused'

$result = Invoke-SSHCommand -SSHSession $ssh -Command 'exit 7'
ConvertTo-E1Row -Transport 'Posh-SSH' -Test 'ExitCode' -Seconds 0 -Result "ExitStatus = $($result.ExitStatus)"

$stdinParameter = (Get-Command -Name Invoke-SSHCommand).Parameters.Keys | Where-Object { $_ -match 'Input|Stdin' }
ConvertTo-E1Row -Transport 'Posh-SSH' -Test 'Stdin' -Seconds 0 -Result $(if ($stdinParameter) { "parameter: $stdinParameter" } else { 'Invoke-SSHCommand has no stdin parameter (only a shell stream)' })
$null = Remove-SSHSession -SSHSession $ssh

$guarded = Invoke-Guarded -TimeoutSeconds $GuardSeconds -ArgumentList $wrongKey, $credential -ScriptBlock {
    param([string]$wrongKey, [pscredential]$credential)
    Import-Module -Name Posh-SSH
    $s = New-SSHSession -ComputerName 127.0.0.1 -Port 2222 -Credential $credential -KeyFile $wrongKey -AcceptKey -ConnectionTimeout 5 -ErrorAction Stop
    "connected?! $($s.Connected)"
}
ConvertTo-E1Row -Transport 'Posh-SSH' -Test 'WrongKey' -Seconds $guarded.Seconds -Result $guarded.Output

$guarded = Invoke-Guarded -TimeoutSeconds $GuardSeconds -ArgumentList $key, $unreachable, $credential -ScriptBlock {
    param([string]$key, [string]$unreachable, [pscredential]$credential)
    Import-Module -Name Posh-SSH
    $s = New-SSHSession -ComputerName $unreachable -Credential $credential -KeyFile $key -AcceptKey -ConnectionTimeout 5 -ErrorAction Stop
    "connected?! $($s.Connected)"
}
ConvertTo-E1Row -Transport 'Posh-SSH' -Test 'Unreachable' -Seconds $guarded.Seconds -Result $guarded.Output
