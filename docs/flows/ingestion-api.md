# Ingestion API Flow

This is a flow-specific reference. The executable Golden Path is [workshop.md](../workshop.md).

## Purpose

This guide defines the current Ingestion API flow-specific configuration and operator checks. The common lifecycle is defined in [Execution phases](../execution-phases.md), and credential ownership is defined in [Authentication](../authentication.md).

## Scope

- Flow version: `v2`, current and recommended.
- Transfer type: `HttpData-PULL` (including the PROD POST profile).
- Data address type: `HttpData`.
- Provider: city council connector.
- Consumer: company connector.
- Profiles:
  - **PRE GET** — validated end-to-end through phase 4 download and manifest.
  - **PROD POST** — new publication/consumption profile; requires a local request body file at phase 4.

PROD asset ids use `pull` because the EDC transfer type is `HttpData-PULL`. The upstream HTTP method is `POST` on the `HttpData` data address. `POST` is not `HttpData-PUSH`.

Operational asset ids used by Geoslab:

| Environment | Company | Asset id |
| --- | --- | --- |
| PRE | Industrias Ebro | `ippcp-ingesta-pull-industrias-ebro` |
| PRE | CIRCE | `ippcp-ingesta-pull-circe` |
| PROD | Industrias Ebro | `ippcp-ingesta-pull-industrias-ebro-prod` |
| PROD | CIRCE | `ippcp-ingesta-pull-circe-prod` |

Do not rename the PRE ids to `*-pre`; they are already in use. PROD is distinguished by the `-prod` suffix.

Concrete hosts appear only in versioned asset configs already allowed by repository policy. Secrets, JWTs, API keys, and business payloads are intentionally excluded from documentation and Git.

## Upstream resource

### PRE GET (validated)

The upstream resource is a JSON Ingestion API exposed through the provider asset. The Data Plane performs an HTTP GET to that resource after validating the consumer's EDR authorization.

The upstream hop requires:

- `X-Api-Key`;
- `X-Provider-Id`.

These headers belong to the provider data address. They are not consumer request parameters.

### PROD POST (current validated profile)

Same transfer type (`HttpData-PULL`) and data address type (`HttpData`). Upstream endpoint for both companies:

```text
https://idezar-sig.zaragoza.es/servicios/ippcp-ingesta/api/intake
```

The published data address additionally sets:

- `method=POST`;
- `proxyBody=true` so the consumer body and `Content-Type` reach the upstream API.

HTTP `POST` is not EDC `HttpData-PUSH`. The transfer remains `HttpData-PULL`.

One stable asset per company because `X-Provider-Id` is fixed per published data address:

| Company | Asset id | `provider_id` (`X-Provider-Id`) | Config |
| --- | --- | --- | --- |
| Industrias Ebro | `ippcp-ingesta-pull-industrias-ebro-prod` | `1` | `asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json` |
| CIRCE | `ippcp-ingesta-pull-circe-prod` | `2` | `asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json` |

`provider_id` is non-secret metadata embedded in each company config so the stable asset cannot be published with the wrong `X-Provider-Id`. Config `provider_id` takes precedence over a stale `INGESTA_API_PROVIDER_ID` in the shell environment.

`X-Api-Key` is a provider-side / runtime secret loaded only for phase 1. It is stored in the provider data address, is never delivered to the consumer, and must not appear in documentation, logs, or evidence.

Validation status (functional):

- Industrias Ebro PROD: phases 0–4 validated (POST metadata-only phase 4).
- CIRCE PROD: phases 0–4 validated (POST metadata-only phase 4).
- PROD request bodies are company-specific: Industrias Ebro uses `centerId`, while CIRCE uses `districtCode`. Do not reuse one company's payload for the other.

## Flow-specific configuration

### PRE GET (current validated path)

```text
asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json
```

It declares:

- `type=HttpData`;
- JSON content and `.json` output;
- `requires_api_key_header=true`;
- `requires_provider_id_header=true`.

No explicit `http_method` or `proxy_body` (upstream GET behavior unchanged).

