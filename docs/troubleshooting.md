# Troubleshooting

## Purpose

This guide covers the current `v2` `HttpData-PULL` execution path. Start with the executable [workshop](workshop.md), then use this document and the flow-specific reference:

- [Ingestion API](flows/ingestion-api.md)
- [WFS](flows/wfs.md)
- [SPARQL](flows/sparql.md)

Do not paste passwords, tokens, API keys, EDR authorization, connector hosts, or raw evidence into support requests.

## Diagnostic principles

Before changing state:

1. identify the last phase whose status is `ok`;
2. identify the expected `SUFFIX`;
3. use the run-specific `summary.json` and phase artifacts;
4. confirm that every sourced phase environment has the same `SUFFIX`;
5. inspect `.http`, redacted JSON, and attempt-summary files before raw payloads;
6. stop when a prerequisite phase has failed.

`runtime/env/latest/` is mutable convenience state. The historical source of truth is:

```text
evidencias/runs/${SUFFIX}/
```

## Environment and repository setup

### Issue: a phase cannot find the repository root

**Symptom**

The script reports that it cannot find the API root or a required repository file.

**Likely cause**

- The command is running outside the cloned repository.
- The checkout is incomplete.
- The script was copied away from the repository instead of executed in place.

**Checks**

```bash
pwd
test -f endpoints.sh
test -f export_suffix.sh
test -f scripts/lib_common.sh
```

**Corrective action**

Change to the repository root and run the original script from `scripts/`. Restore missing tracked files from the repository rather than recreating them manually.

### Issue: Bash or required commands are unavailable

**Symptom**

The shell reports syntax errors around associative arrays or name references, or the script reports that `curl` or `jq` is unavailable.

**Likely cause**

- Bash is older than 4.3.
- The selected `BASH_BIN` is incorrect.
- A required command is not installed or not on `PATH`.

**Checks**

```bash
bash_bin="${BASH_BIN:-$(command -v bash)}"
"${bash_bin}" --version
command -v curl
command -v jq
command -v python3
```

**Corrective action**

Install or select Bash 4.3 or newer, `curl`, and `jq`. Python 3 is recommended for claim diagnostics. Re-run the failed phase with the corrected Bash executable.

### Issue: connector network access fails

**Symptom**

Phase 0 reports name-resolution, connection, timeout, or TLS errors and does not produce `phase0_env.sh`.

**Likely cause**

- The configured connector network is unavailable.
- Required VPN, DNS, proxy, or routing is missing.
- The selected environment profile is not reachable from the current machine.

**Checks**

Verify network access using connector addresses supplied by the environment owner. Do not copy those addresses into public documentation or support messages.

Check that phase 0 did not complete:

```bash
test -f runtime/env/latest/phase0_env.sh
```

**Corrective action**

Restore the approved network path before retrying phase 0. Do not create a phase environment manually. Add local DNS overrides only when the infrastructure owner supplies and approves them.

## Flow and version resolution

### Issue: `IPPCP_FLOW` or `IPPCP_FLOW_VERSION` is incorrect

**Symptom**

The wrong connector configuration is loaded, a flow export is missing, or the selected asset does not match the intended resource.

**Likely cause**

- `IPPCP_FLOW` is not `ingesta` or `consumo`.
- `IPPCP_FLOW_VERSION` is not explicitly set to `v2`.
- A stale `IPPCP_FLOW_DIR`, `IPPCP_DATASPACE_DIR`, or `IPPCP_DATASPACE_FILE` overrides normal resolution.

**Checks**

```bash
printf 'dataspace=%s\n' "${IPPCP_DATASPACE:-<unset>}"
printf 'flow=%s\n' "${IPPCP_FLOW:-<unset>}"
printf 'version=%s\n' "${IPPCP_FLOW_VERSION:-<unset>}"
printf 'flow_dir=%s\n' "${IPPCP_FLOW_DIR:-<auto>}"
```

Expected current selections:

```text
IPPCP_DATASPACE=ippcp
IPPCP_FLOW=ingesta or consumo
IPPCP_FLOW_VERSION=v2
```

**Corrective action**

For a clean selection:

