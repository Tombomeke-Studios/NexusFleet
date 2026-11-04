# tests/transports — tests for src/transports

| File | How |
|---|---|
| `Invoke-NexusHostCommand.Tests.ps1` | With `Invoke-NexusSshClient` mocked: the exact ssh arguments, validation of host and user names, secrets as stdin bytes, and how exit 255 and stderr are read |
| `Invoke-NexusHostCommand.Integration.Tests.ps1` | Against the E1 lab container with the real `ssh` (tag `Integration`). Covers: a command with its output and exit code, a failing command, `sudo`, one and several secrets over stdin that arrive byte for byte, and a refused key that never waits for input |

The integration file is the only proof that the wrapper around `ssh` really works. A mock of a native program cannot
see what is piped into it.