### PROD POST

```text
asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json
asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json
```

They declare stable `asset_id`, `http_method=POST`, `proxy_body=true`, `provider_id`, and the same API-key / provider-id header flags.

The ignored local environment file is:

```text
data/real/ingesta/auth/ingesta_api_key.env
```

Create it from:

```text
data/real/ingesta/auth/ingesta_api_key.env.example
```

For PROD POST, use a separate ignored file so PRE and PROD keys can diverge without touching the validated PRE path:

```text
data/real/ingesta/auth/ingesta_api_key_prod.env
```

Create it from:

```text
data/real/ingesta/auth/ingesta_api_key_prod.env.example
```

Do not commit either local file or place its values in commands, documentation, logs, screenshots, or evidence. Do not assume PRE and PROD API keys are identical.

## Flow-specific variables

Required during phase 1:

| Variable | Requirement |
| --- | --- |
| `ASSET_CONFIG` | PRE GET or one PROD POST company config |
| `INGESTA_API_KEY` | Non-empty local API key for the target environment |
| `INGESTA_API_PROVIDER_ID` | Required only when the config does not embed `provider_id` (PRE GET) |

`INGESTA_API_PROVIDER_ID` / config `provider_id` belong to the published asset configuration. They are not Keycloak UUIDs.

Required during phase 4 for PROD POST only:

| Variable | Requirement |
| --- | --- |
| `INGESTA_API_REQUEST_BODY_FILE` | Path to a local JSON body file (not versioned in Git) |

Internally handled:

- phase 1 adds `header:X-Api-Key` and `header:X-Provider-Id` to the real provider data address;
- phase 1 emits `method` / `proxyBody` only when configured;
- persisted phase 1 evidence replaces the API-key value with `<redacted>`;
- the API key is not exported through `phase1_env.sh`;
- phases 2–3 do not require Ingestion API secrets;
- phase 4 POST sends `Content-Type` and body to the EDR URL; the body is not copied into summary or control evidence.

## Authentication boundary

The asset does not contain an expiring upstream JWT. The API key is loaded immediately before phase 1 and stored in the provider connector's data address for the assessment.

The consumer connector and a future consumer backend do not receive this API key. They receive an EDR for the separate consumer-to-Data Plane hop. Phase 4 therefore runs normally without additional upstream-authentication flags. For POST, the consumer supplies only the business request body file.

See [Authentication](../authentication.md) for the complete boundary and persistence model.

### Evidence-profile rationale

T1–T4 are presentation slots, not asset types. The evidence tools classify each run and apply that asset's `publication_profile`. The current Ingestion API v2 asset uses `minimal_publication` (`publication_safe=true`). WFS, SPARQL, and the historical CSV/B2 baseline currently use `standard` (`publication_safe=false`).

The provider-side `X-Api-Key` and `X-Provider-Id` values stay inside the provider boundary. They are not public values, are not sent to the consumer, are not propagated through the EDR, and are not dynamically obtained by the evidence tools. They must not appear in evidence packages, workbooks, or public examples.

See [workshop.md](../workshop.md), [Evidence and traceability](../evidence-and-traceability.md), and the [Evidence Publication Policy](../evidence-publication.md) for the export boundary.

## Phase 1 behavior

Phase 1:

1. validates the asset configuration;
2. requires a non-empty API key and a numeric provider ID (from config `provider_id` or `INGESTA_API_PROVIDER_ID`);
3. builds a temporary publication payload containing upstream headers and optional `method` / `proxyBody`;
4. publishes the immutable asset and data address;
5. persists only redacted evidence;
6. exports non-secret execution state (`ASSET_HTTP_METHOD`, `ASSET_PROXY_BODY` when set).

Changing the provider ID or rotating the API key requires publication of a new asset with a new execution identifier. Reusing the existing immutable asset would retain its previous data address. Stable PROD asset ids are company-fixed; republishing the same id after a secret rotation still requires connector-side replacement procedures outside this guide.

## Optional direct upstream preflight

This preflight is separate from the phase0–phase4 pipeline. It validates the currently available PRE profile without publishing an asset:

