# src/steps — the installation steps

One file per step; each calls `Register-NexusStep` once when the module loads. `Install-NexusNode` runs them in
`Order`: `Docker` (10), `RegisterNode` (20), `AgentContainer` (30), `VerifyHealthy` (40). Adding, replacing
or removing a step is adding, replacing or removing a file here. How to write one: docs/development.md.
