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
