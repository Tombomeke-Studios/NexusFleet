# Verbinden met NexusInfra

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: `Connect-NexusInfra` (#30), de eerste publieke cmdlet._

## 1. Wat het doet

`Connect-NexusInfra` legt de verbinding met je NexusInfra-panel. Het controleert meteen of het API-token genoeg
rechten heeft om nodes te beheren, zodat je dat nu weet en niet pas halverwege een installatie. Het token kan
bewaard worden in een kluis (SecretManagement), zodat je het niet elke keer moet intypen. De verbinding blijft
gelden voor de andere NexusFleet-cmdlets in hetzelfde PowerShell-venster.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `src/public/Connect-NexusInfra.ps1` | De cmdlet (geëxporteerd in `NexusFleet.psd1`) |
| `src/utils/Get-NexusStoredToken.ps1`, `Save-NexusStoredToken.ps1` | De enige twee functies die SecretManagement aanroepen |
| `src/utils/Get-NexusSession.ps1` | De sessie in de module, of "verbind eerst" |
| `config/nexusinfra.psd1` | `Api.BaseUrl`, `Api.SecretName` en de andere API-instellingen |
| `tests/public/Connect-NexusInfra.Tests.ps1` | 10 tests met mocks |
| `tests/public/Connect-NexusInfra.LocalHttp.Tests.ps1` | 3 tests tegen een nagebootst panel op de eigen machine |
| `tests/NexusFleet.Tests.ps1`, "Help of every exported cmdlet" | Controleert de help van elke publieke cmdlet |

## 3. Hoe het werkt

```powershell
Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save
```

1. **Configuratie en token.** Zonder `-BaseUrl` komt het adres uit de configuratie. Zonder `-Token` haalt
   `Get-NexusStoredToken` het token uit de kluis; is er geen, dan legt de fout uit hoe je er een bewaart.
2. **Een run starten.** `Initialize-NexusRunContext` krijgt het token mee als geheim, zodat het in het log
   vervangen wordt door `***`.
3. **Wie ben je?** `GET /me` geeft het account terug. Is de rol niet `admin` of `owner`, dan stopt de cmdlet met
   `NexusFleet.NotPlatformAdmin`.
4. **Heeft het token de scope `admin`?** `GET /users` is een leesroute achter dezelfde controle als de node-routes.
   `403` betekent: geen `admin`-scope → `NexusFleet.TokenMissingAdminScope`, met de uitleg welk token je moet maken.
   Een andere fout (bijvoorbeeld `401`) gaat door met zijn eigen foutcode.
5. **De sessie bewaren.** In `$script:NexusSession` komen het adres, het token, de gebruiker en de API-instellingen.
   Andere cmdlets halen die op met `Get-NexusSession`.
6. **Eventueel bewaren in de kluis.** Met `-Save` roept de cmdlet `Save-NexusStoredToken` aan, maar alleen als
   `$PSCmdlet.ShouldProcess(...)` "ja" zegt. Bij `-WhatIf` toont PowerShell "What if: ..." en wordt er niets bewaard.
7. **Uitvoer.** Een object met `BaseUrl`, `User`, `PlatformRole`, `TokenSaved` en `RunId`, en **zonder** het token.

## 4. Waarom zo

- **Vooraf controleren.** E4 toonde dat node-routes een beheerdersaccount én een token met `write` + `admin`
  vragen. Zonder die controle zou `Install-NexusNode` pas bij het registreren van de node falen, na Docker en de
  agent al geïnstalleerd te hebben. De `write`-scope kan niet gecontroleerd worden zonder iets te veranderen; dat
  staat eerlijk in de help.
- **SecretManagement in plaats van een bestand.** Een token in een bestand naast de scripts komt vroeg of laat in
  een repository of een back-up terecht. SecretManagement bewaart het versleuteld in een kluis van je keuze, en
  het blijft een `SecureString`. Het is ook de manier die het voorstel noemt.
- **Twee kleine functies rond SecretManagement.** Zo is er één plek met de duidelijke foutmeldingen ("niet
  geïnstalleerd", "geen kluis", "nog geen token"), en kunnen de tests van `Connect-NexusInfra` die functies
  vervangen zonder een echte kluis.
- **`ShouldProcess` alleen voor het bewaren.** Verbinden zelf verandert niets blijvends; een token in een kluis
  schrijven wel. Daarom vraagt alleen dat deel `ShouldProcess`, en werkt `-WhatIf` precies daar.
- **De sessie in de module.** Zo hoef je het token niet aan elke cmdlet mee te geven. In een `-Parallel`-runspace
  bestaat die modulevariabele niet; daar geven de cmdlets de sessie mee met `$using:` (zoals de run-context).
- **Een algemene help-test.** Het voorstel vraagt `Get-Help` op elke functie. In plaats van dat per cmdlet te
  onthouden, controleert één test voor elke cmdlet in `FunctionsToExport` dat er een synopsis, een beschrijving,
  minstens één voorbeeld en uitleg bij elke parameter is. Een nieuwe cmdlet zonder goede help laat de tests falen.
- **Een test tegen een nagebootst panel.** De gemockte tests controleren de logica; de `LocalHttp`-test laat de
  echte `Invoke-NexusApi` praten met een lokale server die antwoordt zoals NexusInfra (eigenaar, gast, token
  zonder `admin`-scope).

## 5. PowerShell-concepten

- **SecretManagement** (`Get-Secret`, `Set-Secret -SecureStringSecret`, `Register-SecretVault`):
  https://learn.microsoft.com/powershell/utility-modules/secretmanagement/overview
- **SecretStore**, een lokale kluis: https://learn.microsoft.com/powershell/utility-modules/secretmanagement/get-started/using-secretstore
- **`SupportsShouldProcess` en `$PSCmdlet.ShouldProcess`:**
  https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-shouldprocess
- **Comment-based help** (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_comment_based_help
- **`Read-Host -AsSecureString`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/read-host
- **Pester `Mock -ModuleName`** (een functie binnen de module vervangen) en **`BeforeDiscovery`** (gegevens voor
  `-ForEach` klaarzetten): https://pester.dev/docs/usage/mocking · https://pester.dev/docs/usage/data-driven-tests

## 6. Zelf proberen

```powershell
Import-Module ./NexusFleet.psd1 -Force
Get-Help Connect-NexusInfra -Full

# Zonder panel: duidelijke fouten
Connect-NexusInfra -BaseUrl 'http://127.0.0.1:1' -Token (Read-Host -AsSecureString 'token')   # NexusApi.Unreachable
Connect-NexusInfra                                                                          # geen token in de kluis

# Eenmalig een kluis opzetten (je kiest een wachtwoord voor de kluis)
Install-Module Microsoft.PowerShell.SecretStore -Scope CurrentUser
Register-SecretVault -Name NexusFleet -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault

# Met je eigen panel (zodra het lab draait)
Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save -WhatIf   # toont wat -Save zou doen
Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save
Connect-NexusInfra                                                                 # volgende keer

# Tests
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests/public, ./tests/utils/NexusStoredToken.Tests.ps1 -Output Detailed
```

## 7. Controlevragen

1. Welke twee dingen controleert `Connect-NexusInfra`, en waarom gebeurt dat vóór elke installatie?
2. Waarom kan de `write`-scope niet vooraf gecontroleerd worden?
3. Waarom vraagt alleen het bewaren van het token `ShouldProcess`, en niet het verbinden?
4. Waarom staat het token niet in de uitvoer van de cmdlet, en hoe blijft het uit het logbestand?
5. Hoe zorgt de help-test ervoor dat elke toekomstige cmdlet goede help heeft?