```bash
unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW="<ingesta-or-consumo>"
export IPPCP_FLOW_VERSION=v2
```

Then start a new phase 0. Use `ingesta` for Ingestion API and `consumo` for WFS or SPARQL.

### Issue: context is unresolved or historical `test3` is selected explicitly

**Symptom**

Phase 0 cannot resolve a dataspace, or context artifacts identify the historical `test3` dataspace or unexpected connectors.

**Likely cause**

No current context was selected, or the shell still contains historical selector variables. In particular, `IPPCP_DATASPACE=test3`, `IPPCP_DATASPACE_FILE`, `IPPCP_DATASPACE_DIR`, or `IPPCP_FLOW_DIR` may explicitly resolve an obsolete context.

The current implementation does not fall back automatically to `test3`. With no resolvable context, it stops with an actionable error. A historical context is found only through an explicit, valid selection or override.

**Checks**

```bash
printf 'dataspace=%s\n' "${IPPCP_DATASPACE:-<unset>}"
printf 'dataspace_dir=%s\n' "${IPPCP_DATASPACE_DIR:-<auto>}"
printf 'dataspace_file=%s\n' "${IPPCP_DATASPACE_FILE:-<auto>}"
printf 'flow_dir=%s\n' "${IPPCP_FLOW_DIR:-<auto>}"
printf 'flow=%s\n' "${IPPCP_FLOW:-<unset>}"
printf 'version=%s\n' "${IPPCP_FLOW_VERSION:-<unset>}"
```

Inspect the phase 0 context for the current run without publishing it.

**Corrective action**

Stop the run and clear all historical selectors before choosing the current context:

```bash
unset IPPCP_DATASPACE IPPCP_DATASPACE_DIR IPPCP_DATASPACE_FILE
unset IPPCP_FLOW_DIR IPPCP_FLOW IPPCP_FLOW_VERSION
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW="<ingesta-or-consumo>"
export IPPCP_FLOW_VERSION=v2
```

Start a new phase 0 after making this selection. Do not continue an existing `test3` run as if it were current IPPCP.

### Issue: `runtime/env/latest` contains stale state

**Symptom**

A phase uses an unexpected asset, agreement, transfer, flow, or run identifier.

**Likely cause**

`runtime/env/latest/phaseN_env.sh` belongs to a different execution.

**Checks**

```bash
for env_file in runtime/env/latest/phase{0,1,2,3}_env.sh; do
  if [[ -f "${env_file}" ]]; then
    printf '%s: ' "${env_file}"
    awk -F= '/^export SUFFIX=/{print $2}' "${env_file}"
  fi
done
```

Compare those values with the intended run directory under `evidencias/runs/`.

**Corrective action**

Source the run-specific phase environment from the intended evidence directory, or restart from the last confirmed phase. Never edit IDs in a phase environment to force them to match.

### Issue: `SUFFIX` differs between phases

**Symptom**

Artifacts and inherited identifiers refer to different run directories, or a later phase cannot find the expected connector object.

**Likely cause**

Phase files from different executions were sourced in one shell.

**Checks**

```bash
: "${SUFFIX:?Source the intended phase environment first}"
summary="evidencias/runs/${SUFFIX}/summary.json"
jq -r '.suffix, (.phases | keys[])' "${summary}"
```

Compare `SUFFIX` in each run-specific `phaseN_env.sh`.

**Corrective action**

Stop. Open a clean shell, source only the expected run-specific phase environment, and continue from the next valid phase. If the chain cannot be proven, start a new run.

## Phase 0: context and EdD authentication

### Issue: provider or consumer credentials are missing

**Symptom**

Phase 0 reports a missing `user_provider.sh` or `user_consumer.sh`.

**Likely cause**

The ignored local credential files were not created beside the selected `v2` flow exports.

**Checks**

```bash
flow_dir="flujos/ippcp/v2/${IPPCP_FLOW}"
test -f "${flow_dir}/user_provider.sh"
test -f "${flow_dir}/user_consumer.sh"
test -f "${flow_dir}/user_provider.example.sh"
test -f "${flow_dir}/user_consumer.example.sh"
```

**Corrective action**

