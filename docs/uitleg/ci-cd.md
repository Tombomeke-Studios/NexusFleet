# CI/CD: testresultaten, dekking, build en release

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: fase 4 (#55, #57, #58, #59): schaaltests, testresultaten en dekking in CI, het buildscript, de
release-workflow en het demoscript._

## 1. Wat het doet

Bij elke push controleert GitHub de code (lint en tests, zie `kwaliteitscontrole.md`). Nu bewaart die controle ook
de testresultaten en meet hij hoeveel van de code de tests echt uitvoeren (de *dekking*). Bij een versietag
(`v1.0.0`) bouwt een tweede workflow de module zoals ze uitgeleverd wordt, en zet die als zip in een GitHub-release.
Het demoscript draait de hele flow op een inventaris en meet de tijden voor het verslag.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `.github/workflows/ci.yml` | Lint en tests; nu met testresultaten (NUnit XML), dekking (JaCoCo) en een samenvatting |
| `.github/workflows/release.yml` | Bij een tag `v*`: dezelfde controles, versie nakijken, bouwen, release maken |
| `tools/Build-NexusModule.ps1` | Bouwt `out/NexusFleet/` en `out/NexusFleet-<versie>.zip` met alleen wat de module nodig heeft |
| `tests/tools/Build-NexusModule.Tests.ps1` | Bouwt echt in TestDrive en controleert de inhoud |
| `tests/public/Scale.Tests.ps1` | 50 en 100 gegenereerde servers voor de drie cmdlets die per server werken |
| `lab/demo/Invoke-NexusDemo.ps1` | De demo: preflight, plan, installatie, tweede run, status, met tijden en de drie criteria |
| `lab/demo/README.md` | Wat de lab-VM's nodig hebben, en hoe je de demo draait |

## 3. Hoe het werkt

**Dekking in CI.** Pester houdt bij welke regels in `src/` uitgevoerd werden:

```powershell
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = './src'
$config.CodeCoverage.UseBreakpoints = $false   # de snellere manier van meten
$config.CodeCoverage.OutputFormat = 'JaCoCo'
```

De totalen (geslaagd, gefaald, dekking in %) gaan naar `$env:GITHUB_STEP_SUMMARY`, zodat ze bovenaan de run op
GitHub staan. De bestanden gaan als artifact `test-results` mee, ook als een test faalt (`if: always()`).

**Het buildscript** kopieert een vaste lijst: de manifest, de loader, de README, elk `.ps1`-bestand onder `src/`, en
de standaardconfig met het voorbeeld van de inventaris. Nooit tests, tools, het lab, de docs, logs of een lokale
config. Daarna controleert het zijn eigen werk in een **apart** `pwsh`-proces: laadt de gebouwde module, en exporteert
ze precies de cmdlets van de manifest? Pas dan maakt het de zip.

**De release-workflow:**

1. `checks` hergebruikt `ci.yml` (`workflow_call`): dezelfde lint en tests, niet een kopie ervan.
2. Komen de tag en `ModuleVersion` in de manifest overeen? `v1.0.0` met versie `0.1.0` stopt hier.
3. `Build-NexusModule.ps1`, en de zip als artifact.
4. `gh release create` met de zip en automatische release notes.

Met de hand gestart (`workflow_dispatch`) doet hij stap 1 en 3: een proefrelease zonder release.

**Het demoscript** voert de vijf fases uit, meet elke fase met een `Stopwatch`, en beoordeelt daarna de drie
criteria op de resultaten zelf (niet op wat iemand ziet): zijn alle geslaagde servers nu *healthy*, veranderde de
tweede run niets, en kregen falende servers hun eigen fout terwijl de rest slaagde?

## 4. Waarom zo

- **Dekking als getal, niet als doel.** 96 % zegt vooral waar tests ontbreken: de meting vond een functie zonder test
  (`ConvertTo-NexusInstallFailure`). `Invoke-NexusSshClient` blijft bewust buiten de unit-tests: die start echt `ssh`
  en wordt door de integratietest gedekt.
- **Bouwen met een script en niet in de workflow zelf**: lokaal en in CI hetzelfde, en het script heeft een eigen test.
- **Een release alleen bij een tag**, en tags alleen op `main` bij een mijlpaal (CLAUDE.md, sectie 2). Publiceren in
  de PowerShell Gallery is een extra voor later (fase 5), en vraagt een API-sleutel van de Gallery.
- **De versiecontrole**: een release mag nooit een andere versie bevatten dan haar naam zegt.
- **Schaaltests met falende servers erin** (elke 17e onbereikbaar, elke 23e weigert NexusInfra): het gaat er niet om
  dat 100 servers werken, wel dat elke server zijn eigen, juiste resultaat krijgt.
- **Het demoscript beoordeelt de criteria zelf**, zodat de meting in het verslag niet afhangt van iemand die een tabel
  goed leest. De tijden uit het node-lab zijn niet representatief (cache), die van de VM's wel.

## 5. PowerShell-concepten

- **Pester-configuratie: `TestResult`, `CodeCoverage`:** https://pester.dev/docs/usage/code-coverage
- **GitHub Actions: herbruikbare workflows (`workflow_call`), artifacts, job summary:**
  https://docs.github.com/actions/sharing-automations/reusing-workflows ·
  https://docs.github.com/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions#adding-a-job-summary
- **`Compress-Archive`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.archive/compress-archive
- **`Test-ModuleManifest`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.core/test-modulemanifest
- **`[System.IO.Path]::GetRelativePath`:** https://learn.microsoft.com/dotnet/api/system.io.path.getrelativepath
- **`[System.Diagnostics.Stopwatch]`:** https://learn.microsoft.com/dotnet/api/system.diagnostics.stopwatch

## 6. Zelf proberen

```powershell
# Bouwen en de gebouwde module laden
./tools/Build-NexusModule.ps1
Get-ChildItem ./out/NexusFleet -Recurse -File | Select-Object -ExpandProperty FullName
pwsh -NoProfile -Command "Import-Module ./out/NexusFleet/NexusFleet.psd1 -PassThru | Select-Object -ExpandProperty ExportedFunctions"

# Dekking lokaal meten
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
$c = New-PesterConfiguration
$c.Run.Path = './tests'; $c.Filter.ExcludeTag = 'Integration'; $c.Run.PassThru = $true
$c.CodeCoverage.Enabled = $true; $c.CodeCoverage.Path = './src'; $c.CodeCoverage.UseBreakpoints = $false
$r = Invoke-Pester -Configuration $c
$r.CodeCoverage.CoveragePercent
$r.CodeCoverage.CommandsMissed | Group-Object File | Select-Object Count, Name

# Laten mislukken: een versie die niet bij de tag past, zoals de workflow het controleert
$version = (Import-PowerShellDataFile ./NexusFleet.psd1).ModuleVersion
if ('v9.9.9' -ne "v$version") { "Tag v9.9.9 does not match ModuleVersion $version" }

# De schaaltests
Invoke-Pester -Path ./tests/public/Scale.Tests.ps1 -Output Detailed
```

## 7. Controlevragen

1. Waarom hergebruikt de release-workflow `ci.yml` in plaats van de lint- en teststappen te kopiëren?
2. Wat controleert `Build-NexusModule.ps1` voordat het de zip maakt, en waarom in een apart `pwsh`-proces?
3. Waarom is 100 % dekking geen doel, en welke functie blijft bewust buiten de unit-tests?
4. Wat gebeurt er als je de tag `v1.0.0` pusht terwijl de manifest nog `0.1.0` zegt?
5. Waarom zitten er in de schaaltests opzettelijk onbereikbare en falende servers?