```bash
run_ingestion_preflight() {
  source data/real/ingesta/auth/ingesta_api_key.env

  if ! bash data/real/ingesta/pre/curl_ingesta_api_pull_pre_base.sh; then
    unset INGESTA_API_KEY INGESTA_API_PROVIDER_ID
    return 1
  fi

  unset INGESTA_API_KEY INGESTA_API_PROVIDER_ID
}

run_ingestion_preflight
unset -f run_ingestion_preflight
```

The preflight succeeds only when the response is HTTP 200, non-empty, and valid JSON. The `curl_ingesta_api_pull_pre_limit10.sh` script is an optional parameter experiment; it is not required by the EdD flow.

## Current v2 execution (PRE GET)

Run this block from the repository root. It sources the upstream secret only for phase 1 and removes it before negotiation:

```bash
run_ingestion_flow() {
  local bash_bin download_file manifest_file
  bash_bin="${BASH_BIN:-$(command -v bash)}"

  unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR
  unset SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL
  unset CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID

  export IPPCP_DATASPACE=ippcp
  export IPPCP_FLOW=ingesta
  export IPPCP_FLOW_VERSION=v2

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

  download_file="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"
  manifest_file="downloads/manifests/${ASSET_ID}/latest.manifest.json"

  test -s "${download_file}"
  jq empty "${download_file}"
  jq -e \
    --arg suffix "${SUFFIX}" \
    --arg asset_id "${ASSET_ID}" \
    '.suffix == $suffix
      and .asset_id == $asset_id
      and (.bytes > 0)
      and (.sha256 | type == "string" and length == 64)' \
    "${manifest_file}"
}

run_ingestion_flow
unset -f run_ingestion_flow
```

Every phase sources the preceding phase environment before continuing. `ASSET_CONFIG` is set explicitly before phase 1.

## PROD POST execution notes

Same phase0–phase3 sequence with a PROD POST `ASSET_CONFIG`. Source `data/real/ingesta/auth/ingesta_api_key_prod.env` only for phase 1 (not the PRE file).

Phase 4 POST path (metadata-only):

```text
consumer request body (local file)
  → EDR / Data Plane (authorization from EDR)
  → body + Content-Type proxied (`proxyBody=true`)
  → HTTP POST upstream Intake API
```

`INGESTA_API_REQUEST_BODY_FILE` is required. The request body is not persisted in evidence. The response body is not persisted. There is no download artifact and no response SHA-256. Success is `curl` exit 0 with an HTTP 2xx status (the body may be empty or non-JSON).

```bash
export INGESTA_API_REQUEST_BODY_FILE="/absolute/or/repo-relative/path/to/body.json"
# body file stays local; do not commit production payloads
source runtime/env/latest/phase3_env.sh
"${BASH_BIN:-bash}" scripts/phase4_save_download.sh
unset INGESTA_API_REQUEST_BODY_FILE
```

Control evidence records method, HTTP status, media type, and byte counts — not the request or response bodies. Typical artifacts:

```text
evidencias/runs/<run_id>/phase4/post_result.json
evidencias/runs/<run_id>/phase4/post_manifest.json
```

Do not enable `PHASE3_TRY_DATA_CONSUMPTION=1` for POST assets; the legacy phase 3 probe is GET-only and is skipped for `ASSET_HTTP_METHOD=POST`.

CIRCE phase 4 requires a CIRCE-specific body using `districtCode`. Industrias Ebro uses `centerId`. Both PROD company profiles are validated end-to-end through phase 4; do not reuse one company's payload for the other.

## Expected result

### PRE GET (historical download path)

A successful phase 4 creates:

```text
evidencias/runs/<run_id>/phase4/40_data_response.json
downloads/assets/<asset_id>/<run_id>.json
downloads/assets/<asset_id>/latest.json
downloads/manifests/<asset_id>/<run_id>.manifest.json
downloads/manifests/<asset_id>/latest.manifest.json
```

