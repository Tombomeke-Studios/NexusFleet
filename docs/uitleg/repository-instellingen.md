# Repository-instellingen

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: unit 4 (`.gitignore` en `.gitattributes`, #4)._

## 1. Wat het doet

Twee kleine bestanden in de root sturen hoe git met de bestanden omgaat. `.gitignore` zegt welke bestanden
**nooit** in de repository mogen: logs, je echte hostlijst en lokale configuratie met geheimen.
`.gitattributes` zorgt dat PowerShell- en shellscripts altijd **LF**-regeleinden hebben, ook op Windows,
omdat bash op een Linux-host anders over de Windows-regeleinden struikelt.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `.gitignore` | `logs/`, `config/*.local.*`, `config/inventory.json`, Pester-uitvoer, OS-bestanden |
| `.gitattributes` | `* text=auto` en `eol=lf` voor `*.ps1`, `*.psm1`, `*.psd1`, `*.sh` |

## 3. Hoe het werkt

**`.gitignore`.** Elke regel is een patroon. Bij `git add` slaat git bestanden over die op een patroon passen:

```gitignore
logs/
config/*.local.*
config/inventory.json
```

- `logs/`: de hele map met run-logs, die `Write-NexusLog` later aanmaakt.
- `config/*.local.*`: elk bestand in `config/` met `.local.` in de naam, bijvoorbeeld
  `config/nexusinfra.local.psd1`. Daar komen je eigen adressen en instellingen in.
- `config/inventory.json`: je echte hostlijst. In de repo staat alleen het voorbeeld
  `config/inventory.example.json`.

**`.gitattributes`.** Een regeleinde is het onzichtbare teken aan het eind van elke regel. Linux en macOS
gebruiken **LF** (`\n`), Windows gebruikt traditioneel **CRLF** (`\r\n`). Op deze machine staat in de
systeemconfiguratie van Git voor Windows `core.autocrlf = true`. Dat betekent: in de repo LF, maar bij
uitchecken zet git er CRLF van.

```gitattributes
* text=auto

*.ps1  text eol=lf
*.psm1 text eol=lf
*.psd1 text eol=lf
*.sh   text eol=lf
```

- `* text=auto`: git herkent zelf welke bestanden tekst zijn en bewaart die in de repo altijd met LF.
- `*.ps1 text eol=lf` (en de andere): voor deze bestanden ook **in je werkmap** LF, wat `core.autocrlf` ook
  zegt. `.gitattributes` zit in de repo, dus dit geldt voor iedereen die kloont, en wint van de instelling op
  die machine.
- Andere tekstbestanden (zoals `.md`) volgen de instelling van de machine. Dat is geen probleem, want ze
  worden nooit naar een host gestuurd.

Na het toevoegen is `git add --renormalize .` uitgevoerd, wat bestaande bestanden opnieuw volgens de regels
opslaat. Er veranderde niets, want alles stond al met LF in de repo.

## 4. Waarom zo

- **Waarom LF zo belangrijk is.** NexusFleet stuurt straks scripts via SSH naar Ubuntu-hosts. Bash leest de
  `\r` van CRLF als deel van het commando, en dan krijg je fouten als `$'\r': command not found`, of een
  `apt-get install docker-ce\r` die een pakket met een onzichtbaar teken in de naam zoekt. Die fouten zijn
  moeilijk te zien. De regel staat ook in CLAUDE.md (sectie 8, SSH).
- **`.gitattributes` in plaats van iedereen `core.autocrlf` te laten aanpassen.** Een instelling op je eigen
  machine geldt niet voor de docent, de CI of een nieuwe laptop. Een bestand in de repo geldt voor iedereen.
- **Ook `.psd1` en `.psm1` op LF**, niet alleen `.sh`. De module draait ook op Linux (CI op ubuntu-latest), en
  één regel voor alle PowerShell-bestanden is eenvoudiger dan uitzonderingen. PowerShell leest LF op elk
  platform zonder problemen.
- **Ignoren op naam (`*.local.*`) in plaats van op map.** De voorbeeldconfiguratie moet wel in de repo, in
  dezelfde map als je echte configuratie. Met een naamafspraak staan ze naast elkaar, en alleen de lokale
  versie blijft buiten git. Het alternatief was een aparte map `config/local/`, maar dan staan voorbeeld en
  echte versie ver uit elkaar.
- **Het echte inventarisbestand ook negeren.** De repo is publiek. Je hostlijst bevat IP-adressen en
  gebruikersnamen van je thuis- en laptop-VM's, en die horen daar niet.
- **`.gitignore` is geen geheimenbeheer.** Hij voorkomt alleen een ongelukje bij `git add`. Het API-token en
  het `INTERNAL_API_TOKEN` komen in SecretManagement (fase 3) en staan nooit in een bestand in de repo, ook
  niet in een genegeerd bestand.

## 5. PowerShell- en git-concepten

- **`.gitignore`-patronen:** https://git-scm.com/docs/gitignore
- **`git check-ignore -v`:** toont welke regel een bestand negeert. https://git-scm.com/docs/git-check-ignore
- **`.gitattributes`, `text`, `eol`:** https://git-scm.com/docs/gitattributes
- **Regeleinden op GitHub en `core.autocrlf`:**
  https://docs.github.com/en/get-started/git-basics/configuring-git-to-handle-line-endings
- **`git ls-files --eol`:** toont per bestand het regeleinde in de repo (`i/`), in je werkmap (`w/`) en welk
  attribuut geldt (`attr/`). https://git-scm.com/docs/git-ls-files

## 6. Zelf proberen

```bash
# Welke regel negeert dit bestand?
git check-ignore -v logs/run.log config/nexusinfra.local.psd1 config/inventory.json

# Het voorbeeld wordt NIET genegeerd (geen uitvoer = gevolgd)
git check-ignore config/inventory.example.json

# Regeleinden per bestand: .ps1/.psd1/.psm1 tonen attr/text eol=lf
git ls-files --eol

# Waar staat core.autocrlf op deze machine?
git config --show-origin core.autocrlf
```

Zien wat CRLF met bash doet (op een Linux-host of in WSL):

```bash
printf 'echo hallo\r\n' > crlf.sh
bash crlf.sh        # hallo wordt gevolgd door een onzichtbare \r; met een commando als 'ls\r' faalt het
cat -A crlf.sh      # toont ^M$ aan het eind van de regel: dat is de \r
rm crlf.sh
```

## 7. Controlevragen

1. Wat is het verschil tussen LF en CRLF, en waarom maakt dat uit voor een script dat naar een Ubuntu-host gaat?
2. Waarom zet je de regeleinden in `.gitattributes` en niet in je eigen git-configuratie?
3. Wat betekent `* text=auto`, en wat voegt `eol=lf` daar voor `.ps1` aan toe?
4. Waarom staat `config/inventory.json` in `.gitignore` maar `config/inventory.example.json` niet?
5. Waarom is `.gitignore` geen goede plek om geheimen te beschermen, en waar komen ze dan wel?