Copy the `.example.sh` files to the ignored names and populate them locally. Provider credentials must be valid for the configured provider connector; consumer credentials must be valid for the configured consumer connector. The file layout does not require different users for every data flow.

### Issue: EdD authentication returns no token

**Symptom**

Phase 0 reports that it could not obtain the provider or consumer JWT.

**Likely cause**

- Incorrect username or password.
- The technical user cannot complete non-interactive authentication.
- Wrong dataspace, realm, or client configuration.
- User provisioning is incomplete or disabled.

**Checks**

- Confirm the selected dataspace and flow.
- Confirm both ignored credential files exist.
- Confirm the technical users are enabled for the configured connector authentication process.
- If an earlier run exists, inspect its redacted `jwt_claims_*.json`; do not inspect or paste the token.

**Corrective action**

Correct the local credential or identity configuration and rerun phase 0. Do not use a manual token request with a password on the command line.

### Issue: one connector smoke check fails

**Symptom**

Provider or consumer asset-list smoke evidence has a non-success status.

**Likely cause**

- The corresponding technical user lacks connector permissions.
- The connector base URL belongs to another environment.
- Network access is incomplete.

**Checks**

```bash
: "${SUFFIX:?Set the phase 0 run identifier}"
cat "evidencias/runs/${SUFFIX}/phase0/01_provider_assets_smoke.http"
cat "evidencias/runs/${SUFFIX}/phase0/02_consumer_assets_smoke.http"
```

**Corrective action**

Correct the failing connector's access, role, or environment configuration. Both smoke checks must pass before phase 1.

## Phase 1: asset and offer publication

### Issue: phase 1 runs in an unsupported folder or context

**Symptom**

`ASSET_CONFIG` cannot be found, the wrong default asset is selected, or publication targets unexpected connectors.

**Likely cause**

- The command is not running from the repository root.
- `ASSET_CONFIG` is relative to another directory.
- The wrong flow/version was selected.
- `ASSET_CONFIG` was omitted.

**Checks**

```bash
pwd
test -f scripts/phase1_provider_publish.sh
test -f "${ASSET_CONFIG:-<missing>}"
printf 'flow=%s version=%s\n' "${IPPCP_FLOW:-<unset>}" "${IPPCP_FLOW_VERSION:-<unset>}"
```

**Corrective action**

