# Preflight

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: `Test-NexusHost` (#35, #36), de eerste parallelle cmdlet._

## 1. Wat het doet

Voordat NexusFleet iets op een server installeert, controleert `Test-NexusHost` of die server er klaar voor is:
kunnen we erbij, mogen we inloggen, is het een ondersteund besturingssysteem, mag de gebruiker `sudo`, is er genoeg
schijfruimte, staat Docker er al, en kan de server de broker van NexusInfra bereiken. Dat gebeurt voor veel servers
tegelijk, en elke server krijgt zijn eigen resultaat. Er wordt niets veranderd.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `src/public/Test-NexusHost.ps1` | De cmdlet: de dunne parallelle schil |
| `src/core/Invoke-NexusHostPreflight.ps1` | Het werk voor één server (wordt rechtstreeks getest) |
| `src/core/ConvertTo-NexusPreflightFailure.ps1` | Maakt van een onverwachte fout een mislukt resultaat |
| `config/nexusinfra.psd1` | `Broker`, `Ssh`, `Preflight` (drempels, `ThrottleLimit`) |
| `tests/core/Invoke-NexusHostPreflight.Tests.ps1` | 13 tests met een nep-transport |
| `tests/public/Test-NexusHost.Tests.ps1` | 6 tests, waaronder 100 gegenereerde servers |
| `tests/public/Test-NexusHost.LocalSsh.Tests.ps1` | 3 tests: echte runspaces en echte `ssh` naar gesloten poorten (draait in CI) |
| `tests/public/Test-NexusHost.Integration.Tests.ps1` | 3 tests tegen de lab-container |

## 3. Hoe het werkt

```powershell
Import-NexusInventory ./config/inventory.json | Test-NexusHost
```

**`Test-NexusHost`:**

1. `process` verzamelt de servers uit de pijplijn in een lijst. Er gebeurt nog niets: het parallelle werk kan pas
   beginnen als alle servers bekend zijn.
2. `end` leest de configuratie, start een run (RunId, logmap) en geeft alle servers aan de gedeelde lus
   `Invoke-NexusHostLoop`, met `Invoke-NexusHostPreflight` als werk per server en `ConvertTo-NexusPreflightFailure` voor
   een server waarbij iets misgaat. De lus kiest:
   - **`-ThrottleLimit 1`:** een gewone `foreach`, in volgorde, in de eigen runspace;
   - **anders:** `ForEach-Object -Parallel -ThrottleLimit N`, met de module ingeladen in elke runspace.

   Hoe die lus werkt, staat in [gedeelde-hulpfuncties.md](gedeelde-hulpfuncties.md).
3. De lus werkt de voortgangsbalk bij en geeft één resultaat per server. Daarna een samenvatting in `run.log`, en de
   resultaten gaan de pijplijn in.

**`Invoke-NexusHostPreflight`** (één server):

1. **`ssh ... true`.** Lukt dat niet (exitcode 255): staat er "Permission denied", dan antwoordt de server maar
   weigert hij de sleutel (`SshAuth` faalt); anders is hij onbereikbaar (`Reachable` faalt). Dan stopt het hier.
2. **Eén `ssh`-oproep met een klein bash-script** dat alle feiten als `sleutel=waarde` afdrukt:

   ```bash
   . /etc/os-release; echo "os=${ID:-unknown}" ...
   if sudo -n true 2>/dev/null; then echo "sudo=yes"; else echo "sudo=no"; fi
   echo "diskfreemb=$(df -Pm / | awk 'NR==2 {print $4}')"
   if command -v docker ...; then echo "docker=$(docker --version)"; else echo "docker="; fi
   if timeout 3 bash -c '</dev/tcp/BROKER/5672'; then echo "broker=yes"; else echo "broker=no"; fi
   ```

   PowerShell splitst de regels op `=` in een hashtable en beoordeelt elk feit: `Pass`, `Fail` of `Warning`.
3. **Het resultaat:** `Success` (geen enkele `Fail`), `Step` (de eerste `Fail`), `Error` (de uitleg) en alle
   `Checks`. Alles zit in een `try`: ook een onverwachte fout wordt een gewoon, mislukt resultaat.

## 4. Waarom zo

- **Het werk per server in een eigen functie, en een dunne schil.** Dat is het patroon uit E3: mocks werken niet in
  `-Parallel`, dus alle logica zit in `Invoke-NexusHostPreflight`, die volledig met mocks getest wordt. De schil doet
  bijna niets meer dan "voor elke server, tegelijk".
- **Hoe de schil dan toch getest wordt.** Op drie manieren: met `-ThrottleLimit 1` (gewone lus, mocks werken; ook de
  test met 100 gegenereerde servers waarvan er 4 falen), met **echte** runspaces en **echte** `ssh` naar gesloten
  poorten op de eigen machine (elke `ssh` faalt meteen; dat bewijst dat elke server een resultaat krijgt en de logging
  vanuit de runspaces werkt), en tegen de lab-container.
- **Eén verbinding voor alle feiten.** Zes aparte `ssh`-oproepen zouden 6 × 0,2 s kosten per server. Eén script
  doet het in één keer. De eerste oproep (`true`) blijft apart: die maakt het verschil tussen "onbereikbaar" en
  "inloggen mislukt" duidelijk, en zonder login heeft de rest geen zin.
- **Docker is een waarschuwing, geen fout.** `Install-NexusNode` installeert Docker zelf. Een server zonder Docker is
  dus wel klaar.
- **De broker vanaf de server testen.** De agent moet heartbeats naar de broker sturen; zonder broker wordt de node
  nooit *healthy* (het voorstel). Dat moet je vanaf de server testen, niet vanaf je laptop: die zit misschien in een
  ander netwerk. In de configuratie staan alleen host en poort: de volledige `RABBITMQ_URL` bevat een wachtwoord.
- **Niet blijven hangen.** `ssh` met `BatchMode` en een time-out, `timeout 3` voor de broker, en een `try` per server.
- **Resultaten zodra ze klaar zijn.** Met meerdere servers tegelijk komen snelle servers eerst. Wie de volgorde van de
  inventaris wil, gebruikt `-ThrottleLimit 1` of `Sort-Object Host`.

## 5. PowerShell-concepten

- **`begin` / `process` / `end`** (verzamelen in `process`, werken in `end`):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_methods
- **`ForEach-Object -Parallel`, `-ThrottleLimit`, `$using:`:**
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object
- **`& $module { }`** (een scriptblok in de scope van een module):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_operators#call-operator-
- **`Write-Progress`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/write-progress
- **Bash:** `/dev/tcp/host/poort` (een TCP-verbinding testen), `sudo -n` (niet om een wachtwoord vragen), `df -Pm`.

## 6. Zelf proberen

```powershell
Import-Module ./NexusFleet.psd1 -Force
Get-Help Test-NexusHost -Full

# Tegen de lab-container (./lab/E1-transport/Start-LabTarget.ps1); de sleutel en known_hosts van het lab
Set-Content ./config/nexusinfra.local.psd1 "@{ Ssh = @{ KnownHostsFile = '$PWD/lab/E1-transport/.keys/known_hosts' }; Broker = @{ Host = '127.0.0.1' } }"
$lab = [pscustomobject]@{ PSTypeName = 'NexusFleet.Host'; Name = 'node-lab'; Address = '127.0.0.1'; Port = 2222; User = 'fleet'
                          Location = 'lab'; Role = $null; KeyFile = "$PWD/lab/E1-transport/.keys/id_ed25519"; AgentUrl = $null }
$result = $lab | Test-NexusHost
$result | Format-List Host, Success, Step, Error
$result.Checks | Format-Table
Remove-Item ./config/nexusinfra.local.psd1

# De tests: logica, schaal, echte parallel, integratie
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests/core/Invoke-NexusHostPreflight.Tests.ps1, ./tests/public/Test-NexusHost*.ps1 -Output Detailed
Invoke-Pester -Path ./tests/public -TagFilter Integration -Output Detailed
```

## 7. Controlevragen

1. Waarom verzamelt `Test-NexusHost` de servers in `process` en begint hij pas in `end` te werken?
2. Hoe test je de parallelle schil als mocks niet in `-Parallel` werken? Noem de drie manieren.
3. Hoe maakt de preflight het verschil tussen "onbereikbaar" en "inloggen mislukt"?
4. Waarom is een ontbrekende Docker een waarschuwing en een onbereikbare broker een fout?
5. Waarom wordt de broker vanaf de server getest en niet vanaf de laptop van de beheerder?
