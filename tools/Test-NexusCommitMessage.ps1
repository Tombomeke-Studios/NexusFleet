<#
.SYNOPSIS
Checks commit messages (or a pull request title) against the commit rules of CLAUDE.md, section 3.

.DESCRIPTION
The first line must read "type(scope): summary":
  - type   one of feat, fix, docs, chore, refactor, test, ci;
  - scope  one of core, steps, transport, api, public, log, config, tests, docs, ci, lab;
  - summary does not end with a full stop, and the whole line is at most 100 characters (the limit commitlint
    uses; GitHub cuts longer titles off).
A capital at the start is allowed: summaries often start with a name (E3, Invoke-NexusApi).
The merge commits git and GitHub write themselves ("Merge pull request ...", "Merge branch ...") are accepted.
Only the first line is checked: the body may say anything.

Returns one result per message: Message (its first line), Valid, Reason (why not, or empty). It never throws on an
invalid message, so the caller decides what to do; CI fails the job when a result is not valid.

.PARAMETER Message
The messages to check, for example a pull request title. Also from the pipeline.

.PARAMETER Range
A git range such as origin/dev..HEAD: every commit in it is checked, the oldest first, merge commits left out.
Run inside the repository.

.EXAMPLE
./tools/Test-NexusCommitMessage.ps1 -Message 'feat(steps): add a step'

Message                   Valid Reason
-------                   ----- ------
feat(steps): add a step   True

.EXAMPLE
./tools/Test-NexusCommitMessage.ps1 -Range origin/dev..HEAD | Where-Object { -not $_.Valid }

Lists the commits of your branch that do not follow the rules, before you open a pull request.
#>
[CmdletBinding(DefaultParameterSetName = 'Message')]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory, ParameterSetName = 'Message', ValueFromPipeline)]
    [AllowEmptyString()]
    [string[]]$Message,

    [Parameter(Mandatory, ParameterSetName = 'Range')]
    [ValidateNotNullOrEmpty()]
    [string]$Range
)

begin {
    # The same lists as CLAUDE.md, section 3. A new scope is added here and there together.
    $types = 'feat', 'fix', 'docs', 'chore', 'refactor', 'test', 'ci'
    $scopes = 'core', 'steps', 'transport', 'api', 'public', 'log', 'config', 'tests', 'docs', 'ci', 'lab'
    $maxLength = 100

    # Returns why a first line breaks the rules, or $null when it does not.
    $findProblem = {
        param([string]$Line)
        if ($Line -match '^Merge (pull request|branch|remote-tracking branch) ') {
            return $null
        }
        if ($Line -notmatch '^(?<type>[a-z]+)\((?<scope>[a-z]+)\): (?<summary>\S.*)$') {
            return "it does not read 'type(scope): summary'"
        }
        if ($Matches.type -notin $types) {
            return "type '$($Matches.type)' is not one of $($types -join ', ')"
        }
        if ($Matches.scope -notin $scopes) {
            return "scope '$($Matches.scope)' is not one of $($scopes -join ', ')"
        }
        if ($Matches.summary.EndsWith('.')) {
            return 'the summary ends with a full stop'
        }
        if ($Line.Length -gt $maxLength) {
            return "the first line is $($Line.Length) characters, at most $maxLength"
        }
        $null
    }

    $check = {
        param([string]$Text)
        $line = ($Text -split '\r?\n', 2)[0].Trim()
        $problem = & $findProblem $line
        [pscustomobject]@{
            PSTypeName = 'NexusFleet.CommitMessageCheck'
            Message    = $line
            Valid      = $null -eq $problem
            Reason     = $problem
        }
    }
}

process {
    foreach ($text in $Message) {
        & $check $text
    }
}

end {
    if ($PSCmdlet.ParameterSetName -eq 'Range') {
        # %s is the first line of each commit; --reverse puts the oldest first, in the order they were made.
        # --no-merges: a merge commit only joins two lines of work, whatever its message says.
        $subjects = @(git log --reverse --no-merges --format=%s $Range)
        if ($LASTEXITCODE -ne 0) {
            throw "git log failed for the range '$Range'."
        }
        foreach ($subject in $subjects) {
            & $check $subject
        }
    }
}
