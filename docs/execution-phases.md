# Execution Phases

This is a reference document. Copy-and-paste execution from a clean clone is in [workshop.md](workshop.md).

## Purpose

This document is the canonical definition of the current `phase0` to `phase4` execution model.

The current and recommended path is a clean `v2` `HttpData-PULL` execution:

```text
phase0 -> phase1 -> phase2 -> phase3 -> phase4
```

`v1` remains legacy-supported but is not recommended for new integrations. The B2/CSV/InesDataStore path is a separate delivered T1 evidence baseline and does not use this phase 4 download path.

## Prerequisites

Run commands from the repository root with:

- Bash 4.3 or newer;
- `curl` and `jq`;
- Python 3 when available;
- network access to the configured connectors and upstream resource;
- ignored local provider and consumer credential files;
- any flow-specific provider secret loaded locally.

See [Authentication](authentication.md) for credential placeholders and secret-loading rules.

## Flow resolution

Every phase calls the shared environment loader in [`scripts/lib_common.sh`](../scripts/lib_common.sh).

### Dataspace

`IPPCP_DATASPACE` selects:

```text
flujos/<dataspace>/export_dataspace.sh
```

For current IPPCP executions:

```bash
export IPPCP_DATASPACE=ippcp
```

Advanced overrides are available through `IPPCP_DATASPACE_DIR` and `IPPCP_DATASPACE_FILE`. They are troubleshooting mechanisms, not the standard public path.

### Flow and version

The IPPCP dataspace resolves the flow directory as:

```text
flujos/ippcp/${IPPCP_FLOW_VERSION}/${IPPCP_FLOW}
```

Select a current flow explicitly:

```bash
export IPPCP_FLOW="<ingesta-or-consumo>"
export IPPCP_FLOW_VERSION=v2
```

For the `ippcp` dataspace, `IPPCP_FLOW_VERSION` defaults to `v2` when unset. Explicit selection is recommended for reproducibility.

Valid project versions are:

- `v2`: current and recommended;
- `v1`: legacy-supported and not recommended.

`IPPCP_FLOW_DIR` is an advanced explicit override. `test3` is historical and must not be selected for a current execution.

### Run identifier

If no `SUFFIX` exists, the shared loader creates one. `SUFFIX` is the current functional representation of `run_id` and identifies:

- generated connector object IDs;
- the run evidence directory;
- phase environment hand-offs;
- the run summary;
- materialized download metadata.

When a phase environment is sourced, the existing `SUFFIX` is reused. See [Evidence and traceability](evidence-and-traceability.md).

## Phase 0: context and authentication

Script: [`scripts/phase0_context_smoke.sh`](../scripts/phase0_context_smoke.sh)

### Purpose

- resolves the selected dataspace, version, and flow;
- loads provider and consumer configuration;
- authenticates both connector users;
- performs connector smoke checks;
- creates the run context.

### Inputs

- `IPPCP_DATASPACE`;
- `IPPCP_FLOW`;
- `IPPCP_FLOW_VERSION`;
- selected flow exports;
- local `user_provider.sh` and `user_consumer.sh`.

### Outputs and inherited state

`phase0_env.sh` exports:

- `SUFFIX`;
- dataspace, flow, and version selection;
- provider and consumer connector names;
- provider and consumer Management API base URLs;
- provider and consumer protocol addresses.

It does not export passwords or JWTs.

### Evidence

Representative phase 0 artifacts include:

- redacted provider and consumer JWT claims;
- provider asset-list smoke response and HTTP metadata;
- consumer asset-list smoke response and HTTP metadata;
- context diagnostics.

The exact artifacts are stored under:

```text
evidencias/runs/${SUFFIX}/phase0/
```

## Phase 1: publication

Script: [`scripts/phase1_provider_publish.sh`](../scripts/phase1_provider_publish.sh)

### Purpose

- vocabulary;
- access and contract policies;
- asset and data address;
- contract definition.

It also verifies the published asset and checks that it is present in the provider's own catalog.

### Inputs

- state from `phase0_env.sh`;
- `ASSET_CONFIG` for the selected `HttpData-PULL` resource;
- provider-side upstream credentials when required by the asset configuration.

