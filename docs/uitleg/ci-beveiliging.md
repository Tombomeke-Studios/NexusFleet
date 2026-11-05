# Beveiliging van de pipeline

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

## 1. Wat het doet

De pipeline zelf is ook iets wat je kunt aanvallen. Wie een action kan veranderen die je workflow gebruikt, of een
geheim in de geschiedenis vindt, komt binnen zonder één regel van NexusFleet te raken. Daarom:
- staat elke action vast op één commit;
- zoekt gitleaks bij elke wijziging naar gelekte geheimen;
- geeft OpenSSF Scorecard de repository elke week een rapport over hoe veilig ze gebouwd wordt.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `.github/workflows/*.yml`, `.github/actions/*/action.yml` | Elke `uses:` op een volledige commit-SHA, met de versie als commentaar |
| `tests/Quality.Tests.ps1` | "Every action is pinned to a commit": faalt op een nieuwe, niet-vastgezette action |
| `.github/dependabot.yml` | Houdt de SHA's bij, ook in `.github/actions/` |
| `.github/workflows/secrets.yml` | gitleaks over de commits; vondsten naar code scanning |
| `.gitleaks.toml` | De standaardregels van gitleaks, plus de nepgeheimen van de tests |
| `.github/workflows/scorecard.yml` | OpenSSF Scorecard op `dev`, wekelijks |

## 3. Hoe het werkt

**Actions op een commit (#129).** Vroeger stond er `uses: actions/checkout@v7`. `v7` is een *tag*, en een tag kan de
eigenaar van die repository naar een andere commit verplaatsen. Is die eigenaar gehackt, dan draait jouw workflow
de volgende keer andere code, met jouw token. Dat gebeurde in maart 2025 met `tj-actions/changed-files`: alle
tags wezen opeens naar code die de geheimen van duizenden repositories in de logs zette. Een commit-SHA kan niet
verplaatst worden:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

Het commentaar zegt welke versie dat is, voor mensen en voor Dependabot. Dependabot opent elke week een PR met de
nieuwe SHA én het nieuwe commentaar. Een Quality-test leest elke `uses:`-regel en faalt als er geen 40 hex-tekens na
de `@` staan.

**gitleaks (#130).** gitleaks leest elke commit en zoekt naar wat op een geheim lijkt: API-tokens van bekende
diensten, private keys, wachtwoorden in URL's, en tekst met veel willekeur (*entropie*). Bij een pull request leest
het alleen de commits van die PR (`--log-opts base..head`). Op `dev` en `main`, en elke week, leest het de hele
geschiedenis: een geheim dat toegevoegd en weer verwijderd werd, staat nog in een oude commit. `--redact` zorgt
ervoor dat een gevonden geheim niet in de log van de run zelf terechtkomt.

gitleaks draait als de binary van zijn release. Voor het script die start, controleert het de download tegen het
checksumbestand van die release (`sha256sum --check`). Een download die onderweg veranderd is, draait dus nooit.

De tests gebruiken met opzet nepgeheimen (`nxi_FakeTokenForTests123`, `Br0ker-pass`). Die staan in `.gitleaks.toml`
**per waarde** op de allowlist, niet per map: een echt geheim in een testbestand wordt nog altijd gevonden.

**Scorecard (#131).** De OpenSSF (Open Source Security Foundation) geeft een repository per praktijk een score van 0
tot 10, bijvoorbeeld:
- *Pinned-Dependencies*: staan de actions vast?
- *Token-Permissions*: vraagt elke workflow alleen de rechten die hij nodig heeft?
- *SAST*: draait er statische analyse? Dat is PSScriptAnalyzer via code scanning.
- *Signed-Releases*: de provenance van de release telt mee.
- *Branch-Protection* en *Code-Review*: worden wijzigingen nagekeken voor ze op `dev` komen?

Het resultaat staat publiek op scorecard.dev (de badge in de README), en de verbeterpunten komen in het
Security-tabblad.

**Rechten per job.** Elke workflow begint met `permissions: contents: read`. Alleen de job die het echt nodig heeft,
krijgt meer, bijvoorbeeld `security-events: write` om naar code scanning te schrijven, of `id-token: write` om te
ondertekenen. Zo kan een fout in één stap niet meer doen dan die job mocht.

## 4. Waarom zo

- **SHA's met Dependabot, en geen tags.** Alleen SHA's betekent nooit meer updates, en dat is ook onveilig (oude
  fouten blijven). Met Dependabot krijg je de updates wel, maar als PR, die door dezelfde CI moet.
- **De gitleaks-binary, en niet de action `gitleaks/gitleaks-action`.** Die action vraagt een licentiesleutel voor
  repositories van een organisatie. De binary is gratis en doet hetzelfde. De checksumcontrole maakt de download
  even betrouwbaar als een vastgezette action.
- **Een allowlist per waarde, en niet "sla `tests/` over".** Een map overslaan is precies de plek waar iemand een
  echt token zou plakken om snel iets te testen.
- **Scorecard alleen op `dev`.** Scorecard beoordeelt de standaardbranch. Op een feature-branch heeft het geen zin.
- **Wat nog open staat:** *branch protection* op `dev` (alleen mergen als de checks groen zijn) is een instelling
  van de repository, geen bestand. Die zet Tom zelf aan. Scorecard zal tot dan lager scoren op *Branch-Protection*.

## 5. PowerShell-concepten

Dit onderwerp is vooral GitHub Actions. Wat PowerShell erin zit:
- **Een reguliere expressie met benoemde groepen** in de Quality-test (`(?<ref>[^\s#]+)`):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_regular_expressions
- **Pester `-ForEach` met data uit `BeforeDiscovery`** (één test per `uses:`-regel):
  https://pester.dev/docs/usage/data-driven-tests

En de bronnen over GitHub Actions:
- Security hardening for GitHub Actions: https://docs.github.com/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- OpenSSF Scorecard, de checks: https://github.com/ossf/scorecard/blob/main/docs/checks.md
- gitleaks: https://github.com/gitleaks/gitleaks

## 6. Zelf proberen

```powershell
# Welke actions gebruikt de pipeline, en staan ze vast?
Select-String -Path ./.github/workflows/*.yml, ./.github/actions/*/action.yml -Pattern 'uses:' |
    ForEach-Object { $_.Line.Trim() }

# Zie de Quality-test falen: zet in een workflow één action terug op een tag, en draai
Invoke-Pester ./tests/Quality.Tests.ps1 -Output Detailed
git checkout -- .github/workflows

# De score van de repository
Start-Process 'https://scorecard.dev/viewer/?uri=github.com/Tombomeke-Studios/NexusFleet'
```

## 7. Controlevragen

1. Waarom is `uses: actions/checkout@v7` minder veilig dan een commit-SHA, en wat ging er mis bij
   `tj-actions/changed-files`?
2. Als de SHA's vastliggen, hoe krijgt NexusFleet dan nog updates van de actions?
3. Waarom leest gitleaks op `dev` de hele geschiedenis, en niet alleen de laatste commit?
4. Waarom staan de nepgeheimen per waarde op de allowlist, en niet de map `tests/`?
5. Wat betekent `permissions: contents: read` bovenaan een workflow, en waarom krijgt alleen de lint-job
   `security-events: write`?
