# SSH-transport

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: experiment E1 (#16). De echte functie `Invoke-NexusHostCommand` komt hier later bij (fase 2)._

## 1. Wat het doet

NexusFleet moet commando's uitvoeren op Linux-hosts: Docker installeren, de agent starten. Experiment E1
vergelijkt drie manieren om dat vanuit PowerShell te doen: het gewone `ssh`-programma, PowerShell-remoting over
SSH, en de module Posh-SSH. Als doelhost dienen twee Docker-containers die zich gedragen als een verse
Ubuntu-machine.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `lab/E1-transport/target/Dockerfile` | De "verse Ubuntu-VM": sshd, gebruiker `fleet`, alleen sleutel, sudo zonder wachtwoord |
| `lab/E1-transport/Start-LabTarget.ps1` | Maakt lab-sleutels, bouwt en start de twee containers (poort 2222 en 2223) |
| `lab/E1-transport/Measure-Transport.ps1` | Meet de drie transporten |
| `lab/E1-transport/.keys/` | Lab-sleutels en `known_hosts`, door git genegeerd |
| `docs/ontwerpkeuzes.md`, E1 en K4 | Resultaten, voorstel en de open vraag over de PowerShell-versie |

## 3. Hoe het werkt

**De doelhost.** De `Dockerfile` start van `ubuntu:24.04`, installeert `openssh-server` en `sudo`, en maakt
een gebruiker `fleet` die alleen met een sleutel binnenkomt:

```dockerfile
RUN useradd --create-home --shell /bin/bash fleet \
    && usermod --password '*' fleet \
    && echo 'fleet ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/fleet \
    ...
    && echo "$PUBKEY" > /home/fleet/.ssh/authorized_keys \
```

`--password '*'` betekent: geen wachtwoord waarmee je kunt inloggen, maar het account is ook niet
"vergrendeld" (dan zou sshd de sleutel weigeren). Met `WITH_PWSH=true` komt er PowerShell bij, plus een regel in
`sshd_config` die PowerShell-remoting mogelijk maakt. `Start-LabTarget.ps1` maakt eerst een sleutelpaar
(`ssh-keygen`), geeft de publieke sleutel als `--build-arg` mee, en start de containers alleen op `127.0.0.1`.

**Native `ssh`.** Elke oproep is een volledig `ssh`-commando met vaste opties:

```powershell
$sshOptions = @('-p', '2222', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
    '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$knownHosts")
$null = ssh -i $key @sshOptions fleet@127.0.0.1 'exit 7'
$LASTEXITCODE    # 7
```

- `BatchMode=yes`: nooit iets vragen. Zonder deze optie kan `ssh` om een wachtwoord vragen en blijft het script
  hangen.
- `ConnectTimeout=5`: na 5 seconden opgeven als de host niet antwoordt.
- `StrictHostKeyChecking=accept-new` en een eigen `UserKnownHostsFile`: een nieuwe host automatisch vertrouwen,
  maar een **gewijzigde** host key wel weigeren, en je eigen `~/.ssh/known_hosts` niet aanraken.
- `@sshOptions` is *splatting* van een array: elk element wordt een apart argument.
- `$LASTEXITCODE` bevat de exitcode van het laatste externe programma; `ssh` geeft die van het commando op de
  host door, of 255 als `ssh` zelf faalt.

**Een geheim via stdin.** Zo komt een geheim nooit op de commandoregel (waar `ps` op de host het kan tonen):

```powershell
$bytes = [System.Text.Encoding]::UTF8.GetBytes($secret)
$received = $bytes | ssh -i $key @sshOptions fleet@127.0.0.1 'IFS= read -r s; printf %s "$s" | sha256sum | cut -d" " -f1'
```

De host leest één regel van stdin, berekent er een SHA-256 van, en het script vergelijkt die met de hash van het
originele geheim. Zo bewijs je dat het geheim exact aankwam, zonder het terug te sturen.

**PowerShell-remoting** opent één sessie en hergebruikt die:

```powershell
$session = New-PSSession -HostName 127.0.0.1 -Port 2223 -UserName fleet -KeyFilePath $key -Options $psrOptions
Invoke-Command -Session $session -ScriptBlock { bash -c 'exit 7'; $LASTEXITCODE }
```

**Posh-SSH** doet hetzelfde met `New-SSHSession` en `Invoke-SSHCommand`; het resultaat heeft een `ExitStatus`.

**Niet blijven hangen.** De gevallen "verkeerde sleutel" en "onbereikbare host" draaien via `Invoke-Guarded`:
een thread job, waarop het script hoogstens `-TimeoutSeconds` wacht (`Wait-Job -Timeout`). Hangt er toch iets,
dan staat in de resultaten "hangs" in plaats van dat het experiment vastloopt.

## 4. Waarom zo

- **Native `ssh` als voorstel.** Niets te installeren op de hosts, geen externe module, geheimen via stdin, en
  duidelijke exitcodes. PowerShell-remoting vraagt PowerShell op élke host (een extra installatiestap van 87 MB
  en meer aanvalsoppervlak). Posh-SSH heeft geen stdin, dus een geheim zou op de commandoregel of in een bestand
  moeten.
- **Het nadeel van `ssh`:** een nieuwe verbinding per commando, 0,2 s tegenover 0,07–0,09 s met een hergebruikte
  sessie. Met een paar commando's per stap en hosts in parallel (E2) is dat klein.
- **Valkuil 1: `\r\n` bij een string-pijp.** Een string die je in PowerShell naar een extern programma pijpt,
  krijgt `[Environment]::NewLine` erachter, op Windows `\r\n`. `read` op Linux knipt de `\n` weg, maar laat de
  `\r` staan: het geheim is één onzichtbaar teken te lang. Een `byte[]` pijpen stuurt exact die bytes (sinds
  PowerShell 7.4). Daarom de open vraag K4 over de minimumversie.
- **Valkuil 2: `localhost` is traag.** Op deze machine probeert `localhost` eerst IPv6 (`::1`); de lab-poorten
  luisteren alleen op IPv4. Dat kost 2 s per verbinding. Daarom gebruikt het lab `127.0.0.1`.
- **Containers in plaats van wachten op een VM.** Een container met sshd gedraagt zich voor SSH zoals een verse
  VM, start in seconden en kun je weggooien. Wat een container niet kan nabootsen (Docker installeren op de host,
  een echte netwerkverbinding over het internet), komt in E0 met een echte VM.

## 5. PowerShell-concepten

- **Externe programma's aanroepen en `$LASTEXITCODE`:**
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_automatic_variables
- **Splatting** (`@sshOptions`): https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_splatting
- **Byte-pijpen naar externe programma's** (`PSNativeCommandPreserveBytePipe`, PowerShell 7.4):
  https://learn.microsoft.com/powershell/scripting/whats-new/what-s-new-in-powershell-74
- **PowerShell-remoting over SSH** (`New-PSSession -HostName`, `-KeyFilePath`, `-Options`):
  https://learn.microsoft.com/powershell/scripting/security/remoting/ssh-remoting-in-powershell
- **OpenSSH-opties** (`BatchMode`, `ConnectTimeout`, `StrictHostKeyChecking`): `man ssh_config`,
  https://man.openbsd.org/ssh_config
- **Posh-SSH:** https://github.com/darkoperator/Posh-SSH
- **`Wait-Job -Timeout`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.core/wait-job

## 6. Zelf proberen

```powershell
# Vereist Docker Desktop (aan) en Posh-SSH (Install-Module Posh-SSH -Scope CurrentUser)
./lab/E1-transport/Start-LabTarget.ps1 | Format-Table
./lab/E1-transport/Measure-Transport.ps1 | Format-Table -AutoSize

# Zelf inloggen op de lab-host
ssh -i ./lab/E1-transport/.keys/id_ed25519 -p 2222 -o UserKnownHostsFile=./lab/E1-transport/.keys/known_hosts fleet@127.0.0.1

# Opruimen
./lab/E1-transport/Start-LabTarget.ps1 -Remove
```

Zien hoe het faalt:

```powershell
$k = './lab/E1-transport/.keys'
$o = @('-i', "$k/id_ed25519", '-p', '2222', '-o', 'BatchMode=yes', '-o', "UserKnownHostsFile=$k/known_hosts")

# De \r\n-valkuil: od toont \r \n achter het geheim
'geheim' | ssh @o fleet@127.0.0.1 'od -c'
# Met bytes: geen \r en geen \n
[System.Text.Encoding]::UTF8.GetBytes('geheim') | ssh @o fleet@127.0.0.1 'od -c'

# Verkeerde sleutel: exitcode 255, geen prompt dankzij BatchMode
ssh -i "$k/wrong_ed25519" -p 2222 -o BatchMode=yes -o "UserKnownHostsFile=$k/known_hosts" fleet@127.0.0.1 true; $LASTEXITCODE

# Traag via localhost, snel via 127.0.0.1
Measure-Command { ssh @o fleet@localhost true }
Measure-Command { ssh @o fleet@127.0.0.1 true }
```

## 7. Controlevragen

1. Waarom moet `BatchMode=yes` altijd aan staan als een script `ssh` aanroept?
2. Waarom gaat een geheim via stdin en niet als argument op de commandoregel?
3. Wat gaat er mis als je een string naar `ssh` pijpt op Windows, en hoe lost een `byte[]` dat op?
4. Waarom valt PowerShell-remoting af, hoewel het per commando sneller is en objecten teruggeeft?
5. Wat doet `StrictHostKeyChecking=accept-new`, en waarom is dat veiliger dan `no`?
