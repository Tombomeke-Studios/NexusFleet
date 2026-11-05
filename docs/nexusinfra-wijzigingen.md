# NexusInfra — wijzigingen voor NexusFleet

NexusInfra ([Tombomeke-Studios/NexusInfra](https://github.com/Tombomeke-Studios/NexusInfra)) is een apart
project en wordt **niet** beoordeeld. Soms heeft NexusFleet een kleine aanpassing in NexusInfra nodig. Die
gebeurt in de NexusInfra-repository zelf, nooit vanuit deze repository, in aparte commits met het voorvoegsel
`fleet-support:`.

**Peilpunt:** de stand van NexusInfra bij de start van dit project is de git-tag `nexusfleet-baseline`
(versie 0.4.0). Alles wat sindsdien veranderde, toon je in de NexusInfra-repository met:

```powershell
git diff nexusfleet-baseline..HEAD
```

Elke wijziging krijgt hieronder één regel. Deze lijst maakt de scheiding tussen de twee projecten zichtbaar.

| Datum | Commit (NexusInfra) | Wat | Waarom NexusFleet dit nodig heeft |
|---|---|---|---|
| 2026-11-04 | `2c03a16` (NexusInfra #411) | `DELETE /nodes/:id` voor een node die niet bestaat antwoordt `404` in plaats van `500` | De rollback van `RegisterNode`, en later `Remove-NexusNode`, moeten "die node is er al niet meer" kunnen herkennen. Een `500` lijkt op een echte fout |
| 2026-11-04 | `b1f74e0` (NexusInfra #409) | De broker (RabbitMQ, 5672) is in beide bundels te publiceren met `BROKER_BIND` / `BROKER_PORT`; standaard alleen op `127.0.0.1` | Een agent op een andere machine moet de broker bereiken. Zonder dit moest je het compose-bestand zelf aanpassen voor elke VM-test |
| 2026-11-04 | `33c3e5f` (NexusInfra #410) | De installers maken een eigen broker-gebruiker met een willekeurig wachtwoord in plaats van `guest/guest` | RabbitMQ laat `guest` alleen toe vanaf de eigen machine, dus een agent op een VM werd altijd geweigerd |
| 2026-11-04 | `95e421a` (NexusInfra #414) | De installers vragen op welk adres de broker gepubliceerd wordt, en schrijven dat als `BROKER_BIND` | Zonder die vraag was een control plane voor agents op andere machines pas klaar na het met de hand aanpassen van `.env` |
| 2026-11-05 | `df55d7f` (NexusInfra #417) | undici als afhankelijkheid van de orchestrator | Nodig om de bestaande agent-aanroepen over een andere verbinding (de link) te sturen |
| 2026-11-05 | `e6a860d` (NexusInfra #417) | Het berichtformaat van de agent link en het multiplexen van streams (gedeelde code) | De basis van `reach: outbound`: één verbinding van de node draagt elke aanroep van NexusInfra naar de agent (K11, `docs/agent-link.md`) |
| 2026-11-05 | `acb1ce7` (NexusInfra #417) | Een heartbeat kan `connection: outbound` melden | De control plane moet weten dat zo'n node geen eigen adres heeft |
| 2026-11-05 | `c612c52` (NexusInfra #417) | De agent opent zelf de link (`AGENT_LINK_URL`, `AGENT_LINK_TOKEN`, `AGENT_LINK_ALLOW_INSECURE`) | `AgentContainer` start een outbound agent zonder open poort; die moet zelf naar buiten bellen |
| 2026-11-05 | `a9aa77b` (NexusInfra #417) | De database bewaart per node hoe hij bereikt wordt en de hash van zijn link-token | Een eigen token per node, waarvan alleen de hash bewaard wordt |
| 2026-11-05 | `c61b029` (NexusInfra #417) | Agent-aanroepen gaan over de link van de node | Zonder dit wordt een node achter NAT *healthy* maar kan NexusInfra hem niet besturen; `AgentReachable` (`GET /nodes/:id/disk`) bewijst dat het werkt |
| 2026-11-05 | `3ef519e` (NexusInfra #417) | `POST /nodes` aanvaardt `connection: outbound`; `POST /nodes/:id/link-token` maakt het token | `RegisterNode` registreert een outbound host, `AgentContainer` vraagt zijn token |
| 2026-11-05 | `962ce4e` (NexusInfra #417) | De orchestrator aanvaardt links (token per node) en de console werkt erover | Alleen de juiste node mag zijn link openen; de console moet ook op een outbound node werken |
| 2026-11-05 | `15484b1` (NexusInfra #417) | `GET /config` meldt `features: ["agent-link"]` | `Connect-NexusInfra` en de preflight (`AgentLink`) zien zo of de control plane de link kent |
| 2026-11-05 | `e05eece` (NexusInfra #417) | De gateway stuurt `/agent-link` door naar de orchestrator | De agent belt hetzelfde publieke adres (en met TLS poort 443) als het panel |
| 2026-11-05 | `55ba60b` (NexusInfra #417) | Een geweigerde link wordt één keer gelogd, niet twee keer | Duidelijkere logs van de agent bij een fout token |
| 2026-11-05 | `c383ca8` (NexusInfra #417) | Documentatie van de agent link | De installatie zonder NexusFleet moet ook beschreven zijn |
| 2026-11-05 | `ef551a9` (NexusInfra #417) | De codekaart en TODO van NexusInfra bijgewerkt | Onderhoud van de NexusInfra-repo zelf |