For current public flows, `ASSET_CONFIG` must point to a canonical Ingestion API, WFS, or SPARQL configuration. Every current Ingestion API profile requires `INGESTA_API_KEY` in the local environment during phase 1. PRE GET does not embed `provider_id`, so it also requires `INGESTA_API_PROVIDER_ID`. PROD POST embeds `provider_id` in the company asset configuration, so `INGESTA_API_PROVIDER_ID` is not required. The current profiles do not use an upstream JWT.

### Outputs and inherited state

`phase1_env.sh` exports:

- `SUFFIX`;
- `VOCAB_ID` when applicable;
- `ACCESS_POLICY_ID`;
- `CONTRACT_POLICY_ID`;
- `ASSET_ID`;
- `CD_ID`;
- selected flow and non-secret asset metadata.

The Ingestion API key is not exported.

### Evidence

Representative phase 1 artifacts include:

- redacted JWT claims;
- vocabulary, policy, asset, and contract-definition request/response artifacts;
- asset retrieval;
- contract-definition list;
- provider self-catalog request;
- catalog asset match;
- a redacted effective asset configuration.

The real data-address request is handled as temporary sensitive material. Persisted artifacts redact `header:X-Api-Key`.

## Phase 2: negotiation

Script: [`scripts/phase2_consumer_negotiate.sh`](../scripts/phase2_consumer_negotiate.sh)

### Purpose

- requests the provider catalog;
- selects the asset and offer;
- starts contract negotiation;
- polls negotiation state;
- obtains the agreement.

### Inputs

- state from `phase1_env.sh`;
- `ASSET_ID`;
- provider protocol address;
- consumer connector credentials loaded from the selected flow.

### Outputs and inherited state

`phase2_env.sh` exports:

- `SUFFIX`;
- `ASSET_ID`;
- `PROVIDER_PARTICIPANT_ID`;
- `OFFER_POLICY_ID`;
- `CATALOG_ASSET_ID`;
- `NEG_ID`;
- `AGREEMENT_ID`;
- selected flow and non-secret asset metadata.

### Evidence

Representative phase 2 artifacts include:

- redacted consumer JWT claims;
- remote catalog request and response;
- selected catalog identifiers;
- contract-negotiation response;
- negotiation polling responses and final state;
- contract-agreement item and list responses.

## Phase 3: transfer and EDR

Script: [`scripts/phase3_transfer_edr.sh`](../scripts/phase3_transfer_edr.sh)

### Purpose

- starts an `HttpData-PULL` transfer;
- waits for an accepted transfer state;
- retrieves an EDR;
- persists only redacted EDR diagnostics.

Phase 3 ends at transfer plus resolvable EDR. Data download in phase 3 is an explicit compatibility option and is not the current execution model.

### Inputs

- state from `phase2_env.sh`;
- `ASSET_ID`;
- `AGREEMENT_ID`;
- provider protocol address;
- consumer connector credentials loaded from the selected flow.

### Outputs and inherited state

`phase3_env.sh` exports:

- `SUFFIX`;
- inherited publication and negotiation identifiers;
- `TRANSFER_ID`;
- `EDR_URL` only when it is safe to persist;
- selected flow and non-secret asset metadata.

EDR authorization material is not exported.

### Evidence

Representative phase 3 artifacts include:

- redacted consumer JWT claims;
- transfer creation response;
- transfer polling responses and final state;
- redacted EDR data address;
- EDR key-name diagnostics without credential values;
- an internal record that phase 3 data consumption was skipped.

Direct EDR retrieval is attempted first. The script can query the EDR collection as an internal retrieval fallback. These are implementation details, not alternative operator procedures.

## Phase 4: data consumption and verification

Script: [`scripts/phase4_save_download.sh`](../scripts/phase4_save_download.sh)

Phase 4 has two result modes. Both use the same EDC transfer type (`HttpData-PULL`); the difference is upstream HTTP method and what is persisted locally.

### Result — materialized response

Used by PRE GET Ingestion API, WFS, and SPARQL:

- re-authenticates the consumer;
- retrieves the current EDR;
- performs a Data Plane GET;
- persists the response body locally;
- creates a download artifact, manifest, and SHA-256 hash;
- updates the run summary.

### Result — POST metadata-only

Used by PROD Ingestion API:

