# src/transports — running a command on a host

`Invoke-NexusHostCommand` runs one shell command on one host over native ssh (the choice of experiment E1): never
waiting for input, secrets on stdin, strict validation of host and user names. `Invoke-NexusSshClient` is the minimal
wrapper around `ssh` that the unit tests replace. Another transport is another file that returns the same
`NexusFleet.CommandResult`.