Return to the repository root, source the matching `phase0_env.sh`, and set the exact `ASSET_CONFIG` from the selected [flow guide](getting-started.md#select-a-flow) before rerunning phase 1.

### Issue: asset configuration is rejected

**Symptom**

Phase 1 reports invalid JSON, missing fields, unsupported content kind/extension, an invalid base URL, or an InesDataStore configuration.

**Likely cause**

The selected file is malformed or belongs to the separate B2 baseline rather than the current `HttpData-PULL` path.

**Checks**

```bash
jq empty "${ASSET_CONFIG}"
jq '{type, content_kind, extension, media_type}' "${ASSET_CONFIG}"
```

The current phase 1 requires `type=HttpData`.

**Corrective action**

Select a current configuration from the Ingestion API, WFS, or SPARQL guide. Do not route an InesDataStore configuration through the current phase 1 script.

### Issue: publication returns HTTP 409

**Symptom**

Phase 1 reports that a resource derived from the current `SUFFIX` already exists.

**Likely cause**

The same run identifier was reused for immutable provider resources.

**Checks**

```bash
: "${SUFFIX:?Source phase0_env.sh}"
jq '.phases.phase1' "evidencias/runs/${SUFFIX}/summary.json"
```

**Corrective action**

Start a new execution with a new `SUFFIX`. The scripts do not implement provider cleanup or in-place asset mutation.

### Issue: asset or offer is absent from the provider catalog

**Symptom**

Publication calls succeed, but phase 1 cannot find the asset in the provider self-catalog.

**Likely cause**

- Policy or contract-definition publication failed.
- The asset, policy, and contract definition do not reference the same IDs.
- Catalog propagation or connector authorization failed.

**Checks**

Inspect:

```text
evidencias/runs/${SUFFIX}/phase1/
evidencias/runs/${SUFFIX}/summary.json
```

Focus on asset retrieval, contract-definition listing, self-catalog status, and catalog match.

**Corrective action**

Fix the failed publication step and start a new execution if immutable objects were partially created. Do not invent or edit connector IDs in local state.

## Phase 2: negotiation and agreement

### Issue: the catalog does not contain the expected asset

**Symptom**

Phase 2 cannot select `ASSET_ID` or an offer policy from the remote catalog.

**Likely cause**

- Phase 1 did not complete.
- A stale `phase1_env.sh` was sourced.
- Provider/consumer roles or protocol address are incorrect.
- The asset is not visible under the published contract definition.

**Checks**

```bash
: "${SUFFIX:?Source the intended phase1_env.sh}"
jq '.phases.phase1.status, .phases.phase2' "evidencias/runs/${SUFFIX}/summary.json"
```

Inspect the remote catalog and selected-ID artifacts under `phase2/`.

**Corrective action**

Resolve phase 1/catalog visibility first. Source the matching `phase1_env.sh` and rerun phase 2 only when the asset and offer are present.

### Issue: negotiation does not reach `FINALIZED` or produce an agreement

**Symptom**

Negotiation becomes `TERMINATED` or times out without `contractAgreementId`.

**Likely cause**

- Policy mismatch.
- Stale asset or offer identifiers.
- Consumer authentication expired during an external/manual operation.
- Connector notification or protocol failure.

**Checks**

Inspect the negotiation response and state polling artifacts:

```text
evidencias/runs/${SUFFIX}/phase2/30_contract_negotiation_response.json
evidencias/runs/${SUFFIX}/phase2/31_negotiation_state_*.json
evidencias/runs/${SUFFIX}/phase2/32_negotiation_final_state.json
```

The script polls up to 20 times with three-second intervals. The implemented success gate is a valid agreement ID. A `FINALIZED` display state is not sufficient without that ID, and a valid agreement ID can complete the implemented gate even when state reporting differs.

**Corrective action**

Correct the policy, asset selection, or connector issue. `PHASE2_FORCE=1` is implemented only to relaunch phase 2 when `phase2_env.sh` already contains an agreement for the same `SUFFIX`; it creates another negotiation. Use it only after reviewing the existing run.

### Issue: phase 2 refuses to relaunch

**Symptom**

The script reports that `phase2_env.sh` already contains `AGREEMENT_ID` for the current run.

**Likely cause**

Duplicate negotiation protection detected completed phase 2 state.

**Checks**

```bash
: "${SUFFIX:?Source phase1_env.sh}"
jq '.phases.phase2' "evidencias/runs/${SUFFIX}/summary.json"
```

**Corrective action**

Continue to phase 3 if the agreement is valid. If a deliberate new negotiation is required for the same run, execute phase 2 with `PHASE2_FORCE=1`. This is not a cleanup or rollback mechanism.

## Phase 3: transfer and EDR

### Issue: transfer does not reach `STARTED` or `COMPLETED`

**Symptom**

Phase 3 times out, or the transfer becomes `TERMINATED` or `ERROR`.

**Likely cause**

- Invalid agreement or provider protocol address.
- Transfer request rejected by a connector.
- Connector/Data Plane availability problem.

**Checks**

Inspect:

```text
evidencias/runs/${SUFFIX}/phase3/10_transfer_response.json
evidencias/runs/${SUFFIX}/phase3/20_transfer_state_*.json
evidencias/runs/${SUFFIX}/phase3/21_transfer_final_state.json
```

The script polls up to 20 times with three-second intervals. The implemented accepted states are `STARTED` and `COMPLETED`.

**Corrective action**

Correct the underlying transfer failure. `PHASE3_FORCE=1` is implemented to create a new transfer when phase 3 state already exists for the same `SUFFIX`. It does not repair a failed transfer.

### Issue: EDR is not found after transfer start

**Symptom**

Phase 3 reports that no resolvable EDR was found.

**Likely cause**

- The EDR has not been materialized yet.
- The transfer ID does not belong to the current run.
- Consumer access or connector state is invalid.

**Checks**

Review:

```text
evidencias/runs/${SUFFIX}/phase3/30_edr_direct_*.http
evidencias/runs/${SUFFIX}/phase3/30_edr_dataaddress_redacted.json
evidencias/runs/${SUFFIX}/phase3/31_edrs_request_redacted.json
```

Phase 3 already polls direct EDR retrieval up to 20 times with three-second intervals and then tries its implemented EDR-list fallback.

**Corrective action**

If the existing transfer is still valid, rerun phase 3 with `PHASE3_RESUME=1`. The script resolves and reuses `TRANSFER_ID`, checks transfer state, polls when appropriate, and retries EDR retrieval without creating a new transfer.

Do not combine `PHASE3_RESUME=1` with `PHASE3_FORCE=1`; the script rejects that combination.

### Issue: phase 3 refuses to run because transfer state exists

**Symptom**

The script reports that `phase3_env.sh` already contains `TRANSFER_ID`.

**Likely cause**

Duplicate-transfer protection detected prior phase 3 state for the same run.

**Checks**

Review the existing transfer state and whether the EDR step completed.

**Corrective action**

- Use the existing `phase3_env.sh` and continue to phase 4 when phase 3 is `ok`.
- Use `PHASE3_RESUME=1` to continue the existing transfer after an EDR-stage failure.
- Use `PHASE3_FORCE=1` only when a deliberate new transfer is required.

These controls are mutually exclusive where the script enforces it and do not delete prior connector state.

## Phase 4: download and manifest

### Issue: phase 4 reports a failed prerequisite

**Symptom**

Phase 4 reports missing phase 3 state or `phases.phase3.status != ok`.

**Likely cause**

Phase 3 did not complete, or the wrong `phase3_env.sh` is loaded.

**Checks**

```bash
: "${SUFFIX:?Source phase3_env.sh}"
jq -r '.phases.phase3.status' "evidencias/runs/${SUFFIX}/summary.json"
printf 'transfer=%s\n' "${TRANSFER_ID:-<unset>}"
```

**Corrective action**

Complete or resume phase 3 first. Phase 4 requires matching `SUFFIX`, `ASSET_ID`, `AGREEMENT_ID`, and `TRANSFER_ID`.

### Issue: EDR is missing or expired in phase 4

**Symptom**

Phase 4 cannot resolve a current EDR even though phase 3 previously succeeded.

**Likely cause**

- The EDR is not currently available.
- The transfer ID or sourced phase state is stale.
- Consumer authentication or connector state is invalid.

**Checks**

Review phase 4 EDR status and redacted diagnostics:

```text
evidencias/runs/${SUFFIX}/phase4/30_edr_direct_*.http
evidencias/runs/${SUFFIX}/phase4/30_edr_dataaddress_redacted.json
evidencias/runs/${SUFFIX}/phase4/31_edrs_request_redacted.json
```

Phase 4 automatically re-authenticates the consumer, polls direct EDR retrieval up to 20 times with three-second intervals, and uses its implemented EDR-list fallback.

**Corrective action**

First rerun phase 4 with the correct `phase3_env.sh`; this invokes the implemented EDR re-fetch. If the transfer itself is not valid, return to phase 3 and use `PHASE3_RESUME=1` only when its documented preconditions hold.

### Issue: all Data Plane authorization attempts fail

**Symptom**

Phase 4 reports that it could not consume the EDR endpoint.

**Likely cause**

- EDR authorization is no longer valid.
- Data Plane or upstream access fails.
- The response is empty, non-successful, or invalid JSON for a JSON asset.

**Checks**

Inspect:

```text
evidencias/runs/${SUFFIX}/phase4/42_data_attempts_summary.json
evidencias/runs/${SUFFIX}/phase4/40_data_response_attempt_*.http
```

The current observed valid authorization representation is handled internally as `authorization_raw`. Other candidates are compatibility fallbacks implemented by the script.

**Corrective action**

Correct transfer, EDR, Data Plane, or upstream availability and rerun phase 4. Do not extract raw authorization or manually reproduce the candidate loop.

### Issue: manifest is missing

**Symptom**

The download may exist, but the run-specific manifest or `phase4/save_download` summary step is absent.

**Likely cause**

- Phase 4 failed after receiving data but before terminal completion.
- Content validation failed.
- Local copy or hashing failed.

**Checks**

```bash
: "${SUFFIX:?Source phase3_env.sh}"
jq '.phases.phase4' "evidencias/runs/${SUFFIX}/summary.json"
test -f "downloads/manifests/${ASSET_ID}/${SUFFIX}.manifest.json"
```

**Corrective action**

Treat the run as incomplete. Resolve the recorded phase 4 failure and rerun phase 4. Do not create a manifest by hand.

### Issue: downloaded JSON is invalid or unexpected

**Symptom**

HTTP status is successful, but phase 4 rejects JSON syntax or the flow guide's semantic check fails.

**Likely cause**

- Upstream returned HTML, XML, an error object, or truncated content.
- The wrong asset configuration was published.
- The response is valid JSON but not the expected domain structure.

**Checks**

```bash
download_file="downloads/assets/${ASSET_ID}/${SUFFIX}.${ASSET_EXTENSION:-json}"
test -s "${download_file}"
jq empty "${download_file}"
```

Then run the semantic `jq` check from the selected flow guide.

**Corrective action**

Correct the upstream request or publish a new asset with the correct immutable data address. HTTP 200 alone is not acceptance.

### Issue: a run-specific download already exists with different content

**Symptom**

Phase 4 refuses to overwrite the destination and requests `DOWNLOAD_FORCE=1`.

**Likely cause**

The same `SUFFIX` and asset destination already contain bytes with a different SHA-256.

**Checks**

Compare the intended run, asset ID, existing run-specific manifest, byte count, and hash metadata.

**Corrective action**

If replacement is deliberate and the run identity is correct, rerun phase 4 with `DOWNLOAD_FORCE=1`. The implemented behavior is:

- create the run-specific file when absent;
- leave it unchanged when the existing hash matches;
- reject a different hash unless `DOWNLOAD_FORCE=1`;
- update mutable `latest.*` from the accepted run-specific file.

`DOWNLOAD_FORCE` is overwrite permission, not a retry or connector cleanup mechanism.

## Ingestion API

### Issue: phase 1 reports a missing API key

**Symptom**

Phase 1 requires `INGESTA_API_KEY`.

**Likely cause**

The ignored Ingestion API environment was not sourced immediately before phase 1.

**Checks**

Confirm the local file exists without printing its values:

```bash
test -f data/real/ingesta/auth/ingesta_api_key.env
```

**Corrective action**

Follow the [Ingestion API flow](flows/ingestion-api.md): source the ignored file immediately before phase 1, run phase 1, then unset `INGESTA_API_KEY` and `INGESTA_API_PROVIDER_ID` before phase 2.

### Issue: provider ID is missing or non-numeric

**Symptom**

Phase 1 reports that `INGESTA_API_PROVIDER_ID` is required or must be numeric.

**Likely cause**

The variable is absent, contains a header prefix, or contains an identity-system identifier rather than the upstream application's numeric provider ID.

**Checks**

```bash
if [[ "${INGESTA_API_PROVIDER_ID:-}" =~ ^[0-9]+$ ]]; then
  echo "provider ID format: numeric"
else
  echo "provider ID format: invalid"
fi
```

**Corrective action**

Obtain the numeric provider ID from the upstream resource owner and update the ignored local environment. Do not publish or log it unnecessarily.

### Issue: Ingestion phase 4 returns an upstream authorization failure

**Symptom**

The EDR is resolved, but the upstream response is unauthorized, empty, or invalid JSON.

**Likely cause**

The provider asset was published with a missing, invalid, or rotated API key/provider ID.

**Checks**

- Review phase 1 redacted data-address evidence.
- Review phase 4 HTTP status and attempt summary.
- Optionally run the separate direct preflight documented in the flow guide.

**Corrective action**

Correct the provider-side secret and publish a new asset. The provider data address is immutable for this assessment. Run phase 4 normally; do not add the upstream key to the consumer environment.

### Issue: phase 4 POST fails before calling the Data Plane

**Symptom**

Phase 4 reports that `INGESTA_API_REQUEST_BODY_FILE` is required, missing, empty, or not valid JSON.

**Likely cause**

A PROD POST asset (`ASSET_HTTP_METHOD=POST`) was negotiated, but the consumer body file was not provisioned for phase 4.

**Checks**

```bash
test -n "${INGESTA_API_REQUEST_BODY_FILE:-}"
test -s "${INGESTA_API_REQUEST_BODY_FILE}"
jq empty "${INGESTA_API_REQUEST_BODY_FILE}"
```

**Corrective action**

Point `INGESTA_API_REQUEST_BODY_FILE` at a local JSON payload for the company asset. Do not commit production bodies. Do not paste the body into logs or evidence. See [Ingestion API flow](flows/ingestion-api.md).

### Issue: confusing HTTP POST with HttpData-PUSH

**Symptom**

Operators expect transfer type `HttpData-PUSH` because phase 4 uses HTTP POST.

**Likely cause**

HTTP method (`POST`) vs EDC transfer vocabulary (`HttpData-PULL`).

**Corrective action**

Keep transfer `HttpData-PULL` and data address `HttpData` with `method=POST` and `proxyBody=true`. Do not switch the transfer type. PROD asset ids are `ippcp-ingesta-pull-*-prod`.

### Issue: PROD POST uses wrong provider id after a previous PRE run

**Symptom**

Phase 1 publishes with an unexpected `X-Provider-Id`, or upstream rejects the provider.

**Likely cause**

A stale `INGESTA_API_PROVIDER_ID` remains exported in the shell while the PROD config embeds a different `provider_id` (Ebro `1`, CIRCE `2`).

**Corrective action**

Rely on config `provider_id` for PROD company assets. Unset stale `INGESTA_API_PROVIDER_ID` before phase 1, or ensure the config value is the one that must win.

### Issue: phase 4 POST expects a download or response SHA-256

**Symptom**

Operators look for `downloads/assets/...`, `download_manifest.json`, or a response SHA-256 after a PROD POST run.

**Likely cause**

GET/download expectations applied to POST metadata-only phase 4.

**Corrective action**

For `ASSET_HTTP_METHOD=POST`, require `INGESTA_API_REQUEST_BODY_FILE`, confirm HTTP 2xx, and inspect `phase4/post_result.json` / `phase4/post_manifest.json` (`manifest_kind=post_metadata_only`). Do not require a downloaded payload or response SHA-256. Request and response bodies must not be persisted.

### Issue: forcing `Authorization: Bearer` on the EDR hop returns 403

**Symptom**

Phase 4 fails with HTTP 403 when the consumer rewrites EDR authorization as `Bearer …`.

**Likely cause**

The Data Plane expects the raw EDR authorization material selected by the scripts, not an ad-hoc Bearer rewrite.

**Corrective action**

Use the scripted EDR authorization candidates. Do not force `Bearer` on top of a raw EDR authorization value.

### Issue: EdD POST returns 500 and direct upstream POST also returns 500

**Symptom**

Phase 4 via the EdD Data Plane returns HTTP 500, and a provider-side direct POST to the same Intake URL with the same business body also returns HTTP 500.

**Likely cause**

Upstream/backend rejection or payload/schema problem — not a Data Plane proxy failure.

**Checks**

Compare (without publishing secrets or bodies):

1. POST through EdD / phase 4 → 500;
2. POST direct to the Intake URL with the same company headers/body → 500.

**Corrective action**

Treat matching 500s as an upstream/backend diagnosis. Fix the payload or backend contract with the data provider. Do not change transfer type to `HttpData-PUSH`.

Historical note: a past Intake validation bug around an unexpected `field_id` shape produced this pattern and was corrected on the backend. Keep that as a diagnostic example, not as a general client rule.

### Issue: phase 4 POST uses a body for the wrong company

**Symptom**

Phase 4 POST fails or cannot be executed because the request body does not match the company-specific ingestion schema.

**Likely cause**

PROD request bodies are company-specific: Industrias Ebro uses `centerId`, while CIRCE uses `districtCode`.

**Corrective action**

Provide the request body for the correct company. Do not reuse the Industrias Ebro payload for CIRCE or the CIRCE payload for Industrias Ebro. Both PROD company profiles have been validated end-to-end through phase 4.

## WFS

### Issue: WFS response is not expected GeoJSON

**Symptom**

The response is empty, invalid JSON, or valid JSON without the expected GeoJSON `FeatureCollection`.

**Likely cause**

- Upstream WFS is unavailable.
- Wrong layer or request format.
- Upstream returned an XML/HTML error document or an application error object.

**Checks**

```bash
download_file="downloads/assets/${ASSET_ID}/${SUFFIX}.json"
jq -e '
  type == "object"
  and .type == "FeatureCollection"
  and (.features | type == "array")
' "${download_file}"
```

**Corrective action**

Select the validated city or district-board configuration required by the integration and publish a new asset if the data address was wrong. Do not accept HTTP 200 or generic JSON as GeoJSON proof.

## SPARQL

### Issue: SPARQL returns XML instead of SPARQL Results JSON

**Symptom**

The request returns HTTP 200, but `jq` rejects the body or the content is XML.

**Likely cause**

A legacy/noncanonical configuration omitted the explicit SPARQL Results JSON format.

**Checks**

Confirm:

```text
ASSET_CONFIG=asset_configs/real/consumo/sparql/emisiones_sparql_limit10_format_json.json
```

Validate the local download:

```bash
download_file="downloads/assets/${ASSET_ID}/${SUFFIX}.json"
jq -e '
  type == "object"
  and (.head | type == "object")
  and (.results | type == "object")
  and (.results.bindings | type == "array")
' "${download_file}"
```

**Corrective action**

Use the canonical JSON-format configuration and publish a new asset. Do not relabel XML as JSON and do not treat HTTP 200 as content validation.

### Issue: SPARQL JSON has the wrong structure

**Symptom**

`jq empty` succeeds, but `head` or `results.bindings` is absent.

**Likely cause**

The upstream returned a generic JSON error, the encoded query is wrong, or a different API response was published.

**Checks**

Run the structural check from the [SPARQL flow](flows/sparql.md) and review only the local authorized result.

**Corrective action**

Validate query and result format together, then publish a new asset with the corrected immutable data address.

## Evidence and secret handling

### Issue: a secret is detected in evidence

**Symptom**

A script redaction assertion or evidence scan detects a password, token-like value, API-key value, EDR authorization, client secret, storage credential, or sensitive URL.

**Likely cause**

- A raw response or temporary request was copied into evidence.
- A new credential field is not covered by the expected redaction path.
- A local credential file was included in a package.

**Checks**

Stop publication. Identify the affected file without printing the value. Check whether it is:

- a phase environment;
- a sensitive/secret-named artifact;
- a raw request body;
- a local credential file;
- an unredacted JSON field.

**Corrective action**

Remove the artifact from any package or shared location, rotate the credential if disclosure occurred, correct the generation/redaction process, and regenerate evidence. Do not hand-edit a leaked public package and assume the secret is safe.

See [Evidence and traceability](evidence-and-traceability.md) and [Authentication](authentication.md).

### Issue: `latest.json` does not identify the intended run

**Symptom**

The current convenience download contains data from a newer execution than expected.

**Likely cause**

`latest.*` was updated by another successful phase 4 run.

**Checks**

Use the run-specific manifest and download:

```text
downloads/assets/${ASSET_ID}/${SUFFIX}.${ASSET_EXTENSION}
downloads/manifests/${ASSET_ID}/${SUFFIX}.manifest.json
```

**Corrective action**

Use asset ID, `SUFFIX`, run-specific paths, and manifest metadata for durable traceability. Do not use `latest.*` as a backend contract or historical identifier.

## Legacy and historical boundaries

- `v1` is legacy-supported and not the recommended path.
- B2/CSV/InesDataStore is preserved as delivered baseline evidence; its `phase*b` procedures are not part of this active guide.
- `test3`, flat pre-versioned flow paths, upstream JWT authentication, phase 3 inline download, and obsolete workshop procedures are historical.

Historical procedures are intentionally not repaired or merged here. T1–T4 are presentation slots; see [Evidence and traceability](evidence-and-traceability.md) and [workshop.md](workshop.md).

## Related documentation

- [Workshop](workshop.md)
- [Getting Started](getting-started.md)
- [Architecture](architecture.md)
- [Authentication](authentication.md)
- [Execution phases](execution-phases.md)
- [Evidence and traceability](evidence-and-traceability.md)