- re-authenticates the consumer;
- retrieves the current EDR;
- sends a POST with a local request body file (`INGESTA_API_REQUEST_BODY_FILE`);
- persists HTTP result/control metadata only (`post_result.json`, `post_manifest.json`);
- does **not** persist request or response bodies;
- does **not** create a GET-style download under `downloads/assets/` or a response SHA-256;
- success is `curl` exit 0 plus HTTP 2xx.

See [Ingestion API](flows/ingestion-api.md) for PROD POST operator checks and company-specific request-body requirements.

### Purpose (common)

### Inputs

- state from `phase3_env.sh`;
- `TRANSFER_ID`;
- asset content kind, extension, and media type;
- consumer connector credentials loaded from the selected flow.

Phase 4 retrieves the EDR again at runtime. It does not require a stored EDR credential.

For PRE GET Ingestion API, WFS, and SPARQL, execute phase 4 normally. The provider asset data address already contains upstream configuration for the Data Plane request. For PROD POST Ingestion API, set `INGESTA_API_REQUEST_BODY_FILE` before phase 4. The historical upstream JWT mode is not part of a clean current v2 execution.

### EDR authorization behavior

The validated EDR form observed in the current environment places the complete header value in the EDR `authorization` field. The script's `authorization_raw` candidate sends that value unchanged.

The scripts can internally try `authKey`/`authCode`, Bearer-prefixed, or explicit auth-type candidates for compatibility. Operators must not add those variants manually or treat them as required flow steps.

### Outputs

**Materialized response** creates:

```text
evidencias/runs/${SUFFIX}/phase4/40_data_response.${ASSET_EXTENSION}
downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION}
downloads/manifests/${ASSET_ID}/latest.manifest.json
```

The manifest includes the SHA-256 hash and traceability metadata.

**POST metadata-only** creates control metadata such as:

```text
evidencias/runs/${SUFFIX}/phase4/post_result.json
evidencias/runs/${SUFFIX}/phase4/post_manifest.json
```

It does not create GET-style downloads or a response SHA-256.

The run `summary.json` records phase 4 completion in both modes. Phase 4 does not create `phase4_env.sh`.

### Evidence

Representative phase 4 artifacts include:

- redacted consumer JWT claims;
- redacted runtime EDR data address;
- EDR key-name diagnostics;
- per-attempt response artifacts and status summary;
- **materialized response:** the accepted material response, download manifest, and SHA-256 metadata;
- **POST metadata-only:** `post_result.json` / `post_manifest.json` with `manifest_kind=post_metadata_only`, HTTP status, and byte counts — not request/response bodies.

## Environment hand-off

Each phase must source the environment generated by the preceding phase:

```text
phase0_env.sh -> phase1_env.sh -> phase2_env.sh -> phase3_env.sh
```

Run-specific copies under `evidencias/runs/${SUFFIX}/` are the historical source of truth. `runtime/env/latest/` is a mutable convenience location for the most recently exported phase state.

Before continuing an execution, verify that every sourced file contains the expected `SUFFIX`. Do not combine phase files from different runs.

Phase files exchange execution state, not credentials. See [Backend integration](backend-integration.md) for the future persisted-state replacement.

## Runnable clean v2 executions

The executable copy/paste path is [workshop.md](workshop.md). Status classification is in [architecture.md](architecture.md). The following blocks remain condensed reference from the repository root. They contain no credential values.

Validated profiles, aligned with the workshop:

- Ingestion API PRE GET
- Ingestion API PROD POST — Industrias Ebro
- Ingestion API PROD POST — CIRCE
- WFS city
- WFS districts / juntas
- SPARQL Results JSON

### Select the resource

PRE GET Ingestion API:

```bash
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=ingesta
export IPPCP_FLOW_VERSION=v2
export ASSET_CONFIG="asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json"
```

PROD POST Ingestion API. Select one company configuration. `provider_id` is embedded in the configuration, so `INGESTA_API_PROVIDER_ID` is not required:

```bash
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=ingesta
export IPPCP_FLOW_VERSION=v2
export ASSET_CONFIG="asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json"
# or: asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json
```

Validated WFS layers. Select exactly one:

```bash
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=consumo
export IPPCP_FLOW_VERSION=v2
export ASSET_CONFIG="asset_configs/real/consumo/wfs/emisiones_wfs_ciudad_geojson.json"
# or: asset_configs/real/consumo/wfs/emisiones_wfs_juntas_geojson.json
```

