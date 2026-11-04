# E2 — how NexusFleet handles many hosts at once

**Question:** which way of working in parallel should NexusFleet use: `ForEach-Object -Parallel`, `Start-ThreadJob`
or `Start-Job`?

**Outcome:** `ForEach-Object -Parallel`, the fastest and the lightest. For 50 simulated hosts it took 2.89 s and
124 MB, against 3.36 s and 173 MB for `Start-ThreadJob`. Doing them one after the other took 26 s.
`Start-Job` starts a whole process per job and is far slower. All results:
[docs/ontwerpkeuzes.md](../../docs/ontwerpkeuzes.md#e2--parallel-werken-foreach-object--parallel-start-threadjob-of-start-job).

| File | What it is |
|---|---|
| `Measure-Concurrency.ps1` | Gives every simulated host the same work: a pause that stands in for waiting on ssh (`-WorkMilliseconds`), plus a small CPU loop. It measures each method in a fresh `pwsh` process, so memory never leaks from one run into the next. `-ThrottleLimit`, `-Repeat` (it reports the median) and `-Method` choose what runs |

```powershell
./lab/E2-concurrency/Measure-Concurrency.ps1 | Format-Table
```

Needs nothing but PowerShell 7. NexusFleet uses the result in `Invoke-NexusHostLoop` (`src/utils/`).
