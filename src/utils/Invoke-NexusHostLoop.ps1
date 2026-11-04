function Invoke-NexusHostLoop {
    <#
    .SYNOPSIS
    Runs one per-host function for many hosts, a number at a time, with a progress bar. One result per host, always.

    .DESCRIPTION
    Test-NexusHost, Install-NexusNode and Get-NexusFleetStatus do the same thing with a different function: run it
    for every host, in parallel, and never let one host stop the others. This is that loop, written once.

    Every item of -InputObject is a hashtable with the parameters for one host (at least HostInfo). The shared
    parameters of -Parameter are added to it, and the function -FunctionName is called with the result.

    - -ThrottleLimit 1 runs the hosts one after the other in this runspace. Pester mocks work there (E3), so the unit
      tests of the cmdlets use it.
    - A higher -ThrottleLimit uses ForEach-Object -Parallel. A runspace starts empty: the module is imported there by
      path, and the function runs in the module's scope (& $module { }), because it is internal.

    When the function throws for a host, or the module cannot even be loaded in its runspace, that host still gets a
    result: -FailureFunction is called with -Message (the error) and those of the host's parameters it declares. It
    runs in this runspace, after the parallel work, so it always exists.

    .PARAMETER InputObject
    One hashtable per host, with that host's parameters for -FunctionName (at least HostInfo).

    .PARAMETER FunctionName
    The per-host function, for example Invoke-NexusHostPreflight. It may be internal to the module.

    .PARAMETER Parameter
    Parameters that are the same for every host (Config, RunContext, ...).

    .PARAMETER FailureFunction
    Builds the result of a host whose work failed, for example ConvertTo-NexusPreflightFailure. It is called with
    -Message and with the host's own parameters (from -InputObject) that it declares.

    .PARAMETER ThrottleLimit
    How many hosts at the same time. 1 means one after the other, in this runspace.

    .PARAMETER Activity
    The title of the progress bar, for example 'NexusFleet preflight'.

    .EXAMPLE
    $items = $hosts | ForEach-Object { @{ HostInfo = $_ } }
    Invoke-NexusHostLoop -InputObject $items -FunctionName Invoke-NexusHostPreflight -Parameter @{ Config = $config } `
        -FailureFunction ConvertTo-NexusPreflightFailure -ThrottleLimit 10 -Activity 'NexusFleet preflight'

    Checks ten hosts at a time and returns one NexusFleet.PreflightResult per host.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'FunctionName, Parameter and ThrottleLimit are used inside the & { } block; the analyzer does not look there.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable[]]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FunctionName,

        [hashtable]$Parameter = @{},

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FailureFunction,

        [Parameter(Mandatory)]
        [ValidateRange(1, 256)]
        [int]$ThrottleLimit,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Activity
    )

    $total = $InputObject.Count
    if ($total -eq 0) {
        return
    }

    # Both paths return, per host, either the function's result or a failure marker with the error. They are wrapped
    # in & { } and piped on (not assigned to a variable first), so every answer reaches the progress bar below as soon
    # as its host is done.
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1'
    $failureParameters = @((Get-Command -Name $FailureFunction).Parameters.Keys)
    $done = 0
    & {
        if ($ThrottleLimit -eq 1) {
            foreach ($item in $InputObject) {
                try {
                    $splat = $Parameter + $item
                    & $FunctionName @splat
                }
                catch {
                    [pscustomobject]@{ PSTypeName = 'NexusFleet.HostLoopFailure'; Item = $item; Message = $_.Exception.Message }
                }
            }
        }
        else {
            $InputObject | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                $item = $_
                try {
                    $module = Import-Module -Name $using:manifest -PassThru -ErrorAction Stop
                    $splat = $using:Parameter + $item
                    & $module {
                        param($Name, $Splat)
                        & $Name @Splat
                    } $using:FunctionName $splat
                }
                catch {
                    [pscustomobject]@{ PSTypeName = 'NexusFleet.HostLoopFailure'; Item = $item; Message = $_.Exception.Message }
                }
            }
        }
    } | ForEach-Object {
        $done++
        Write-Progress -Activity $Activity -Status "$done of $total hosts done" -PercentComplete ([math]::Floor(100 * $done / $total))
        if ($_.PSObject.TypeNames -contains 'NexusFleet.HostLoopFailure') {
            # A marker becomes a real result here, in this runspace, where the failure function always exists. It gets
            # only the host parameters it declares (HostInfo, and PlanOnly for an install), and the error.
            $failed = @{}
            foreach ($key in $_.Item.Keys) {
                if ($failureParameters -contains $key) { $failed[$key] = $_.Item[$key] }
            }
            & $FailureFunction @failed -Message $_.Message
        }
        else {
            $_
        }
    }
    Write-Progress -Activity $Activity -Completed
}
