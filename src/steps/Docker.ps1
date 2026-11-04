# Step 10: Docker Engine on the host. The agent is a container, so nothing else works without it.
Register-NexusStep -Name 'Docker' -Order 10 -Description 'Docker Engine installed and running' -Test {
    param($Context)
    # Usable means: the command exists and the daemon answers (with sudo, as every later step uses it).
    $answer = Invoke-NexusStepCommand -Context $Context -Purpose 'check Docker' -AllowFailure `
        -Command 'command -v docker >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1'
    $answer.Succeeded
} -Apply {
    param($Context)
    $package = ConvertTo-NexusShellArgument -Value $Context.Config.Docker.Package
    $lockTimeout = $Context.Config.Docker.AptLockTimeoutSeconds
    # Ubuntu's own package: no extra apt repository or key to trust. DEBIAN_FRONTEND keeps apt from asking
    # questions; the lock time-out waits for unattended-upgrades, which often runs on a fresh VM.
    # Hosts without systemd (containers in the lab) start the daemon with 'service'.
    $script = @"
set -e
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=$lockTimeout update -q
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=$lockTimeout install -y -q $package
if [ -d /run/systemd/system ]; then sudo -n systemctl enable --now docker; else sudo -n service docker start; fi
for i in 1 2 3 4 5 6 7 8 9 10; do sudo -n docker info >/dev/null 2>&1 && exit 0; sleep 1; done
echo 'Docker was installed but the daemon does not answer' >&2; exit 1
"@
    $null = Invoke-NexusStepCommand -Context $Context -Purpose 'install Docker' -Command $script
} -Rollback {
    param($Context)
    # Only runs when this run installed Docker (the runner never rolls back a step that was already in order).
    $package = ConvertTo-NexusShellArgument -Value $Context.Config.Docker.Package
    $null = Invoke-NexusStepCommand -Context $Context -Purpose 'remove Docker' `
        -Command "sudo -n env DEBIAN_FRONTEND=noninteractive apt-get remove -y -q $package"
}
