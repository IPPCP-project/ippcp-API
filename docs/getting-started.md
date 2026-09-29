# Getting Started

This is a reference document. The executable Golden Path from a clean clone is [workshop.md](workshop.md).

## Purpose

This guide records setup details, flow selection, and result locations for the IPPCP API automation. The repository publishes upstream resources through provider and consumer data-space connectors, negotiates access, obtains an Endpoint Data Reference (EDR), and completes authorized Data Plane consumption. Phase 4 has two result modes: **materialized response** (PRE GET Ingestion API, WFS, SPARQL — download, manifest, SHA-256) and **POST metadata-only** (PROD Ingestion API — HTTP 2xx control metadata, no persisted request/response bodies). Both Ingestion API profiles remain `HttpData-PULL`.

## Supported flows

The current public flows are:

- [Ingestion API](flows/ingestion-api.md): protected JSON API through `HttpData-PULL`;
- [WFS](flows/wfs.md): current city and district-board GeoJSON layers;
- [SPARQL](flows/sparql.md): SPARQL Results JSON through `HttpData-PULL`.

`v2` is current and recommended. `v1` remains legacy-supported but is not used by this guide. `test3`, discarded experiments, upstream JWT authentication, and old workshop procedures are non-current.

The PRE GET profile and PROD POST profile (Industrias Ebro phases 0–4; CIRCE phases 0–4) are validated Ingestion API paths. PRE and PROD are environment profiles, not universal deployment requirements; another environment needs its own connector and upstream configuration.

## Prerequisites

- Bash 4.3 or newer.
- `curl` and `jq`.
- Python 3, recommended for robust JWT claim diagnostics.
- Git.
- Network access to the configured EdD connectors and selected upstream resource.
- Provider and consumer EdD technical credentials provisioned for the configured dataspace/connectors.

The current connector login uses technical users that can complete the configured non-interactive authentication flow. Do not place passwords or tokens in commands.

On systems where the default Bash is older, select a newer executable:

```bash
export BASH_BIN="<path-to-bash-4.3-or-newer>"
"${BASH_BIN}" --version
command -v curl jq python3
```

The flow guides use `${BASH_BIN:-$(command -v bash)}` when `BASH_BIN` is not explicitly set.

## Clone the repository

Clone the public repository:

```bash
git clone https://github.com/IPPCP-project/ippcp-API.git
cd ippcp-API
```

Run all commands from the repository root. It contains `endpoints.sh`, `export_suffix.sh`, and `scripts/lib_common.sh`.

## Prepare EdD credentials

The repository keeps ignored credential files beside the selected `v2` flow configuration:

```text
flujos/ippcp/v2/ingesta/user_provider.sh
flujos/ippcp/v2/ingesta/user_consumer.sh
flujos/ippcp/v2/consumo/user_provider.sh
flujos/ippcp/v2/consumo/user_consumer.sh
```

Create the files you need from the adjacent `.example.sh` templates:

```bash
export IPPCP_FLOW="<ingesta-or-consumo>"
credential_dir="flujos/ippcp/v2/${IPPCP_FLOW}"

cp "${credential_dir}/user_provider.example.sh" "${credential_dir}/user_provider.sh"
cp "${credential_dir}/user_consumer.example.sh" "${credential_dir}/user_consumer.sh"
```

Edit the copied files locally using the variable names provided by the templates.

These files implement the repository layout; they do not imply that each supported data flow requires different EdD users. The provider credentials are associated with the configured provider connector, and the consumer credentials are associated with the configured consumer connector. The same provisioned technical user may be reused where connector policy permits.

See [Authentication](authentication.md) for credential ownership, token lifetime, and secret boundaries.

## Prepare flow-specific upstream secrets

Upstream secrets are separate from EdD connector credentials and are required only by flows whose provider resource needs them.

The current Ingestion API profiles require a provider-side API key during phase 1. PRE GET also requires a numeric provider identifier when the config does not embed `provider_id`. Create ignored local environments from:

```text
data/real/ingesta/auth/ingesta_api_key.env.example       # PRE GET
data/real/ingesta/auth/ingesta_api_key_prod.env.example  # PROD POST
```

PROD POST phase 4 additionally requires a local request body file via `INGESTA_API_REQUEST_BODY_FILE` (not versioned in Git). The [Ingestion API guide](flows/ingestion-api.md) defines when to source and remove those variables. WFS and SPARQL do not use the Ingestion API secret files.

## Select dataspace, flow, and version

Always select the active dataspace explicitly:

```bash
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW="<ingesta-or-consumo>"
export IPPCP_FLOW_VERSION=v2
```

Use:

- `IPPCP_FLOW=ingesta` for Ingestion API;
- `IPPCP_FLOW=consumo` for WFS or SPARQL.

WFS and SPARQL are distinguished by `ASSET_CONFIG` in their flow guides. Do not rely on implicit dataspace fallback and do not select `test3`.

The effective flow directory is:

