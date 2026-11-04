# Uitleg — index

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

Eén bestand per onderwerp. Elk bestand groeit mee wanneer de code van dat onderwerp verandert.

| Onderwerp | Bestand | Over |
|---|---|---|
| Module-opbouw | [module-opbouw.md](module-opbouw.md) | De mappenstructuur, de manifest en de loader |
| Kwaliteitscontrole | [kwaliteitscontrole.md](kwaliteitscontrole.md) | PSScriptAnalyzer-regels, de exporttest, de Pester-valkuil en de CI |
| Repository-instellingen | [repository-instellingen.md](repository-instellingen.md) | `.gitignore`, `.gitattributes` en waarom scripts LF nodig hebben |
| Parallel uitvoering | [parallel-uitvoering.md](parallel-uitvoering.md) | E2 (`-Parallel`, ThreadJob, Start-Job) en E3 (mocks in runspaces) |
| SSH-transport | [ssh-transport.md](ssh-transport.md) | E1: `ssh`, remoting en Posh-SSH; geheimen via stdin; de lab-doelhost |
| Logging | [logging.md](logging.md) | Run-context, `Write-NexusLog`, redactie, logs vanuit `-Parallel` |
| Configuratie | [configuratie.md](configuratie.md) | `config/nexusinfra.psd1`, lokale overschrijving, validatie |
| API-client | [api-client.md](api-client.md) | `Invoke-NexusApi`: token, herhalen, foutcodes, de http-regel, echte HTTP-tests |
| Experimenten in gewone taal | [experimenten-in-gewone-taal.md](experimenten-in-gewone-taal.md) | Wat E1–E4 moesten beslissen en waarom de voorstellen zo zijn, zonder vakjargon |
| Stappen en rollback | [stappen-en-rollback.md](stappen-en-rollback.md) | Stappencontract, de step runner, idempotentie, terugdraaien, dry run |
| Verbinden | [verbinden.md](verbinden.md) | `Connect-NexusInfra`, SecretManagement, de sessie, de help-test |
| Inventaris | [inventaris.md](inventaris.md) | `Import-NexusInventory`: JSON-formaat, defaults, controles, dubbels |
| Preflight | [preflight.md](preflight.md) | `Test-NexusHost`: de checks, het parallelle patroon in de praktijk, drie soorten tests |
| Installatie | [installatie.md](installatie.md) | `Install-NexusNode`: de vier stappen, geheimen naar de agent, `-WhatIf`, de nep-fleet, het node-lab |
| Status | [status.md](status.md) | `Get-NexusFleetStatus` en `Export-NexusFleetStatus`: twee kanten van een node, nooit stoppen, export |
| CI/CD | [ci-cd.md](ci-cd.md) | Testresultaten en dekking in CI, het buildscript, de release-workflow, schaaltests, het demoscript |
| Gedeelde hulpfuncties | [gedeelde-hulpfuncties.md](gedeelde-hulpfuncties.md) | De gedeelde lus per server (`Invoke-NexusHostLoop`), ssh- en API-parameters, `sleutel=waarde` lezen |
