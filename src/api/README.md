# src/api — the NexusInfra REST API

`Invoke-NexusApi` is the only function in NexusFleet that calls the NexusInfra API. It sends the API token as a
bearer token (kept as a SecureString), with a time-out; it repeats only GET requests after a network error or a
502/503/504, and turns HTTP errors into errors with their own id (`NexusApi.Unauthorized`, `Forbidden`,
`NotFound`, `Conflict`, `Unavailable`, `Unreachable`, `HttpError`, `RequestFailed`,
`UnencryptedNotAllowed`). Tests: `tests/api/` (mocked, and against a real local HTTP server).
