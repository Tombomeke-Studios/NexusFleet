# De experimenten E1–E4 in gewone taal

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: na experimenten E1–E4 (#16–#19). De technische details staan in `docs/ontwerpkeuzes.md`; dit bestand
legt uit wát er beslist moest worden en waarom het voorstel zo is, zonder vakjargon waar het kan._

## 1. Wat het doet

Voordat de echte cmdlets gebouwd worden, moesten vier vragen beantwoord worden. Elk antwoord bepaalt hoe een
stuk van NexusFleet gebouwd wordt. Daarom zijn ze eerst uitgeprobeerd en gemeten in plaats van gegokt. Dat is
ook wat het criterium *Design* vraagt: tonen welke opties uitgetest werden, welke weerhouden werden en waarom.

| | De vraag in één zin | Het voorstel in één zin |
|---|---|---|
| **E1** | Hoe geeft NexusFleet een commando aan een Linux-server? | Met het gewone `ssh`-programma |
| **E2** | Hoe werkt NexusFleet met veel servers tegelijk? | Met `ForEach-Object -Parallel` |
| **E3** | Hoe test je code die met veel servers tegelijk werkt? | Het werk voor één server in een eigen functie zetten, en die testen |
| **E4** | Welke rechten heeft NexusFleet nodig in NexusInfra? | Een beheerdersaccount en een token met `write` + `admin` |

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `docs/ontwerpkeuzes.md` | Alle metingen, de voorstellen en de keuzes K1–K5 |
| `lab/` | De scripts van de experimenten (index: `lab/README.md`) |
| `docs/uitleg/ssh-transport.md` | E1 in detail |
| `docs/uitleg/parallel-uitvoering.md` | E2 en E3 in detail |

## 3. Hoe het werkt (per experiment)

### E1 — Hoe geeft NexusFleet een commando aan een server?

**De situatie.** Om een server een node te maken, moet NexusFleet op die server dingen doen: Docker
installeren, de agent-container starten. NexusFleet draait op jouw laptop, de server staat ergens anders. Er moet
dus een manier zijn om vanaf je laptop "voer dit uit" tegen de server te zeggen. Dat heet hier het *transport*.

**De drie kandidaten.** Vergelijk het met drie manieren om iemand in een ander gebouw iets te laten doen:

1. **Gewoon `ssh`:** je belt aan, zegt één opdracht, en hangt op. Voor elke opdracht bel je opnieuw. Elke Linux-
   server heeft standaard een deurbel (de SSH-server), en je laptop heeft al een telefoon (de `ssh`-client zit in
   Windows 10 en later).
2. **PowerShell-remoting over SSH:** je belt één keer en blijft aan de lijn, en je spreekt allebei "PowerShell".
   Maar dan moet de server eerst PowerShell leren: op **elke** server moet PowerShell geïnstalleerd worden.
3. **Posh-SSH:** ook één keer bellen en aan de lijn blijven, maar met een extra toestel dat je eerst op je laptop
   moet installeren (een module van iemand anders).

**Wat er getest werd.** Omdat er nog geen echte lab-VM was, maakte het experiment twee Docker-containers die zich
gedragen als een verse Ubuntu-server. Daarop werden de drie manieren gemeten:

- **Snelheid:** allemaal ongeveer even snel om te verbinden (0,2–0,5 s). `ssh` is per opdracht iets trager
  (0,20 s) omdat het telkens opnieuw "belt"; de andere twee 0,07–0,09 s.
- **Fouten:** alle drie gaven een fout van de server netjes terug, en geen enkele bleef hangen bij een verkeerde
  sleutel of een server die niet antwoordt.
- **Geheimen doorgeven:** een geheim (zoals het token van de agent) moet je naar de server sturen **zonder** dat
  het op de opdrachtregel staat, want daar kan iedereen op de server het zien. Dat kan via *stdin* (het geheim
  wordt als het ware "ingetypt" in plaats van in de opdracht geschreven). Met `ssh` en remoting lukt dat; met
  Posh-SSH niet.

**Waarom het voorstel `ssh` is.**

- Er moet **niets op de servers** geïnstalleerd worden. Remoting vraagt PowerShell op elke server: bij honderd
  servers is dat honderd keer een extra installatie, en meer software op een server is meer dat kan misgaan of
  aangevallen worden.
- Er is **geen extra module** nodig op je laptop (Posh-SSH).
- **Geheimen kunnen veilig mee** via stdin; bij Posh-SSH niet.
- Het nadeel, iets trager per opdracht, valt weg omdat NexusFleet veel servers **tegelijk** behandelt (E2).

**De verrassing.** Een geheim dat je in PowerShell op Windows naar `ssh` stuurt, krijgt onzichtbaar `\r\n` (een
Windows-regeleinde) erachter. Linux houdt de `\r` vast, dus het geheim is één onzichtbaar teken te lang en zou
niet werken. De oplossing (het geheim als bytes sturen) kan pas vanaf PowerShell 7.4. Dat is één van de redenen
voor jouw keuze voor 7.6 (K4).

### E2 — Hoe werkt NexusFleet met veel servers tegelijk?

**De situatie.** Stel dat één server klaarmaken 30 seconden duurt. Honderd servers na elkaar is 50 minuten. Tien
tegelijk is 5 minuten. NexusFleet moet dus servers tegelijk behandelen. PowerShell heeft drie manieren om dat te
doen.

**De drie kandidaten.** Vergelijk het met een keuken die honderd maaltijden moet maken:

1. **`ForEach-Object -Parallel`:** tien koks in **dezelfde keuken**, die elk een maaltijd maken.
2. **`Start-ThreadJob`:** ook tien koks in dezelfde keuken, maar elke maaltijd krijgt een bonnetje dat je
   achteraf moet ophalen. Wat meer administratie.
3. **`Start-Job`:** voor elke maaltijd wordt een **hele nieuwe keuken** gebouwd. Werkt, maar het bouwen kost tijd
   en ruimte.

**Wat er gemeten werd.** Vijftig nep-servers, elk 0,5 s werk, tien tegelijk:

| Manier | Tijd | Geheugen |
|---|---|---|
| Na elkaar (ter vergelijking) | 26 s | 99 MB |
| `ForEach-Object -Parallel` | **2,9 s** | **124 MB** |
| `Start-ThreadJob` | 3,4 s | 173 MB |
| `Start-Job` | 9,6 s | 464 MB |

Het snelst mogelijke resultaat is 2,5 s (50 servers, 10 tegelijk, 0,5 s elk). `-Parallel` komt daar het dichtst
bij.

**Waarom het voorstel `-Parallel` is.** Het is het snelst, gebruikt het minst geheugen, zit in PowerShell zelf,
en je kunt makkelijk instellen hoeveel er tegelijk mogen (`-ThrottleLimit`). Dat laatste is belangrijk: zonder
limiet zou NexusFleet bij 500 servers 500 verbindingen tegelijk openen.

### E3 — Hoe test je code die met veel servers tegelijk werkt?

**De situatie.** Tests mogen nooit echte servers aanraken (anders heb je voor elke test een lab nodig, en zijn de
tests traag en onbetrouwbaar). Daarom vervang je in een test "praat met de server" door een nep-versie die een
vast antwoord geeft. In Pester heet dat een **mock**: een stand-in, zoals een stuntman voor een acteur.

**Het probleem.** Met `-Parallel` (E2) werkt elke "kok" in een eigen, lege werkplek die bij de start opnieuw
wordt ingericht. De stuntman die de test regelde, staat alleen in de werkplek van de test zelf. In de werkplekken
van de koks staat weer de echte acteur.

**Wat er getest werd.** Een mini-module met dezelfde opbouw als NexusFleet. Dezelfde mock, op drie manieren
aangeroepen:

| Hoe | Wie speelde er? |
|---|---|
| De functie rechtstreeks aanroepen | de stuntman (mock), 1 keer |
| In een gewone lus, na elkaar | de stuntman, 2 keer |
| Met `-Parallel` | **de echte acteur**, 0 keer de stuntman |

Het vermoeden klopt dus: in `-Parallel` werken mocks niet.

**Waarom het voorstel "het werk per server in een eigen functie" is.** Alle logica voor één server komt in één
functie, die je rechtstreeks test, met mocks, en volledig. De parallelle lus eromheen doet bijna niets meer dan
"roep die functie aan voor elke server". Dan valt er aan de lus ook bijna niets te testen. Zo test je toch alles
wat ertoe doet.

### E4 — Welke rechten heeft NexusFleet nodig in NexusInfra?

**De situatie.** NexusFleet praat met NexusInfra via een **API-token**: een soort sleutelkaart. NexusInfra kent
per sleutelkaart *scopes*: welke deuren hij opent. Er zijn er twee: `write` (dingen veranderen) en `admin` (het
panel zelf beheren). Lezen mag altijd. Daarnaast heeft het **account** achter de kaart een rol (gewone gebruiker,
admin of owner).

**Wat er onderzocht werd.** In de broncode van NexusInfra staat precies welke controles er gebeuren:

1. Alles wat iets verandert (zoals een node registreren), vraagt de scope `write`.
2. De node-routes zijn "beheer van het panel" en vragen bovendien een account met rol `admin` of `owner`, én een
   kaart met de scope `admin`.

| Wat NexusFleet doet | Nodig |
|---|---|
| Lijst van nodes ophalen | elke kaart |
| Een node registreren, in onderhoud zetten, verwijderen | admin-account + kaart met `write` **en** `admin` |

**Waarom het voorstel zo is.** NexusFleet vraagt dus een kaart met `write` en `admin` van een beheerder.
`Connect-NexusInfra` kan bij het verbinden al controleren of dat klopt, zodat je meteen een duidelijke fout krijgt
en niet pas halverwege een installatie. Dit is gelezen in de code en in de tests van NexusInfra zelf; het moet nog
één keer echt uitgeprobeerd worden zodra je lab draait (#21).

## 4. Waarom zo

- **Meten in plaats van gokken.** Elk voorstel steunt op een meting of op de broncode, niet op "dat zeggen ze op
  internet". Daardoor kun je bij elke keuze uitleggen waarom, en welke alternatieven afvielen.
- **Containers in plaats van wachten.** Zonder lab-VM konden E1–E3 toch gedaan worden: E2 en E3 met nep-werk, E1
  met containers die zich als een verse server gedragen. Wat alleen een echte VM kan bewijzen (Docker op de
  server installeren, over het internet), komt in je lab (#14).
- **Voorstellen, geen beslissingen.** De keuzes zijn van jou (#20). Als je een voorstel anders ziet, verandert de
  bouw van het stuk dat ervan afhangt.

## 5. PowerShell-concepten

- **`ForEach-Object -Parallel`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object
- **Pester-mocks:** https://pester.dev/docs/usage/mocking
- **PowerShell-remoting over SSH:** https://learn.microsoft.com/powershell/scripting/security/remoting/ssh-remoting-in-powershell
- **Stdin en externe programma's** (waarom een geheim niet op de opdrachtregel hoort): zie
  `docs/uitleg/ssh-transport.md`, sectie 3.

## 6. Zelf proberen

```powershell
# E3: zie de stuntman wel en niet spelen (een paar seconden)
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./lab/E3-mocks-parallel -Output Detailed

# E2: een kleine meting (ongeveer een halve minuut)
./lab/E2-concurrency/Measure-Concurrency.ps1 -TargetCount 20 -Repeat 1 | Format-Table

# E1: de vergelijking (vereist Docker Desktop en Posh-SSH)
./lab/E1-transport/Start-LabTarget.ps1
./lab/E1-transport/Measure-Transport.ps1 | Format-Table -AutoSize
```

## 7. Controlevragen

1. Waarom valt PowerShell-remoting af, hoewel het per opdracht sneller is?
2. Waarom mag een geheim niet op de opdrachtregel van `ssh` staan, en hoe gaat het dan wel naar de server?
3. Waarom is `Start-Job` zo veel trager dan `ForEach-Object -Parallel`?
4. Waarom werkt een Pester-mock niet in `-Parallel`, en hoe test NexusFleet dan toch alles?
5. Welke rechten heeft het token van NexusFleet nodig, en waarom kan een token met alleen `write` geen node
   registreren?