Validated SPARQL Results JSON configuration:

```bash
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=consumo
export IPPCP_FLOW_VERSION=v2
export ASSET_CONFIG="asset_configs/real/consumo/sparql/emisiones_sparql_limit10_format_json.json"
```

### Run the Ingestion API phases

The PRE GET block below loads the PRE secret file only while phase 1 publishes the provider data address. `INGESTA_API_KEY` and `INGESTA_API_PROVIDER_ID` are removed before phase 2 and are not inherited by phases 2–4.

PROD POST uses the same phase sequence with `ingesta_api_key_prod.env` during phase 1 and does not require `INGESTA_API_PROVIDER_ID`. Phase 4 additionally requires `INGESTA_API_REQUEST_BODY_FILE`, a local company-specific body that is not versioned in Git. Use the company configuration selected above. The workshop owns the copy-paste PROD execution.

```bash
run_ingestion_pre_get_phases() {
  local bash_bin
  bash_bin="${BASH_BIN:-$(command -v bash)}"

  "${bash_bin}" scripts/phase0_context_smoke.sh || return 1

  source runtime/env/latest/phase0_env.sh
  source data/real/ingesta/auth/ingesta_api_key.env
  export ASSET_CONFIG="asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json"

  if ! "${bash_bin}" scripts/phase1_provider_publish.sh; then
    unset INGESTA_API_KEY INGESTA_API_PROVIDER_ID
    return 1
  fi
  unset INGESTA_API_KEY INGESTA_API_PROVIDER_ID

  source runtime/env/latest/phase1_env.sh
  "${bash_bin}" scripts/phase2_consumer_negotiate.sh || return 1

  source runtime/env/latest/phase2_env.sh
  "${bash_bin}" scripts/phase3_transfer_edr.sh || return 1

  source runtime/env/latest/phase3_env.sh
  "${bash_bin}" scripts/phase4_save_download.sh || return 1
}

run_ingestion_pre_get_phases
unset -f run_ingestion_pre_get_phases
```

See [Ingestion API](flows/ingestion-api.md) for the complete flow-specific configuration, validation, and error handling.

### Run the WFS or SPARQL phases

After selecting either validated WFS layer or the validated SPARQL configuration:

```bash
BASH_BIN="${BASH_BIN:-$(command -v bash)}"

"${BASH_BIN}" scripts/phase0_context_smoke.sh

source runtime/env/latest/phase0_env.sh
"${BASH_BIN}" scripts/phase1_provider_publish.sh

source runtime/env/latest/phase1_env.sh
"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh

source runtime/env/latest/phase2_env.sh
"${BASH_BIN}" scripts/phase3_transfer_edr.sh

source runtime/env/latest/phase3_env.sh
"${BASH_BIN}" scripts/phase4_save_download.sh
```

Each phase stops on failure. Do not continue until the failed phase has been diagnosed and its output state is valid.

## Restart and overwrite behavior

- `PHASE2_FORCE=1` allows phase 2 to start a new negotiation when state already exists.
- `PHASE3_FORCE=1` allows phase 3 to start a new transfer when state already exists.
- `PHASE3_RESUME=1` resumes EDR retrieval for the existing transfer instead of creating another transfer.
- `DOWNLOAD_FORCE=1` allows phase 4 to replace an existing materialized download when content differs.

These flags are recovery controls. They must be used only after checking the current `SUFFIX`, identifiers, `summary.json`, and phase evidence.

## Operation path ownership

Connector base URLs come from flow configuration. [`endpoints.sh`](../endpoints.sh) owns only the relative request/list paths declared there. Operations not declared there remain owned by their phase scripts:

- publication and provider self-catalog: phase 1;
- remote catalog, negotiation, and agreement retrieval: phase 2;
- transfer creation/state and EDR retrieval: phase 3;
- runtime EDR retrieval: phase 4.

This is a known path-centralization gap. Do not copy operation paths from the scripts into independently maintained documentation constants.

Flow-specific inputs are documented in:

- [Workshop](workshop.md)
- [Ingestion API](flows/ingestion-api.md)
- [WFS](flows/wfs.md)
- [SPARQL](flows/sparql.md)
