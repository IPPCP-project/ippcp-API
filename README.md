# IPPCP API

This repository contains command-line automation for validating IPPCP data exchanges through an INESData data space.

A provider publishes an asset. A consumer discovers it, negotiates access, starts a transfer, retrieves an Endpoint Data Reference (EDR), and completes authorized Data Plane consumption. Depending on the asset profile, phase 4 either materializes a local download with manifest and SHA-256 (PRE GET Ingestion API, WFS, SPARQL) or records POST execution metadata only (PROD Ingestion API).

The current implementation is operated through Bash phase scripts. A final backend API is not presented as implemented.

## Start here

Follow the executable workshop from a clean clone:

**[docs/workshop.md](docs/workshop.md)**

That document is the Golden Path: machine setup, local credentials, Phase 0 through Phase 4, semantic validation, traceability, and evidence packaging.

## Zaragoza pilot for DSS4SC

This repository contains the Zaragoza technical data-space automation for the IPPCP pilot. It does not contain the Ljubljana implementation.

The current recommended path is `v2` `HttpData-PULL`:

```text
phase0 -> phase1 -> phase2 -> phase3 -> phase4
```

- Executable Golden Path: [docs/workshop.md](docs/workshop.md)
- Status reference: [docs/architecture.md](docs/architecture.md)

Validated profiles:

- Ingestion API PRE GET
- Ingestion API PROD POST — Industrias Ebro
- Ingestion API PROD POST — CIRCE
- WFS city
- WFS districts / juntas
- SPARQL Results JSON

Connector credentials, Ingestion API keys, and PROD request bodies are not stored in Git and must be provisioned separately by the corresponding deployment operator.

`v1`, `phase1b` / `phase3b` / `phase4b`, B2/CSV/InesDataStore, `test3`, configurations under `asset_configs/demo/` and `asset_configs/examples/`, and legacy SPARQL variants are not the recommended path.

## What you can run

Current assets use `v2` `HttpData-PULL`:

- Ingestion API v2 — **PRE GET** (validated phases 0–4, materialized response) and **PROD POST** (Industrias Ebro validated phases 0–4; CIRCE validated phases 0–4)
- WFS city
- WFS districts / juntas
- SPARQL Results JSON

Current lifecycle:

```text
phase0 -> phase1 -> phase2 -> phase3 -> phase4
```

| Role | Connector |
| --- | --- |
| Provider | `conn-citycouncil-ippcp` |
| Consumer | `conn-company-ippcp` |

Ingestion API uses `IPPCP_FLOW=ingesta`. WFS and SPARQL use `IPPCP_FLOW=consumo`.

## Access boundary

Running the validated flows requires network access to the configured connectors, provisioned technical users, local credentials, and valid configuration for the selected upstream resource. Those operational elements are not supplied by the repository. Without them, the repository remains a technical and automation reference, not a standalone EdD environment.

## Architecture

[![IPPCP logical architecture across city council and UPM infrastructures, provider and consumer connectors, and upstream data resources](docs/diagrams/ippcp-architecture.svg)](docs/diagrams/ippcp-architecture.svg)

[Architecture](docs/architecture.md) is the current source for actors, control and data planes, security boundaries, and implementation status.

## Reference documentation

Use these after the workshop, or when you need detail that the workshop does not repeat at length:

- [Getting started](docs/getting-started.md)
- [Execution phases](docs/execution-phases.md)
- [Ingestion API](docs/flows/ingestion-api.md)
- [WFS](docs/flows/wfs.md)
- [SPARQL](docs/flows/sparql.md)
- [Evidence and traceability](docs/evidence-and-traceability.md)
- [Evidence publication](docs/evidence-publication.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Authentication](docs/authentication.md)
- [Backend integration](docs/backend-integration.md)
- [Demo documentation](docs/demo/README.md)
- [Evidence tooling](tools/tools_README.md)

## Current and legacy versions

`v2` is current and recommended for new integrations.

Historical / reference only:

- CSV / B2 / InesDataStore
- `v1`
- `test3`
- `phase1b` / `phase3b` / `phase4b`

Do not mix legacy material into the workshop path.

## Security

Never commit or publish:

- provider or consumer passwords;
- connector tokens;
- Ingestion API keys;
- EDR authorization;
- OAuth client secrets;
- storage credentials;
- ignored local credential or environment files;
- current real `SUFFIX` values;
- raw business data.

Provider and consumer EdD credentials authenticate their configured connectors. Flow-specific upstream credentials protect a different network hop and must not be shared with the consumer.

## License and acknowledgements

This repository is developed in the context of the IPPCP project and its INESData data-space integration.

The repository is licensed under the [Apache License 2.0](LICENSE), which defines the applicable permissions and conditions. Related project attribution is recorded separately in [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md); it does not modify the license.