The run-specific download and manifest, linked by asset ID and run metadata, provide durable local traceability. `latest.json` and `latest.manifest.json` are mutable convenience outputs for the current local result; they are not stable backend integration contracts.

### PROD POST (metadata-only)

A successful phase 4 creates control metadata only (for example `post_result.json` / `post_manifest.json` with `manifest_kind=post_metadata_only`). It does **not** create a GET-style download under `downloads/assets/` and does **not** require a response SHA-256.

## Validation

### PRE GET

Required acceptance checks:

- phase 4 completed successfully in `summary.json`;
- the downloaded file exists and is non-empty;
- `jq empty` accepts the downloaded JSON;
- the manifest identifies the current `SUFFIX` and `ASSET_ID`;
- manifest byte count is greater than zero;
- manifest SHA-256 is populated;
- no API key or EDR authorization appears in persisted control evidence.

### PROD POST

Required acceptance checks:

- phases 0–4 completed successfully for both PROD company profiles;
- for PROD POST phase 4: `ASSET_HTTP_METHOD=POST`, HTTP 2xx, `request_body_persisted=false`, `response_body_persisted=false`, `download_persisted=false`;
- no API key, EDR authorization, or POST request/response body appears in persisted control evidence;
- do not require `download_manifest.json` or a response SHA-256 for POST metadata-only.

The canonical scripts do not impose a business-specific Intake response schema. If an integration requires particular fields, add that acceptance criterion outside the generic flow without publishing business data.

See [Evidence and traceability](../evidence-and-traceability.md) for durable evidence rules.

## Flow-specific errors

### Missing or invalid provider configuration

- Missing `INGESTA_API_KEY`: source the ignored API-key environment before phase 1.
- Missing `INGESTA_API_PROVIDER_ID`: provision the provider identifier for configs without embedded `provider_id`.
- Non-numeric provider ID: use the numeric application identifier, not a Keycloak identifier.
- Duplicate header supplied through an extra-header variable: remove it; phase 1 owns both canonical header fields.

### Missing POST body file

- Phase 4 fails before calling the Data Plane when `ASSET_HTTP_METHOD=POST` and `INGESTA_API_REQUEST_BODY_FILE` is unset, missing, empty, or invalid JSON.

### Upstream access failure

- HTTP 401 during direct PRE preflight usually indicates a missing, invalid, or unauthorized API key.
- A missing-provider message indicates that `X-Provider-Id` was not supplied or was invalid.
- For PRE GET, an empty or non-JSON response fails preflight and phase 4 acceptance even if transport succeeded.
- For PROD POST metadata-only, HTTP 2xx with an empty or non-JSON body can still be success; diagnose 4xx/5xx separately (see [Troubleshooting](../troubleshooting.md)).

### Publication conflict

An HTTP 409 during phase 1 indicates that an object with the identifier already exists. For suffix-derived ids, start a new execution. For stable PROD ids, resolve the existing asset conflict with the provider operator before republishing.

### Phase 4 failure

Phase 4 retrieves the EDR again and handles EDR authorization candidates internally. Do not add the upstream API key to the consumer request and do not enable the historical upstream JWT route.

Review the redacted phase 4 attempt summary and `summary.json`; do not inspect or publish raw authorization material or the POST request body.

## Legacy and non-current material

- `ingesta_api_pull_pre.json` is superseded by the API-key configuration for the current PRE profile.
- `ingesta_api_pull_pro.json` is prepared project material for GET PRO; it is not the PROD POST profile.
- B2/CSV/InesDataStore remains the delivered T1 evidence baseline and is not this `HttpData-PULL` flow.
- Upstream JWT helpers, Bearer-token variables, and phase 4 upstream-authentication flags are historical.
- `v1` is legacy-supported and not used by the recommended block.
- `test3` and old workshop procedures are historical.

## Related documentation

- [Workshop](../workshop.md)
- [Architecture](../architecture.md)
- [Authentication](../authentication.md)
- [Execution phases](../execution-phases.md)
- [Evidence and traceability](../evidence-and-traceability.md)
- [Backend integration](../backend-integration.md)
