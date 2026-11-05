# Kwaliteitspoorten in CI

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

## 1. Wat het doet

Een pull request mag pas naar `dev` als hij door een reeks *poorten* raakt: controles die elk één ding nakijken en
rood worden als het niet klopt. Naast lint en tests zijn dat nu ook:
- de berichten van de commits en de titel van de PR;
- een ondergrens voor de testdekking;
- de workflowbestanden zelf;
- de tests op macOS.

De meldingen van PSScriptAnalyzer verschijnen bovendien in het Security-tabblad van GitHub.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `tools/Test-NexusCommitMessage.ps1` | Controleert of een bericht `type(scope): summary` volgt (CLAUDE.md, sectie 3) |
| `tests/tools/Test-NexusCommitMessage.Tests.ps1` | 16 tests, waaronder een echte git-repo in `TestDrive` met een merge |
| `tools/Invoke-NexusLint.ps1` | `-SarifPath`: de meldingen als SARIF 2.1.0 voor *code scanning* |
| `tools/Write-NexusTestReport.ps1`, `tools/Invoke-NexusTests.ps1` | `-MinimumCoverage`: zegt in het rapport of de dekking hoog genoeg is, en laat de run falen als dat niet zo is |
| `.github/workflows/ci.yml` | De jobs `lint` (met SARIF-upload), `workflows` (actionlint), `commits`, `test` (drie systemen, minimaal 95 %), `build` |

## 3. Hoe het werkt

