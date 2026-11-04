# API-client

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: `Invoke-NexusApi` (#25), en de fix voor lijsten (#47)._

## 1. Wat het doet

`Invoke-NexusApi` is de enige functie in NexusFleet die met de REST-API van NexusInfra praat. Ze stuurt het
API-token mee, wacht niet eindeloos, probeert een leesverzoek opnieuw als het netwerk even hapert, en maakt van
een foutcode van de server een foutmelding die een beheerder begrijpt.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `src/api/Invoke-NexusApi.ps1` | De functie |
| `tests/api/Invoke-NexusApi.Tests.ps1` | 27 tests met een gemockte `Invoke-RestMethod` (de logica) |
| `tests/api/Invoke-NexusApi.LocalHttp.Tests.ps1` | 4 tests tegen een echte HTTP-server op de eigen machine (tag `LocalHttp`) |
| `config/nexusinfra.psd1`, `Api` | `BaseUrl`, `TimeoutSeconds`, `RetryCount`, `AllowUnencryptedHttp` |

## 3. Hoe het werkt

Een oproep ziet er zo uit:

```powershell
Invoke-NexusApi -BaseUrl $config.Api.BaseUrl -Token $token -Method POST -Path '/nodes' -Body @{ id = 'node-a' }
```

1. **Het verzoek opbouwen.** De URL is `BaseUrl` (zonder slash op het einde) plus `Path`. De parameters voor
   `Invoke-RestMethod` komen in een hashtable (`$request`) die later met *splatting* (`@request`) wordt
   meegegeven. Het token gaat via de ingebouwde `-Authentication Bearer -Token`: het blijft een `SecureString`.
   Een `-Body` wordt JSON.
2. **De http-regel.** Over gewone `http://` weigert `Invoke-RestMethod` een token te sturen, tenzij je
   `-AllowUnencryptedAuthentication` meegeeft. `Invoke-NexusApi` doet dat alleen voor de eigen machine
   (`[uri]$BaseUrl).IsLoopback`: `localhost`, `127.0.0.1`, `::1`). Voor een andere `http://`-host moet
   `-AllowUnencryptedHttp` gezet zijn (in de configuratie), en dan volgt een waarschuwing. Anders stopt de
   functie meteen met `NexusApi.UnencryptedNotAllowed`, nog vóór er iets verstuurd is.
3. **Proberen, en eventueel opnieuw.** Een `for`-lus doet hoogstens `1 + RetryCount` pogingen voor `GET`, en
   precies één voor alle andere methodes. Na een netwerkfout of 502/503/504 wacht de functie even (1 s, 2 s,
   4 s: telkens het dubbele) en probeert opnieuw.
4. **Een fout begrijpelijk maken.** In de `catch` wordt de fout eerst in `$caught` bewaard. Daarna:
   - Is er een HTTP-status (`$caught.Exception.Response.StatusCode`)? Dan bepaalt de status de foutcode.
   - Geen status, en het is een `HttpRequestException`, `TaskCanceledException` of `TimeoutException`? Dan is
     het een netwerkfout: `NexusApi.Unreachable`.
   - Iets anders: `NexusApi.RequestFailed`, zonder herhaling.

   | Status | Foutcode | Uitleg in de melding |
   |---|---|---|
   | 401 | `NexusApi.Unauthorized` | token ongeldig, verlopen of ingetrokken |
   | 403 | `NexusApi.Forbidden` | te weinig rechten (node-routes: platformbeheerder + scopes `write` en `admin`) |
   | 404 | `NexusApi.NotFound` | niet gevonden (NexusInfra antwoordt ook 404 als je geen toegang hebt) |
   | 409 | `NexusApi.Conflict` | botst met de huidige toestand (bijv. node met een draaiende deployment) |
   | 502–504 | `NexusApi.Unavailable` | panel tijdelijk niet beschikbaar |
   | geen | `NexusApi.Unreachable` | panel niet bereikbaar, met de reden |

   Als er een HTTP-antwoord was, komt de boodschap van NexusInfra erbij (`{ "error": "..." }`, die PowerShell
   in `ErrorDetails` bewaart). De fout wordt gegooid met `$PSCmdlet.ThrowTerminatingError(...)`, met de
   foutcode als `FullyQualifiedErrorId`, zodat een cmdlet erop kan reageren zonder de tekst te ontleden.

**Een lijst als antwoord** (#47, gevonden in het node-lab). `Invoke-RestMethod` geeft een JSON-lijst
(`[{...},{...}]`) terug als **één** object, de lijst zelf. `Where-Object id -EQ 'node-a'` op dat ene object vond dus
nooit iets. Daarom komt het antwoord eerst in een variabele:

```powershell
$response = Invoke-RestMethod @request
return $response
```

Een lijst in een variabele die je teruggeeft, stuurt PowerShell item per item door, zoals elk commando doet. De
mocks in de unit-tests gaven al losse items terug; alleen de `LocalHttp`-test met een echte HTTP-server laat het zien.

## 4. Waarom zo

- **Eén functie voor alle API-oproepen.** Verandert NexusInfra iets aan de API of de authenticatie, dan pas je
  één plek aan; in tests mock je één ding (bedreiging *wijzigingen in NexusInfra* uit de SWOT).
- **Alleen `GET` opnieuw proberen.** Een `POST /nodes` waarvan het antwoord verloren ging, is misschien wél
  uitgevoerd. Nog eens sturen kan dan een dubbele registratie of een `409` geven. Lezen kun je veilig herhalen.
- **Wachten met verdubbeling** (*exponential backoff*): als het panel net opstart, geeft dat het wat ruimte in
  plaats van het meteen drie keer te bestoken.
- **De http-regel.** Het token geeft beheerrechten over je hele panel. Over het internet zonder TLS kan iemand
  onderweg het meelezen. Naar de eigen machine verlaat het verkeer de computer niet. Voor een vertrouwd
  thuisnetwerk zonder TLS kun je het bewust aanzetten. Zo is de veilige keuze de standaard (keuze K5).
- **Foutcodes in plaats van alleen tekst.** `Install-NexusNode` kan straks bijvoorbeeld bij
  `NexusApi.Conflict` anders reageren dan bij `NexusApi.Unreachable`, zonder op Engelse zinnen te zoeken.
- **Twee soorten tests.** De gemockte tests controleren de logica snel en volledig. Maar een mock doet wat
  jij denkt dat `Invoke-RestMethod` doet. De test tegen een echte, lokale HTTP-server vond drie problemen die de
  mocks niet zagen:
  1. `Invoke-RestMethod` weigert een token over `http://` (dus kwam de http-regel erbij);
  2. de reden van een netwerkfout bleef leeg, omdat `$_` binnen een `switch`-blok de waarde van de `switch` is
     en niet meer de fout (daarom `$caught`);
  3. bij een netwerkfout zet PowerShell zelf tekst in `ErrorDetails`, die dan als "NexusInfra says" verscheen.

  Elk probleem kreeg eerst een test die het liet zien, en pas daarna een oplossing.

## 5. PowerShell-concepten

- **`Invoke-RestMethod`** (`-Authentication Bearer`, `-Token`, `-TimeoutSec`, `-AllowUnencryptedAuthentication`):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/invoke-restmethod
- **Splatting van een hashtable** (`@request`): https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_splatting
- **`SecureString`:** https://learn.microsoft.com/dotnet/api/system.security.securestring
- **`$_` in `switch`** (de automatische variabele is daar de huidige waarde):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_switch
- **`$PSCmdlet.ThrowTerminatingError` en `ErrorRecord`:**
  https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-exceptions
- **`[uri]` en `IsLoopback`:** https://learn.microsoft.com/dotnet/api/system.uri.isloopback
- **Pester: `-ForEach` (een test met meerdere gevallen) en `Should -Throw -ErrorId`:**
  https://pester.dev/docs/usage/data-driven-tests

## 6. Zelf proberen

```powershell
. ./src/api/Invoke-NexusApi.ps1
$token = Read-Host -AsSecureString 'Token'        # typ iets, bv. nxi_test

# Een poort waar niets luistert: NexusApi.Unreachable, met de reden
Invoke-NexusApi -BaseUrl 'http://127.0.0.1:1' -Token $token -Method GET -Path '/nodes' -RetryCount 1 -Verbose

# http:// naar een andere host: geweigerd vóór er iets verstuurd wordt
Invoke-NexusApi -BaseUrl 'http://example.com' -Token $token -Method GET -Path '/me'
$Error[0].FullyQualifiedErrorId                   # NexusApi.UnencryptedNotAllowed,Invoke-NexusApi

# De tests: logica (gemockt) en echt HTTP (lokaal)
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests/api -Output Detailed
```

Zien wat `$_` in een `switch` doet:

```powershell
try { throw 'de echte fout' } catch {
    switch (1) { 1 { "in de switch is `$_ = $_" } }   # 1, niet de fout
    $caught = $_
    switch (1) { 1 { "bewaard: $caught" } }            # de echte fout
}
```

## 7. Controlevragen

1. Waarom probeert `Invoke-NexusApi` een `GET` wel opnieuw en een `POST` niet?
2. Wanneer stuurt de functie het token over gewone `http://`, en waarom niet altijd?
3. Waarom wordt de fout in de `catch` eerst in `$caught` bewaard?
4. Wat is het voordeel van een foutcode zoals `NexusApi.Conflict` boven alleen een tekst?
5. Welke problemen vond de test tegen de lokale HTTP-server die de gemockte tests niet vonden, en waarom
   konden die ze niet vinden?
