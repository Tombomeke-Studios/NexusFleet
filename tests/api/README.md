# tests/api — tests for src/api

| File | How |
|---|---|
| `Invoke-NexusApi.Tests.ps1` | With `Invoke-RestMethod` mocked: every HTTP status becomes its error id, only `GET` is retried, and the token never goes over `http://` to another machine |
| `Invoke-NexusApi.LocalHttp.Tests.ps1` | Against a real `HttpListener` on a free loopback port (tag `LocalHttp`). This found three bugs that a mock could not show |

No test reaches an outside host.