```text
flujos/ippcp/${IPPCP_FLOW_VERSION}/${IPPCP_FLOW}/
```

## Connector endpoint composition

Provider and consumer connector base URLs come from the selected dataspace and flow configuration.

[`endpoints.sh`](../endpoints.sh) is the canonical source only for the relative request/list paths it declares for:

- assets;
- policy definitions;
- contract definitions;
- contract agreements;
- transfer processes;
- vocabularies.

The effective Management API URL is:

```text
connector base URL + operation path
```

Operations not declared in `endpoints.sh` remain defined in their owning phase scripts. See [Architecture](architecture.md) for the current endpoint-source boundary.

## Select a flow

The executable copy/paste path is [workshop.md](workshop.md). Read the selected flow reference before treating a custom variation as supported:

- [Run Ingestion API](flows/ingestion-api.md)
- [Run WFS](flows/wfs.md)
- [Run SPARQL](flows/sparql.md)

Each guide supplies the current `ASSET_CONFIG`, required upstream variables, complete command block, semantic download checks, and flow-specific errors.

## Minimal quick start

The minimal common start resolves context, authenticates both connector roles, performs connector smoke checks, and creates the run:

```bash
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW="<ingesta-or-consumo>"
export IPPCP_FLOW_VERSION=v2

bash_bin="${BASH_BIN:-$(command -v bash)}"
"${bash_bin}" scripts/phase0_context_smoke.sh
source runtime/env/latest/phase0_env.sh
```

Stop if phase 0 fails. Do not source a missing or stale phase environment.

Continue with the complete block in the selected flow guide. The common sequence is:

```text
phase0 -> phase1 -> phase2 -> phase3 -> phase4
```

The state hand-off is:

```text
phase0_env.sh -> phase1_env.sh -> phase2_env.sh -> phase3_env.sh
```

Each phase environment must carry the same `SUFFIX`. Phase 4 is terminal and does not create `phase4_env.sh`.

At a high level:

1. phase 0 resolves context and EdD authentication;
2. phase 1 publishes the provider asset and offer;
3. phase 2 negotiates and obtains the agreement;
4. phase 3 starts the transfer and retrieves an EDR;
5. phase 4 re-fetches the EDR and completes Data Plane consumption — either materializing a download with manifest and SHA-256, or recording POST metadata-only control artifacts.

[Execution phases](execution-phases.md) is the canonical source for inputs, outputs, inherited variables, phase 4 result modes, and implemented restart controls.

## Locate the results

The functional run identifier is `run_id`, currently represented by `SUFFIX`.

Run evidence is stored under:

```text
evidencias/runs/${SUFFIX}/
```

Important locations:

```text
evidencias/runs/${SUFFIX}/summary.json
evidencias/runs/${SUFFIX}/phase0/
evidencias/runs/${SUFFIX}/phase1/
evidencias/runs/${SUFFIX}/phase2/
evidencias/runs/${SUFFIX}/phase3/
evidencias/runs/${SUFFIX}/phase4/
downloads/assets/${ASSET_ID}/${SUFFIX}.${ASSET_EXTENSION}          # materialized-response flows only
downloads/manifests/${ASSET_ID}/${SUFFIX}.manifest.json            # materialized-response flows only
evidencias/runs/${SUFFIX}/phase4/post_result.json                  # PROD POST metadata-only
evidencias/runs/${SUFFIX}/phase4/post_manifest.json                # PROD POST metadata-only
```

`summary.json` records phase and step status. Phase artifacts retain request results, HTTP status, and redacted diagnostics. For materialized-response flows, the download manifest correlates the asset, agreement, transfer, byte count, media type, and SHA-256. For PROD POST metadata-only phase 4, inspect `post_result.json` / `post_manifest.json` (`manifest_kind=post_metadata_only`); do not expect a GET-style download or response SHA-256.

`latest.*` files are mutable local conveniences. Use the run-specific download, manifest, asset ID, and run metadata for durable traceability.

See [Evidence and traceability](evidence-and-traceability.md) for integrity and publication rules.

## Documentation map

Executable path:

1. [Workshop](workshop.md)

Before execution, as reference:

1. [Architecture](architecture.md)
2. [Authentication](authentication.md)
3. [Execution phases](execution-phases.md)
4. [Evidence and traceability](evidence-and-traceability.md)

For operation:

- [Ingestion API](flows/ingestion-api.md)
- [WFS](flows/wfs.md)
- [SPARQL](flows/sparql.md)
- [Troubleshooting](troubleshooting.md)

For future backend integration boundaries:

- [Backend integration](backend-integration.md)

## Security

Never place passwords, tokens, API keys, EDR credentials, or local credential files in Git. Do not paste secrets into commands, documentation, screenshots, or evidence bundles.

Generated phase environments, evidence, and downloads remain local. Review redaction and publication policy before sharing any artifact.

If execution fails, use [Troubleshooting](troubleshooting.md) and inspect only redacted artifacts. Do not reproduce internal EDR authorization attempts manually.