**Commitberichten (#134).** Het script neemt van elk bericht alleen de eerste regel en loopt een vaste lijst af:

```powershell
if ($Line -notmatch '^(?<type>[a-z]+)\((?<scope>[a-z]+)\): (?<summary>\S.*)$') {
    return "it does not read 'type(scope): summary'"
}
if ($Matches.type -notin $types) { return "type '$($Matches.type)' is not one of ..." }
```

`(?<type>...)` is een *benoemde groep*: na een geslaagde `-match` staat wat erin paste in `$Matches.type`. De
volgende controles zijn de scope, geen punt aan het eind, en hoogstens 100 tekens. Met `-Range base..head` vraagt
het script de berichten zelf op met `git log --reverse --no-merges --format=%s`. In CI draait de job `commits`
alleen bij een pull request. Hij controleert de titel en elke commit tussen de basis en de kop van de PR, zet een
tabel in de samenvatting, en geeft per fout een `::error`.

**Code scanning (#132).** SARIF is een JSON-formaat dat elke analysetool kan schrijven: een `run` met de naam van de
tool, de regels, en per melding de regel-id, het niveau, de tekst en de plaats (bestand, regel, kolom). De
lint-job schrijft het bestand en `github/codeql-action/upload-sarif` stuurt het naar GitHub. Dat bestand gaat er
ook heen als er geen meldingen zijn: een lege lijst is hoe GitHub weet dat oude meldingen opgelost zijn.

**De dekking (#135).** Pester meet de dekking al. Het rapport krijgt nu een ondergrens mee en zegt in woorden of
die gehaald is. `Invoke-NexusTests.ps1` gooit daarna een fout als ze niet gehaald is:

```powershell
if ($report.CoverageMet -eq $false) {
    throw "...the coverage of src/ is $($report.Coverage) %, below the minimum of $MinimumCoverage %..."
}
```

`-eq $false` en niet `-not`: `CoverageMet` is `$null` als er geen ondergrens gevraagd werd, en dat mag niet als
"niet gehaald" tellen.

**De workflows (#133).** `actionlint` leest elk bestand in `.github/workflows/`. Het controleert de syntax, de
`${{ }}`-expressies, of de jobs waar je naar verwijst bestaan, en de invoer van bekende actions. Een tikfout in een
workflow faalt dan in de PR, en niet pas bij de volgende run.

**macOS (#136).** De testjob is een matrix van drie systemen: `ubuntu-latest`, `windows-latest` en `macos-latest`.

## 4. Waarom zo

- **Commitregels door een script, niet alleen door afspraak.** De regels uit CLAUDE.md werden tot nu toe alleen
  nagekeken door wie de commit schreef. Een script dat 300 bestaande commits nakeek, vond meteen dat twee regels uit
  het eerste ontwerp te streng waren. Een hoofdletter aan het begin is soms juist (`E3 prove ...`,
  `Invoke-NexusApi`), en 72 tekens was te kort voor goede berichten. Daarom: geen hoofdletterregel, en 100 tekens,
  de grens die commitlint ook gebruikt. Met de hand geschreven merge-berichten slaat `--no-merges` over.
- **De PR-titel via een omgevingsvariabele (`env: PR_TITLE`)**, nooit als `${{ github.event.pull_request.title }}`
  in het script geplakt. Een titel kiest iedereen die een PR opent zelf. Geplakt in het script, zou een titel met
  `"; Remove-Item ...` als code uitgevoerd worden: *script injection*, de bekendste valkuil van GitHub Actions.
- **Een ondergrens van 95 % en geen 100 %.** De dekking is nu 98 %. 95 laat ruimte voor een regel die je echt niet
  kunt testen (`Invoke-NexusSshClient` start echt `ssh`), maar vangt een nieuwe functie zonder tests.
- **SARIF en geen eigen tabel alleen.** De Markdown-tabel in de samenvatting blijft. Code scanning onthoudt de
  meldingen wel over runs heen, en toont ze in het Security-tabblad. Het is ook wat Scorecard (zie
  `ci-beveiliging.md`) als "SAST" herkent.
- **actionlint uit zijn image, op een vaste versie,** zodat de controle niet verandert zonder dat iemand het ziet.

## 5. PowerShell-concepten

- **Benoemde groepen in een reguliere expressie en `$Matches`:**
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_regular_expressions
- **Parametersets** (`DefaultParameterSetName`, `-Message` of `-Range`):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters
- **`begin` / `process` / `end`** (berichten uit de pipeline één voor één):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_methods
- **`$LASTEXITCODE`** na een extern programma (`git log`):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_automatic_variables
- **Pester-codedekking** (`CodeCoverage`, `CoveragePercent`): https://pester.dev/docs/usage/code-coverage
- **SARIF** (geen PowerShell, maar het formaat): https://docs.github.com/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning

## 6. Zelf proberen

```powershell
# Een goed en een fout bericht
./tools/Test-NexusCommitMessage.ps1 -Message 'feat(steps): add a step', 'Fixed stuff.'

# De commits van je branch, voor je een PR opent
./tools/Test-NexusCommitMessage.ps1 -Range origin/dev..HEAD | Where-Object { -not $_.Valid }

# De dekking met een ondergrens: met 99 % faalt hij
./tools/Invoke-NexusTests.ps1 -MinimumCoverage 95
./tools/Invoke-NexusTests.ps1 -MinimumCoverage 99

# De lint-meldingen als SARIF
./tools/Invoke-NexusLint.ps1 -SarifPath ./lint.sarif
Get-Content ./lint.sarif | ConvertFrom-Json | Select-Object -ExpandProperty runs
```

## 7. Controlevragen

1. Wat staat er na `'fix(api): retry' -match '^(?<type>[a-z]+)\((?<scope>[a-z]+)\): (?<summary>\S.*)$'` in
   `$Matches`?
2. Waarom komt de titel van de PR via `env:` in het script, en wat kan er gebeuren als je hem rechtstreeks in de
   `run:` zet?
3. Waarom controleert de commit-job alleen de commits tussen `base.sha` en `head.sha`, en niet de hele
   geschiedenis?
4. Waarom vergelijkt `Invoke-NexusTests.ps1` met `-eq $false` en niet met `-not $report.CoverageMet`?
5. Waarom stuurt de lint-job ook een SARIF-bestand zonder meldingen naar GitHub?
