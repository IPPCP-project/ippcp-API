# IPPCP API workshop

This is the executable Golden Path. Copy and paste the command blocks in order from the repository root.

A new technical user can complete the current IPPCP API workflow from a clean clone by following this document. **PRE GET remains complete and validated; PROD POST is added additively.** All current profiles use EDC `HttpData-PULL`. Detailed reference material also exists in [Getting started](getting-started.md) and the sections linked at the end, but this page is designed to be independently executable.

## 0. What this workshop does

You will:

1. prepare the machine;
2. create ignored local credential files;
3. configure the Ingestion API secret if you will run that asset;
4. execute Phase 0 through Phase 4 for each selected asset profile;
5. validate the technical result semantically where applicable;
6. inspect runtime traceability;
7. package evidence.

Current assets and the same technical lifecycle (`phase0` → `phase4`). Phase 4 has two result modes — both remain `HttpData-PULL`:

| Resource | `IPPCP_FLOW` | Provider | Consumer | Configuration |
| --- | --- | --- | --- | --- |
| Ingestion API PRE GET | `ingesta` | `conn-citycouncil-ippcp` | `conn-company-ippcp` | `ingesta_api_pull_pre_api_key.json` |
| Ingestion API PROD POST — Industrias Ebro | `ingesta` | `conn-citycouncil-ippcp` | `conn-company-ippcp` | `ingesta_api_pull_industrias_ebro_prod.json` |
| Ingestion API PROD — CIRCE (phases 0–3) | `ingesta` | `conn-citycouncil-ippcp` | `conn-company-ippcp` | `ingesta_api_pull_circe_prod.json` |
| WFS city | `consumo` | `conn-citycouncil-ippcp` | `conn-company-ippcp` | `emisiones_wfs_ciudad_geojson.json` |
| WFS districts / juntas | `consumo` | `conn-citycouncil-ippcp` | `conn-company-ippcp` | `emisiones_wfs_juntas_geojson.json` |
| SPARQL Results JSON | `consumo` | `conn-citycouncil-ippcp` | `conn-company-ippcp` | `emisiones_sparql_limit10_format_json.json` |

```text
phase0 -> phase1 -> phase2 -> phase3 -> phase4
```

- Phase 0: context, technical provider/consumer login, smoke checks.
- Phase 1: policies, asset, data address, contract definition.
- Phase 2: catalog discovery, negotiation, agreement.
- Phase 3: transfer process and Endpoint Data Reference (EDR).
- Phase 4 — **materialized response** (PRE GET Ingestion API, WFS, SPARQL): Data Plane GET, local download, manifest, SHA-256.
- Phase 4 — **POST metadata-only** (PROD Ingestion API): local request body at runtime, HTTP 2xx control metadata (`post_result.json` / `post_manifest.json`); no persisted request/response bodies; no GET-style download; no response SHA-256.

The current Golden Path is `v2` `HttpData-PULL`. CSV/B2/InesDataStore, `v1`, `test3`, and `phase1b` / `phase3b` / `phase4b` are historical only. Do not mix them into this workshop.

You need Git access, EdD technical credentials supplied separately, and the Ingestion API secret supplied separately if you run that asset. You do not need prior IPPCP knowledge.

MinIO Client (`mc`) is not required for the current `HttpData-PULL` assets in this workshop.

## 1. Clone the repository

All later commands run from the repository root unless a block says otherwise.

```bash
git clone https://github.com/JPardo08/ippcp-API.git
cd ippcp-API
```

Confirm the root:

```bash
git status -sb
git log -1 --oneline
test -f endpoints.sh && test -f export_suffix.sh && test -f scripts/lib_common.sh && echo "OK repository root"
```

**Expected result:** you are in the repository root and the three files exist.

**STOP if:** the checkout is incomplete or you are not in the repository root.

## 2. Install prerequisites

Required:

- Bash 4.3 or newer.
- Git.
- `curl`.
- `jq`.
- `unzip` (inspect evidence ZIP packages).
- `rg` (ripgrep; audit suspicious artifact names and patterns).
- Python 3, recommended for diagnostics.
- Python 3.10 or newer is required later for evidence tooling. Conda is not required.

Technical users must be able to authenticate without human interaction. Mandatory OTP/MFA or pending required actions block the automated flow.

### 2.1 macOS

Check Homebrew:

```bash
command -v brew
brew --version
```

Install Homebrew first if `brew` is missing.

Install tools:

```bash
brew install bash jq python ripgrep
```

Select modern Bash:

```bash
export BASH_BIN="$(brew --prefix)/bin/bash"

"${BASH_BIN}" --version | head -1
command -v git
command -v curl
command -v jq
command -v unzip
command -v rg
command -v python3
```

**Expected result:** Bash reports `4.3` or newer. `git`, `curl`, `jq`, and `python3` are on `PATH`.

Typical Homebrew Bash locations:

- Apple Silicon: `/opt/homebrew/bin/bash`
- Intel: `/usr/local/bin/bash`

**STOP if:** Bash is older than 4.3 or a required command is missing.

### 2.2 Linux / WSL

Detect the package manager:

```bash
if command -v apt-get >/dev/null 2>&1; then
  echo "PACKAGE_MANAGER=apt"
elif command -v dnf >/dev/null 2>&1; then
  echo "PACKAGE_MANAGER=dnf"
elif command -v yum >/dev/null 2>&1; then
  echo "PACKAGE_MANAGER=yum"
elif command -v zypper >/dev/null 2>&1; then
  echo "PACKAGE_MANAGER=zypper"
elif command -v pacman >/dev/null 2>&1; then
  echo "PACKAGE_MANAGER=pacman"
else
  echo "No supported package manager detected by this workshop"
fi
```

Use **only** the block that matches the detected manager.

APT / Ubuntu / Debian / WSL Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y bash git curl jq unzip ripgrep python3 python3-pip python3-venv
```

DNF / Fedora / modern RHEL:

```bash
sudo dnf install -y bash git curl jq unzip ripgrep python3 python3-pip
```

YUM / older RHEL-like distributions:

```bash
sudo yum install -y bash git curl jq unzip ripgrep python3 python3-pip
```

Zypper / openSUSE:

```bash
sudo zypper install -y bash git curl jq unzip ripgrep python3 python3-pip
```

Pacman / Arch:

```bash
sudo pacman -S --needed bash git curl jq unzip ripgrep python python-pip
```

Select Bash:

```bash
export BASH_BIN="$(command -v bash)"

"${BASH_BIN}" --version | head -1
command -v git
command -v curl
command -v jq
command -v unzip
command -v rg
command -v python3
```

**Expected result:** Bash is 4.3 or newer and the required commands exist.

**STOP if:** Bash is too old or a required command is missing.

### 2.3 Optional static checks

```bash
jq empty asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json
jq empty asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json
jq empty asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json
jq empty asset_configs/real/consumo/wfs/emisiones_wfs_ciudad_geojson.json
jq empty asset_configs/real/consumo/wfs/emisiones_wfs_juntas_geojson.json
jq empty asset_configs/real/consumo/sparql/emisiones_sparql_limit10_format_json.json
echo "OK configs"

BASH_CHECK="${BASH_BIN:-$(command -v bash)}"
"${BASH_CHECK}" -n scripts/phase0_context_smoke.sh
"${BASH_CHECK}" -n scripts/phase1_provider_publish.sh
"${BASH_CHECK}" -n scripts/phase2_consumer_negotiate.sh
"${BASH_CHECK}" -n scripts/phase3_transfer_edr.sh
"${BASH_CHECK}" -n scripts/phase4_save_download.sh
echo "OK scripts"
```

Do not syntax-check `phase1b` / `phase3b` / `phase4b` as part of this workshop. Those scripts belong to the historical B2 path.

## 3. Create local technical-user files

The repository does not include real credentials. A clean clone fails Phase 0 until the ignored local files exist.

```bash
cp flujos/ippcp/v2/ingesta/user_provider.example.sh \
   flujos/ippcp/v2/ingesta/user_provider.sh

cp flujos/ippcp/v2/ingesta/user_consumer.example.sh \
   flujos/ippcp/v2/ingesta/user_consumer.sh

cp flujos/ippcp/v2/consumo/user_provider.example.sh \
   flujos/ippcp/v2/consumo/user_provider.sh

cp flujos/ippcp/v2/consumo/user_consumer.example.sh \
   flujos/ippcp/v2/consumo/user_consumer.sh
```

Edit the four files and replace `CHANGE_ME` with the technical credentials supplied to you:

```bash
export PROVIDER_USERNAME="CHANGE_ME"
export PROVIDER_PASSWORD="CHANGE_ME"
```

```bash
export CONSUMER_USERNAME="CHANGE_ME"
export CONSUMER_PASSWORD="CHANGE_ME"
```

The files are split by flow because that is how the repository is organized. This does not require four different accounts. The same provisioned technical user may be reused when it has permission on the configured connectors.

**Expected result:** all four `user_*.sh` files exist and no longer contain `CHANGE_ME`.

**STOP if:** credentials are missing, still set to `CHANGE_ME`, or you are about to paste passwords into documentation, commits, screenshots, or chat.

Do not commit these files.

## 4. Configure Ingestion API secrets

WFS and SPARQL do not need extra upstream credentials. Ingestion API does: the provider-side hop requires `X-Api-Key` and, for PRE GET, a numeric `X-Provider-Id`.

### 4.1 PRE GET

```bash
cp data/real/ingesta/auth/ingesta_api_key.env.example \
   data/real/ingesta/auth/ingesta_api_key.env
```

Edit the local file (for example with `nano data/real/ingesta/auth/ingesta_api_key.env`):

```bash
export INGESTA_API_KEY="REPLACE_ME"
export INGESTA_API_PROVIDER_ID="1"
```

Use this file for PRE GET (section 6). Do not assume PRE and PROD API keys are identical.

### 4.2 PROD POST

If you will run PROD POST (sections 7–8), create a separate ignored file:

```bash
cp data/real/ingesta/auth/ingesta_api_key_prod.env.example \
   data/real/ingesta/auth/ingesta_api_key_prod.env
```

Edit locally (for example with `nano data/real/ingesta/auth/ingesta_api_key_prod.env`) with the PROD API key supplied to you. PROD company configs embed `provider_id` (`1` for Industrias Ebro, `2` for CIRCE); you do not set `INGESTA_API_PROVIDER_ID` for those assets.

### 4.3 Local request body for PROD POST phase 4

PROD POST phase 4 requires a local JSON body file at runtime. Do not commit production payloads.

```bash
export INGESTA_API_REQUEST_BODY_FILE="/absolute/or/repo-relative/path/to/body.json"
test -s "${INGESTA_API_REQUEST_BODY_FILE}" && jq empty "${INGESTA_API_REQUEST_BODY_FILE}" && echo "OK request body"
```

Use an Industrias Ebro-specific body for Industrias Ebro. Use a CIRCE-specific body for CIRCE. **Never reuse the Industrias Ebro payload against CIRCE.**

- `INGESTA_API_KEY`: the Ingestion API key for the target environment.
- `INGESTA_API_PROVIDER_ID` (PRE GET only): numeric identifier expected by the upstream application. It is **not** a Keycloak UUID.
- These values stay on the provider boundary. They are not given to the consumer and are not placed in the EDR.

If you will run only WFS/SPARQL in this session, you may skip Ingestion API secret files until you run an Ingestion API profile. Phase 1 of Ingestion API will fail without the correct file for the selected profile.

**Expected result:** required ignored auth files exist locally and are not committed.

**STOP if:** you need Ingestion API and the file for the selected profile is missing, still contains `REPLACE_ME`, or you are about to print the key.

## 5. Verify secrets are ignored by Git

```bash
git status --short
```

```bash
git check-ignore \
  flujos/ippcp/v2/ingesta/user_provider.sh \
  flujos/ippcp/v2/ingesta/user_consumer.sh \
  flujos/ippcp/v2/consumo/user_provider.sh \
  flujos/ippcp/v2/consumo/user_consumer.sh \
  data/real/ingesta/auth/ingesta_api_key.env \
  data/real/ingesta/auth/ingesta_api_key_prod.env
```

**Expected result:** the command lists all six paths. Local credential files must not appear as versionable changes.

**STOP if:** any of the six paths is missing from `git check-ignore`. Do not continue and do not commit until `.gitignore` is corrected.

## 5.1 Reset shell context before each asset

Each asset needs a new Phase 0 and a new `SUFFIX`. Run this reset block before starting a new asset (sections 6–11):

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"
set +x

unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR
unset SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL
unset CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID
unset INGESTA_API_REQUEST_BODY_FILE
```

## 6. Ingestion API PRE GET — complete run

Prerequisites:

- `BASH_BIN` selected.
- Ingestion `user_provider.sh` and `user_consumer.sh` exist.
- `ingesta_api_key.env` exists (PRE GET file).
- Git ignores those files.

Each asset needs its own Phase 0 and `SUFFIX`. Start Ingestion API from a reset shell context.

### 6.1 Phase 0

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"
set +x

unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR
unset SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL
unset CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID

export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=ingesta
export IPPCP_FLOW_VERSION=v2

"${BASH_BIN}" scripts/phase0_context_smoke.sh
```

Only after success:

```bash
source runtime/env/latest/phase0_env.sh

echo "SUFFIX=$SUFFIX"
echo "IPPCP_FLOW=$IPPCP_FLOW"
test -f runtime/env/latest/phase0_env.sh && echo "OK phase0_env"
```

**Expected result:** Phase 0 exits successfully, `phase0_env.sh` exists, and `SUFFIX` is set.

**STOP if:** Phase 0 fails, `phase0_env.sh` is missing, or you see `Missing local credentials file`. Return to [section 3](#3-create-local-technical-user-files). Do not run Phase 1.

### 6.2 Phase 1

Load the upstream secret only for publication. Check length, not the key value:

```bash
source runtime/env/latest/phase0_env.sh
source data/real/ingesta/auth/ingesta_api_key.env

echo "INGESTA_API_KEY_LEN=${#INGESTA_API_KEY}"
echo "INGESTA_API_PROVIDER_ID=$INGESTA_API_PROVIDER_ID"

export ASSET_CONFIG="asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json"

"${BASH_BIN}" scripts/phase1_provider_publish.sh

unset INGESTA_API_KEY INGESTA_API_PROVIDER_ID

source runtime/env/latest/phase1_env.sh
```

**Expected result:**

```bash
test -n "${SUFFIX:-}" && echo "SUFFIX=$SUFFIX" || echo "FAIL SUFFIX"
test -n "${ASSET_ID:-}" && echo "ASSET_ID=$ASSET_ID" || echo "FAIL ASSET_ID"
test -n "${CD_ID:-}" && echo "CD_ID=$CD_ID" || echo "FAIL CD_ID"
test -f runtime/env/latest/phase1_env.sh && echo "OK phase1_env" || echo "FAIL phase1_env"
jq '.phases.phase1' "evidencias/runs/${SUFFIX}/summary.json"
```

`INGESTA_API_KEY` and `INGESTA_API_PROVIDER_ID` are unset before Phase 2. Phases 2–4 do not need them. The consumer never receives those values.

**STOP if:** Phase 1 fails, `phase1_env.sh` is missing, `ASSET_ID` is empty, or you see `HTTP 409`. A 409 means an object with the derived identifier already exists; start a **new** run from Phase 0. Do not try to mutate a published asset data address.

### 6.3 Phase 2

```bash
source runtime/env/latest/phase1_env.sh

"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh

source runtime/env/latest/phase2_env.sh
```

**Expected result:**

```bash
test -n "${AGREEMENT_ID:-}" && echo "AGREEMENT_ID=$AGREEMENT_ID" || echo "FAIL AGREEMENT_ID"
test -f runtime/env/latest/phase2_env.sh && echo "OK phase2_env" || echo "FAIL phase2_env"
jq '.phases.phase2' "evidencias/runs/${SUFFIX}/summary.json"
```

**STOP if:** `AGREEMENT_ID` is empty, negotiation ends `TERMINATED`, or `phase2_env.sh` is missing.

### 6.4 Phase 3

```bash
source runtime/env/latest/phase2_env.sh

"${BASH_BIN}" scripts/phase3_transfer_edr.sh

source runtime/env/latest/phase3_env.sh
```

**Expected result:**

```bash
test -n "${TRANSFER_ID:-}" && echo "TRANSFER_ID=$TRANSFER_ID" || echo "FAIL TRANSFER_ID"
test -n "${EDR_URL:-}" && echo "EDR_URL_SET=yes" || echo "FAIL EDR_URL"
test -f runtime/env/latest/phase3_env.sh && echo "OK phase3_env" || echo "FAIL phase3_env"
jq '.phases.phase3' "evidencias/runs/${SUFFIX}/summary.json"
```

Do **not** print EDR authorization.

**STOP if:** `TRANSFER_ID` is empty, EDR URL is missing, or `phase3_env.sh` is missing.

### 6.5 Phase 4

```bash
source runtime/env/latest/phase3_env.sh

"${BASH_BIN}" scripts/phase4_save_download.sh
```

Phase 4 is terminal. It does not create `phase4_env.sh`.

**Expected result:** a non-empty download and manifest exist:

```bash
DOWNLOAD_FILE="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"
MANIFEST_FILE="downloads/manifests/${ASSET_ID}/latest.manifest.json"

test -s "${DOWNLOAD_FILE}" && echo "OK download: ${DOWNLOAD_FILE}" || echo "FAIL download"
test -s "${MANIFEST_FILE}" && echo "OK manifest: ${MANIFEST_FILE}" || echo "FAIL manifest"
jq '{suffix, asset_id, bytes, media_type, sha256}' "${MANIFEST_FILE}"
jq '.phases.phase4' "evidencias/runs/${SUFFIX}/summary.json"
```

### 6.6 Semantic validation

HTTP 200 is not enough. The Ingestion API download must be valid JSON:

```bash
DOWNLOAD_FILE="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"

jq empty "${DOWNLOAD_FILE}" && echo "OK — Ingestion API returned valid JSON"
```

Do not print the payload if it may contain unapproved business data.

Keep this run identity for later evidence packaging:

```bash
export INGESTION_SUFFIX="$SUFFIX"
export INGESTION_ASSET_ID="$ASSET_ID"
echo "INGESTION_SUFFIX=$INGESTION_SUFFIX"
```

**STOP if:** `jq empty` fails, the download is empty, or phase 4 is not `ok`.

## 7. Ingestion API PROD POST — Industrias Ebro

Prerequisites:

- `BASH_BIN` selected.
- Ingestion `user_provider.sh` and `user_consumer.sh` exist.
- `ingesta_api_key_prod.env` exists (not the PRE file).
- A local JSON request body file exists for Industrias Ebro (ignored; not in Git).
- Git ignores those files.

Start from a reset shell context with a new Phase 0 and `SUFFIX`. Do not reuse section 6 state.

### 7.1 Phase 0

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"
set +x

unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR
unset SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL
unset CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID
unset INGESTA_API_REQUEST_BODY_FILE

export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=ingesta
export IPPCP_FLOW_VERSION=v2

"${BASH_BIN}" scripts/phase0_context_smoke.sh
```

Only after success:

```bash
source runtime/env/latest/phase0_env.sh

echo "SUFFIX=$SUFFIX"
echo "IPPCP_FLOW=$IPPCP_FLOW"
test -f runtime/env/latest/phase0_env.sh && echo "OK phase0_env"
jq '.phases.phase0' "evidencias/runs/${SUFFIX}/summary.json"
```

**STOP if:** Phase 0 fails, `phase0_env.sh` is missing, or you see `Missing local credentials file`.

### 7.2 Phase 1

```bash
source runtime/env/latest/phase0_env.sh
source data/real/ingesta/auth/ingesta_api_key_prod.env

echo "INGESTA_API_KEY_LEN=${#INGESTA_API_KEY}"

export ASSET_CONFIG="asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json"

"${BASH_BIN}" scripts/phase1_provider_publish.sh

unset INGESTA_API_KEY

source runtime/env/latest/phase1_env.sh
```

**Expected result:**

```bash
test -n "${SUFFIX:-}" && echo "SUFFIX=$SUFFIX" || echo "FAIL SUFFIX"
test -n "${ASSET_ID:-}" && echo "ASSET_ID=$ASSET_ID" || echo "FAIL ASSET_ID"
test -n "${CD_ID:-}" && echo "CD_ID=$CD_ID" || echo "FAIL CD_ID"
test -f runtime/env/latest/phase1_env.sh && echo "OK phase1_env" || echo "FAIL phase1_env"
jq '.phases.phase1' "evidencias/runs/${SUFFIX}/summary.json"
echo "ASSET_HTTP_METHOD=${ASSET_HTTP_METHOD:-}"
echo "ASSET_PROXY_BODY=${ASSET_PROXY_BODY:-}"
```

**STOP if:** Phase 1 fails, you sourced the PRE API key file, or `ASSET_HTTP_METHOD` is not `POST`.

### 7.3 Phase 2

```bash
source runtime/env/latest/phase1_env.sh

"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh

source runtime/env/latest/phase2_env.sh
```

**Expected result:**

```bash
test -n "${AGREEMENT_ID:-}" && echo "AGREEMENT_ID=$AGREEMENT_ID" || echo "FAIL AGREEMENT_ID"
test -f runtime/env/latest/phase2_env.sh && echo "OK phase2_env" || echo "FAIL phase2_env"
jq '.phases.phase2' "evidencias/runs/${SUFFIX}/summary.json"
```

**STOP if:** `AGREEMENT_ID` is empty, negotiation ends `TERMINATED`, or `phase2_env.sh` is missing.

### 7.4 Phase 3

```bash
source runtime/env/latest/phase2_env.sh

"${BASH_BIN}" scripts/phase3_transfer_edr.sh

source runtime/env/latest/phase3_env.sh
```

**Expected result:**

```bash
test -n "${TRANSFER_ID:-}" && echo "TRANSFER_ID=$TRANSFER_ID" || echo "FAIL TRANSFER_ID"
test -n "${EDR_URL:-}" && echo "EDR_URL_SET=yes" || echo "FAIL EDR_URL"
test -f runtime/env/latest/phase3_env.sh && echo "OK phase3_env" || echo "FAIL phase3_env"
jq '.phases.phase3' "evidencias/runs/${SUFFIX}/summary.json"
```

Do **not** print EDR authorization. Do not enable `PHASE3_TRY_DATA_CONSUMPTION=1` for POST assets.

**STOP if:** `TRANSFER_ID` is empty, EDR URL is missing, or `phase3_env.sh` is missing.

### 7.5 Phase 4 (POST metadata-only)

```bash
source runtime/env/latest/phase3_env.sh

export INGESTA_API_REQUEST_BODY_FILE="/absolute/or/repo-relative/path/to/industrias_ebro_body.json"

"${BASH_BIN}" scripts/phase4_save_download.sh

unset INGESTA_API_REQUEST_BODY_FILE
```

Replace the placeholder path with your local Industrias Ebro body file. Do not commit or paste its contents.

**Expected result:** POST control metadata exists; no GET-style download is required:

```bash
RUN_DIR="evidencias/runs/${SUFFIX}"

test -f "${RUN_DIR}/phase4/post_result.json" && echo "OK post_result"
test -f "${RUN_DIR}/phase4/post_manifest.json" && echo "OK post_manifest"
jq '{manifest_kind, http_status, download_persisted, response_body_persisted, request_body_persisted}' \
  "${RUN_DIR}/phase4/post_manifest.json"
jq '.phases.phase4' "${RUN_DIR}/summary.json"

DOWNLOAD_FILE="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"
test ! -s "${DOWNLOAD_FILE}" 2>/dev/null && echo "OK — no GET-style download expected for POST"
```

Success is `curl` exit 0 plus HTTP 2xx. The response body may be empty or non-JSON.

```bash
export INGESTION_PROD_SUFFIX="$SUFFIX"
export INGESTION_PROD_ASSET_ID="$ASSET_ID"
echo "INGESTION_PROD_SUFFIX=$INGESTION_PROD_SUFFIX"
```

**STOP if:** phase 4 is not `ok`, HTTP status is not 2xx, or request/response bodies appear in persisted evidence.

## 8. CIRCE PROD — phase 4 with a company-specific body

CIRCE PROD (`ingesta_api_pull_circe_prod.json`) is validated end-to-end through phase 4 using a CIRCE-specific request body. CIRCE uses `districtCode`, whereas the Industrias Ebro request body uses `centerId`. Do **not** reuse one company's payload for the other.

Prerequisites match section 7 except the asset config and stop condition.

Start from the [reset block in section 5.1](#51-reset-shell-context-before-each-asset).

### 8.1 Phase 0

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"
set +x

unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR
unset SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL
unset CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID
unset INGESTA_API_REQUEST_BODY_FILE

export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=ingesta
export IPPCP_FLOW_VERSION=v2

"${BASH_BIN}" scripts/phase0_context_smoke.sh
```

Only after success:

```bash
source runtime/env/latest/phase0_env.sh

echo "SUFFIX=$SUFFIX"
test -f runtime/env/latest/phase0_env.sh && echo "OK phase0_env"
jq '.phases.phase0' "evidencias/runs/${SUFFIX}/summary.json"
```

### 8.2 Phase 1

```bash
source runtime/env/latest/phase0_env.sh
source data/real/ingesta/auth/ingesta_api_key_prod.env

export ASSET_CONFIG="asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json"

"${BASH_BIN}" scripts/phase1_provider_publish.sh

unset INGESTA_API_KEY

source runtime/env/latest/phase1_env.sh

test -n "${ASSET_ID:-}" && echo "ASSET_ID=$ASSET_ID" || echo "FAIL ASSET_ID"
jq '.phases.phase1' "evidencias/runs/${SUFFIX}/summary.json"
```

### 8.3 Phase 2

```bash
source runtime/env/latest/phase1_env.sh

"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh

source runtime/env/latest/phase2_env.sh

test -n "${AGREEMENT_ID:-}" && echo "AGREEMENT_ID=$AGREEMENT_ID" || echo "FAIL AGREEMENT_ID"
jq '.phases.phase2' "evidencias/runs/${SUFFIX}/summary.json"
```

### 8.4 Phase 3 — stop here for CIRCE

```bash
source runtime/env/latest/phase2_env.sh

"${BASH_BIN}" scripts/phase3_transfer_edr.sh

source runtime/env/latest/phase3_env.sh

test -n "${TRANSFER_ID:-}" && echo "TRANSFER_ID=$TRANSFER_ID" || echo "FAIL TRANSFER_ID"
test -n "${EDR_URL:-}" && echo "EDR_URL_SET=yes" || echo "FAIL EDR_URL"
jq '.phases.phase3' "evidencias/runs/${SUFFIX}/summary.json"
```

**Expected result:** phases 0–3 are `ok` in `summary.json`; no phase 4 step unless a CIRCE-specific body is supplied.

```bash
jq -e '.phases.phase0.status == "ok" and .phases.phase1.status == "ok" and .phases.phase2.status == "ok" and .phases.phase3.status == "ok"' \
  "evidencias/runs/${SUFFIX}/summary.json" >/dev/null \
  && echo "OK — CIRCE validated through phase3" || echo "FAIL — review summary"
```

**STOP if:** any of phases 0–3 is not `ok`, or you attempt phase 4 without a CIRCE-specific body file.

## 9. WFS city — complete run

Prerequisites:

- Consumption `user_provider.sh` and `user_consumer.sh` exist.
- Do **not** reuse an Ingestion API `SUFFIX` or `runtime/env/latest` from sections 6–8.
- Do not source `ingesta_api_key.env`.

### 9.1 Phase 0

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"
set +x

unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR
unset SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL
unset CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID

export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=consumo
export IPPCP_FLOW_VERSION=v2

"${BASH_BIN}" scripts/phase0_context_smoke.sh
```

Only after success:

```bash
source runtime/env/latest/phase0_env.sh

echo "SUFFIX=$SUFFIX"
echo "IPPCP_FLOW=$IPPCP_FLOW"
test -f runtime/env/latest/phase0_env.sh && echo "OK phase0_env"
```

**STOP if:** Phase 0 fails or `phase0_env.sh` is missing. Do not run Phase 1.

### 9.2 Phase 1

```bash
source runtime/env/latest/phase0_env.sh
export ASSET_CONFIG="asset_configs/real/consumo/wfs/emisiones_wfs_ciudad_geojson.json"

"${BASH_BIN}" scripts/phase1_provider_publish.sh
```

Only after success:

```bash
source runtime/env/latest/phase1_env.sh

test -n "${SUFFIX:-}" && echo "SUFFIX=$SUFFIX" || echo "FAIL SUFFIX"
test -n "${ASSET_ID:-}" && echo "ASSET_ID=$ASSET_ID" || echo "FAIL ASSET_ID"
test -f runtime/env/latest/phase1_env.sh && echo "OK phase1_env" || echo "FAIL phase1_env"
```

**STOP if:** Phase 1 fails, `phase1_env.sh` is missing, or `ASSET_ID` is empty. Do not run Phase 2.

### 9.3 Phase 2

```bash
source runtime/env/latest/phase1_env.sh

"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh
```

Only after success:

```bash
source runtime/env/latest/phase2_env.sh

test -n "${AGREEMENT_ID:-}" && echo "AGREEMENT_ID=$AGREEMENT_ID" || echo "FAIL AGREEMENT_ID"
test -f runtime/env/latest/phase2_env.sh && echo "OK phase2_env" || echo "FAIL phase2_env"
```

**STOP if:** Phase 2 fails, `phase2_env.sh` is missing, or `AGREEMENT_ID` is empty. Do not run Phase 3.

### 9.4 Phase 3

```bash
source runtime/env/latest/phase2_env.sh

"${BASH_BIN}" scripts/phase3_transfer_edr.sh
```

Only after success:

```bash
source runtime/env/latest/phase3_env.sh

test -n "${TRANSFER_ID:-}" && echo "TRANSFER_ID=$TRANSFER_ID" || echo "FAIL TRANSFER_ID"
test -n "${EDR_URL:-}" && echo "EDR_URL_SET=yes" || echo "FAIL EDR_URL"
test -f runtime/env/latest/phase3_env.sh && echo "OK phase3_env" || echo "FAIL phase3_env"
```

Do **not** print EDR authorization.

**STOP if:** Phase 3 fails, `phase3_env.sh` is missing, or `TRANSFER_ID` is empty. Do not run Phase 4.

### 9.5 Phase 4

```bash
source runtime/env/latest/phase3_env.sh

"${BASH_BIN}" scripts/phase4_save_download.sh
```

Phase 4 is terminal. It does not create `phase4_env.sh`.

**STOP if:** Phase 4 fails.

### 9.6 Semantic validation

HTTP 200 and generic JSON are not enough. The download must be a GeoJSON `FeatureCollection`:

```bash
DOWNLOAD_FILE="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"
MANIFEST_FILE="downloads/manifests/${ASSET_ID}/latest.manifest.json"

jq empty "$DOWNLOAD_FILE" && echo "OK JSON"
jq -e '
  type == "object"
  and .type == "FeatureCollection"
  and (.features | type == "array")
  and all(
    .features[];
    type == "object"
    and .type == "Feature"
    and (.properties | type == "object")
    and (.geometry == null or (.geometry | type == "object"))
  )
' "$DOWNLOAD_FILE" >/dev/null \
  && echo "OK — valid GeoJSON FeatureCollection"

jq '{type, feature_count: (.features | length)}' "$DOWNLOAD_FILE"
jq '{suffix, asset_id, bytes, media_type, sha256}' "$MANIFEST_FILE"
```

```bash
export WFS_CITY_SUFFIX="$SUFFIX"
export WFS_CITY_ASSET_ID="$ASSET_ID"
echo "WFS_CITY_SUFFIX=$WFS_CITY_SUFFIX"
```

**STOP if:** the GeoJSON check fails, even when HTTP 200 succeeded.

## 10. WFS districts / juntas — complete run

Start a **new** Phase 0. Do not reuse the WFS city `SUFFIX`.

### 10.1 Phase 0

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"
set +x

unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR
unset SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL
unset CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID

export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=consumo
export IPPCP_FLOW_VERSION=v2

"${BASH_BIN}" scripts/phase0_context_smoke.sh
```

Only after success:

```bash
source runtime/env/latest/phase0_env.sh

echo "SUFFIX=$SUFFIX"
echo "IPPCP_FLOW=$IPPCP_FLOW"
test -f runtime/env/latest/phase0_env.sh && echo "OK phase0_env"
```

**STOP if:** Phase 0 fails or `phase0_env.sh` is missing. Do not run Phase 1.

### 10.2 Phase 1

```bash
source runtime/env/latest/phase0_env.sh
export ASSET_CONFIG="asset_configs/real/consumo/wfs/emisiones_wfs_juntas_geojson.json"

"${BASH_BIN}" scripts/phase1_provider_publish.sh
```

Only after success:

```bash
source runtime/env/latest/phase1_env.sh

test -n "${SUFFIX:-}" && echo "SUFFIX=$SUFFIX" || echo "FAIL SUFFIX"
test -n "${ASSET_ID:-}" && echo "ASSET_ID=$ASSET_ID" || echo "FAIL ASSET_ID"
test -f runtime/env/latest/phase1_env.sh && echo "OK phase1_env" || echo "FAIL phase1_env"
```

**STOP if:** Phase 1 fails, `phase1_env.sh` is missing, or `ASSET_ID` is empty. Do not run Phase 2.

### 10.3 Phase 2

```bash
source runtime/env/latest/phase1_env.sh

"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh
```

Only after success:

```bash
source runtime/env/latest/phase2_env.sh

test -n "${AGREEMENT_ID:-}" && echo "AGREEMENT_ID=$AGREEMENT_ID" || echo "FAIL AGREEMENT_ID"
test -f runtime/env/latest/phase2_env.sh && echo "OK phase2_env" || echo "FAIL phase2_env"
```

**STOP if:** Phase 2 fails, `phase2_env.sh` is missing, or `AGREEMENT_ID` is empty. Do not run Phase 3.

### 10.4 Phase 3

```bash
source runtime/env/latest/phase2_env.sh

"${BASH_BIN}" scripts/phase3_transfer_edr.sh
```

Only after success:

```bash
source runtime/env/latest/phase3_env.sh

test -n "${TRANSFER_ID:-}" && echo "TRANSFER_ID=$TRANSFER_ID" || echo "FAIL TRANSFER_ID"
test -n "${EDR_URL:-}" && echo "EDR_URL_SET=yes" || echo "FAIL EDR_URL"
test -f runtime/env/latest/phase3_env.sh && echo "OK phase3_env" || echo "FAIL phase3_env"
```

Do **not** print EDR authorization.

**STOP if:** Phase 3 fails, `phase3_env.sh` is missing, or `TRANSFER_ID` is empty. Do not run Phase 4.

### 10.5 Phase 4

```bash
source runtime/env/latest/phase3_env.sh

"${BASH_BIN}" scripts/phase4_save_download.sh
```

Phase 4 is terminal. It does not create `phase4_env.sh`.

**STOP if:** Phase 4 fails.

### 10.6 Semantic validation

HTTP 200 and generic JSON are not enough. The download must be a GeoJSON `FeatureCollection`:

```bash
DOWNLOAD_FILE="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"
MANIFEST_FILE="downloads/manifests/${ASSET_ID}/latest.manifest.json"

jq empty "$DOWNLOAD_FILE" && echo "OK JSON"
jq -e '
  type == "object"
  and .type == "FeatureCollection"
  and (.features | type == "array")
  and all(
    .features[];
    type == "object"
    and .type == "Feature"
    and (.properties | type == "object")
    and (.geometry == null or (.geometry | type == "object"))
  )
' "$DOWNLOAD_FILE" >/dev/null \
  && echo "OK — valid GeoJSON FeatureCollection"

jq '{type, feature_count: (.features | length)}' "$DOWNLOAD_FILE"
jq '{suffix, asset_id, bytes, media_type, sha256}' "$MANIFEST_FILE"
```

```bash
export WFS_JUNTAS_SUFFIX="$SUFFIX"
export WFS_JUNTAS_ASSET_ID="$ASSET_ID"
echo "WFS_JUNTAS_SUFFIX=$WFS_JUNTAS_SUFFIX"
```

**STOP if:** the GeoJSON check fails, even when HTTP 200 succeeded.

## 11. SPARQL — complete run

Start a **new** Phase 0. Use the canonical JSON-format configuration. A SPARQL XML body with HTTP 200 is a failure.

### 11.1 Phase 0

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"
set +x

unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR
unset SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL
unset CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID

export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=consumo
export IPPCP_FLOW_VERSION=v2

"${BASH_BIN}" scripts/phase0_context_smoke.sh
```

Only after success:

```bash
source runtime/env/latest/phase0_env.sh

echo "SUFFIX=$SUFFIX"
echo "IPPCP_FLOW=$IPPCP_FLOW"
test -f runtime/env/latest/phase0_env.sh && echo "OK phase0_env"
```

**STOP if:** Phase 0 fails or `phase0_env.sh` is missing. Do not run Phase 1.

### 11.2 Phase 1

```bash
source runtime/env/latest/phase0_env.sh
export ASSET_CONFIG="asset_configs/real/consumo/sparql/emisiones_sparql_limit10_format_json.json"

"${BASH_BIN}" scripts/phase1_provider_publish.sh
```

Only after success:

```bash
source runtime/env/latest/phase1_env.sh

test -n "${SUFFIX:-}" && echo "SUFFIX=$SUFFIX" || echo "FAIL SUFFIX"
test -n "${ASSET_ID:-}" && echo "ASSET_ID=$ASSET_ID" || echo "FAIL ASSET_ID"
test -f runtime/env/latest/phase1_env.sh && echo "OK phase1_env" || echo "FAIL phase1_env"
```

**STOP if:** Phase 1 fails, `phase1_env.sh` is missing, or `ASSET_ID` is empty. Do not run Phase 2.

### 11.3 Phase 2

```bash
source runtime/env/latest/phase1_env.sh

"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh
```

Only after success:

```bash
source runtime/env/latest/phase2_env.sh

test -n "${AGREEMENT_ID:-}" && echo "AGREEMENT_ID=$AGREEMENT_ID" || echo "FAIL AGREEMENT_ID"
test -f runtime/env/latest/phase2_env.sh && echo "OK phase2_env" || echo "FAIL phase2_env"
```

**STOP if:** Phase 2 fails, `phase2_env.sh` is missing, or `AGREEMENT_ID` is empty. Do not run Phase 3.

### 11.4 Phase 3

```bash
source runtime/env/latest/phase2_env.sh

"${BASH_BIN}" scripts/phase3_transfer_edr.sh
```

Only after success:

```bash
source runtime/env/latest/phase3_env.sh

test -n "${TRANSFER_ID:-}" && echo "TRANSFER_ID=$TRANSFER_ID" || echo "FAIL TRANSFER_ID"
test -n "${EDR_URL:-}" && echo "EDR_URL_SET=yes" || echo "FAIL EDR_URL"
test -f runtime/env/latest/phase3_env.sh && echo "OK phase3_env" || echo "FAIL phase3_env"
```

Do **not** print EDR authorization.

**STOP if:** Phase 3 fails, `phase3_env.sh` is missing, or `TRANSFER_ID` is empty. Do not run Phase 4.

### 11.5 Phase 4

```bash
source runtime/env/latest/phase3_env.sh

"${BASH_BIN}" scripts/phase4_save_download.sh
```

Phase 4 is terminal. It does not create `phase4_env.sh`.

**STOP if:** Phase 4 fails.

### 11.6 Semantic validation

HTTP 200 is not enough. The download must be SPARQL Results JSON. XML with HTTP 200 is a failure.

```bash
DOWNLOAD_FILE="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"
MANIFEST_FILE="downloads/manifests/${ASSET_ID}/latest.manifest.json"

jq -e '
  type == "object"
  and (.head | type == "object")
  and (.results | type == "object")
  and (.results.bindings | type == "array")
  and all(.results.bindings[]; type == "object")
' "$DOWNLOAD_FILE" >/dev/null \
  && echo "OK — valid SPARQL Results JSON"

jq '{
  vars: .head.vars,
  binding_count: (.results.bindings | length)
}' "$DOWNLOAD_FILE"
jq '{suffix, asset_id, bytes, media_type, sha256}' "$MANIFEST_FILE"
```

```bash
export SPARQL_SUFFIX="$SUFFIX"
export SPARQL_ASSET_ID="$ASSET_ID"
echo "SPARQL_SUFFIX=$SPARQL_SUFFIX"
```

**STOP if:** the SPARQL Results JSON check fails, the body is XML, or you used `emisiones_sparql_limit10.json` instead of `*_format_json.json`.

## 12. Complete copy/paste runs

Each block below is a full run from a clean shell context. Replace placeholder body paths before executing PROD POST.

### 12.1 PRE GET complete (phases 0–4)

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"; set +x
unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID
export IPPCP_DATASPACE=ippcp IPPCP_FLOW=ingesta IPPCP_FLOW_VERSION=v2
"${BASH_BIN}" scripts/phase0_context_smoke.sh || exit 1
source runtime/env/latest/phase0_env.sh
source data/real/ingesta/auth/ingesta_api_key.env
export ASSET_CONFIG="asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json"
"${BASH_BIN}" scripts/phase1_provider_publish.sh || exit 1
unset INGESTA_API_KEY INGESTA_API_PROVIDER_ID
source runtime/env/latest/phase1_env.sh
"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh || exit 1
source runtime/env/latest/phase2_env.sh
"${BASH_BIN}" scripts/phase3_transfer_edr.sh || exit 1
source runtime/env/latest/phase3_env.sh
"${BASH_BIN}" scripts/phase4_save_download.sh || exit 1
jq -e '.phases.phase0.status == "ok" and .phases.phase1.status == "ok" and .phases.phase2.status == "ok" and .phases.phase3.status == "ok" and .phases.phase4.status == "ok"' "evidencias/runs/${SUFFIX}/summary.json" >/dev/null || exit 1
DOWNLOAD_FILE="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"
MANIFEST_FILE="downloads/manifests/${ASSET_ID}/latest.manifest.json"
test -s "$DOWNLOAD_FILE" && echo "OK download" || exit 1
test -s "$MANIFEST_FILE" && echo "OK manifest" || exit 1
jq empty "$DOWNLOAD_FILE" && echo "OK valid JSON" || exit 1
jq '{suffix, asset_id, bytes, media_type, sha256}' "$MANIFEST_FILE"
LATEST_FILE=$(jq -r '.latest_file' "$MANIFEST_FILE")
EXPECTED_SHA=$(jq -r '.sha256' "$MANIFEST_FILE")
if command -v shasum >/dev/null 2>&1; then ACTUAL_SHA=$(shasum -a 256 "$LATEST_FILE" | awk '{print $1}'); elif command -v sha256sum >/dev/null 2>&1; then ACTUAL_SHA=$(sha256sum "$LATEST_FILE" | awk '{print $1}'); else ACTUAL_SHA=""; fi
[ -n "$ACTUAL_SHA" ] && [ "$EXPECTED_SHA" = "$ACTUAL_SHA" ] && echo "OK SHA256" || exit 1
```

### 12.2 Industrias Ebro PROD POST complete (phases 0–4)

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"; set +x
unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID INGESTA_API_REQUEST_BODY_FILE
export IPPCP_DATASPACE=ippcp IPPCP_FLOW=ingesta IPPCP_FLOW_VERSION=v2
"${BASH_BIN}" scripts/phase0_context_smoke.sh || exit 1
source runtime/env/latest/phase0_env.sh
source data/real/ingesta/auth/ingesta_api_key_prod.env
export ASSET_CONFIG="asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json"
"${BASH_BIN}" scripts/phase1_provider_publish.sh || exit 1
unset INGESTA_API_KEY INGESTA_API_PROVIDER_ID
source runtime/env/latest/phase1_env.sh
"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh || exit 1
source runtime/env/latest/phase2_env.sh
"${BASH_BIN}" scripts/phase3_transfer_edr.sh || exit 1
source runtime/env/latest/phase3_env.sh
export INGESTA_API_REQUEST_BODY_FILE="/absolute/or/repo-relative/path/to/industrias_ebro_body.json"
test -s "$INGESTA_API_REQUEST_BODY_FILE" && jq empty "$INGESTA_API_REQUEST_BODY_FILE" || exit 1
"${BASH_BIN}" scripts/phase4_save_download.sh || exit 1
unset INGESTA_API_REQUEST_BODY_FILE
RUN_DIR="evidencias/runs/${SUFFIX}"
jq -e '.phases.phase0.status == "ok" and .phases.phase1.status == "ok" and .phases.phase2.status == "ok" and .phases.phase3.status == "ok" and .phases.phase4.status == "ok"' "$RUN_DIR/summary.json" >/dev/null || exit 1
test -s "$RUN_DIR/phase4/post_result.json" && echo "OK post_result" || exit 1
test -s "$RUN_DIR/phase4/post_manifest.json" && echo "OK post_manifest" || exit 1
jq . "$RUN_DIR/phase4/post_result.json"
jq . "$RUN_DIR/phase4/post_manifest.json"
jq -e '.manifest_kind == "post_metadata_only" and .request_body_persisted == false and .response_body_persisted == false and .download_persisted == false and (.http_status | tonumber) >= 200 and (.http_status | tonumber) < 300' "$RUN_DIR/phase4/post_manifest.json" >/dev/null && echo "OK POST metadata-only" || exit 1
```

### 12.3 CIRCE PROD through phase 3

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"; set +x
unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID
export IPPCP_DATASPACE=ippcp IPPCP_FLOW=ingesta IPPCP_FLOW_VERSION=v2
"${BASH_BIN}" scripts/phase0_context_smoke.sh || exit 1
source runtime/env/latest/phase0_env.sh
source data/real/ingesta/auth/ingesta_api_key_prod.env
export ASSET_CONFIG="asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json"
"${BASH_BIN}" scripts/phase1_provider_publish.sh || exit 1
unset INGESTA_API_KEY INGESTA_API_PROVIDER_ID
source runtime/env/latest/phase1_env.sh
"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh || exit 1
source runtime/env/latest/phase2_env.sh
"${BASH_BIN}" scripts/phase3_transfer_edr.sh || exit 1
source runtime/env/latest/phase3_env.sh
jq -e '.phases.phase0.status == "ok" and .phases.phase1.status == "ok" and .phases.phase2.status == "ok" and .phases.phase3.status == "ok"' "evidencias/runs/${SUFFIX}/summary.json" >/dev/null || exit 1
echo "STOP — do not run phase 4 without a CIRCE-specific body file; never reuse the Industrias Ebro payload"
```

### 12.4 WFS city complete (phases 0–4)

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"; set +x
unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID
export IPPCP_DATASPACE=ippcp IPPCP_FLOW=consumo IPPCP_FLOW_VERSION=v2
"${BASH_BIN}" scripts/phase0_context_smoke.sh || exit 1
source runtime/env/latest/phase0_env.sh
export ASSET_CONFIG="asset_configs/real/consumo/wfs/emisiones_wfs_ciudad_geojson.json"
"${BASH_BIN}" scripts/phase1_provider_publish.sh || exit 1
source runtime/env/latest/phase1_env.sh
"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh || exit 1
source runtime/env/latest/phase2_env.sh
"${BASH_BIN}" scripts/phase3_transfer_edr.sh || exit 1
source runtime/env/latest/phase3_env.sh
"${BASH_BIN}" scripts/phase4_save_download.sh || exit 1
jq -e '.phases.phase0.status == "ok" and .phases.phase1.status == "ok" and .phases.phase2.status == "ok" and .phases.phase3.status == "ok" and .phases.phase4.status == "ok"' "evidencias/runs/${SUFFIX}/summary.json" >/dev/null || exit 1
DOWNLOAD_FILE="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"
MANIFEST_FILE="downloads/manifests/${ASSET_ID}/latest.manifest.json"
test -s "$DOWNLOAD_FILE" && echo "OK download" || exit 1
test -s "$MANIFEST_FILE" && echo "OK manifest" || exit 1
jq empty "$DOWNLOAD_FILE" && echo "OK JSON"
jq -e 'type == "object" and .type == "FeatureCollection" and (.features | type == "array") and all(.features[]; type == "object" and .type == "Feature" and (.properties | type == "object") and (.geometry == null or (.geometry | type == "object")))' "$DOWNLOAD_FILE" >/dev/null && echo "OK — valid GeoJSON FeatureCollection" || exit 1
jq '{type, feature_count: (.features | length)}' "$DOWNLOAD_FILE"
jq '{suffix, asset_id, bytes, media_type, sha256}' "$MANIFEST_FILE"
LATEST_FILE=$(jq -r '.latest_file' "$MANIFEST_FILE")
EXPECTED_SHA=$(jq -r '.sha256' "$MANIFEST_FILE")
if command -v shasum >/dev/null 2>&1; then ACTUAL_SHA=$(shasum -a 256 "$LATEST_FILE" | awk '{print $1}'); elif command -v sha256sum >/dev/null 2>&1; then ACTUAL_SHA=$(sha256sum "$LATEST_FILE" | awk '{print $1}'); else ACTUAL_SHA=""; fi
[ -n "$ACTUAL_SHA" ] && [ "$EXPECTED_SHA" = "$ACTUAL_SHA" ] && echo "OK SHA256" || exit 1
```

### 12.5 WFS juntas complete (phases 0–4)

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"; set +x
unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID
export IPPCP_DATASPACE=ippcp IPPCP_FLOW=consumo IPPCP_FLOW_VERSION=v2
"${BASH_BIN}" scripts/phase0_context_smoke.sh || exit 1
source runtime/env/latest/phase0_env.sh
export ASSET_CONFIG="asset_configs/real/consumo/wfs/emisiones_wfs_juntas_geojson.json"
"${BASH_BIN}" scripts/phase1_provider_publish.sh || exit 1
source runtime/env/latest/phase1_env.sh
"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh || exit 1
source runtime/env/latest/phase2_env.sh
"${BASH_BIN}" scripts/phase3_transfer_edr.sh || exit 1
source runtime/env/latest/phase3_env.sh
"${BASH_BIN}" scripts/phase4_save_download.sh || exit 1
jq -e '.phases.phase0.status == "ok" and .phases.phase1.status == "ok" and .phases.phase2.status == "ok" and .phases.phase3.status == "ok" and .phases.phase4.status == "ok"' "evidencias/runs/${SUFFIX}/summary.json" >/dev/null || exit 1
DOWNLOAD_FILE="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"
MANIFEST_FILE="downloads/manifests/${ASSET_ID}/latest.manifest.json"
test -s "$DOWNLOAD_FILE" && echo "OK download" || exit 1
test -s "$MANIFEST_FILE" && echo "OK manifest" || exit 1
jq empty "$DOWNLOAD_FILE" && echo "OK JSON"
jq -e 'type == "object" and .type == "FeatureCollection" and (.features | type == "array") and all(.features[]; type == "object" and .type == "Feature" and (.properties | type == "object") and (.geometry == null or (.geometry | type == "object")))' "$DOWNLOAD_FILE" >/dev/null && echo "OK — valid GeoJSON FeatureCollection" || exit 1
jq '{type, feature_count: (.features | length)}' "$DOWNLOAD_FILE"
jq '{suffix, asset_id, bytes, media_type, sha256}' "$MANIFEST_FILE"
LATEST_FILE=$(jq -r '.latest_file' "$MANIFEST_FILE")
EXPECTED_SHA=$(jq -r '.sha256' "$MANIFEST_FILE")
if command -v shasum >/dev/null 2>&1; then ACTUAL_SHA=$(shasum -a 256 "$LATEST_FILE" | awk '{print $1}'); elif command -v sha256sum >/dev/null 2>&1; then ACTUAL_SHA=$(sha256sum "$LATEST_FILE" | awk '{print $1}'); else ACTUAL_SHA=""; fi
[ -n "$ACTUAL_SHA" ] && [ "$EXPECTED_SHA" = "$ACTUAL_SHA" ] && echo "OK SHA256" || exit 1
```

### 12.6 SPARQL JSON complete (phases 0–4)

```bash
export BASH_BIN="${BASH_BIN:-$(command -v bash)}"; set +x
unset IPPCP_DATASPACE_FILE IPPCP_DATASPACE_DIR IPPCP_FLOW_DIR SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID EDR_URL CD_ID VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID
export IPPCP_DATASPACE=ippcp IPPCP_FLOW=consumo IPPCP_FLOW_VERSION=v2
"${BASH_BIN}" scripts/phase0_context_smoke.sh || exit 1
source runtime/env/latest/phase0_env.sh
export ASSET_CONFIG="asset_configs/real/consumo/sparql/emisiones_sparql_limit10_format_json.json"
"${BASH_BIN}" scripts/phase1_provider_publish.sh || exit 1
source runtime/env/latest/phase1_env.sh
"${BASH_BIN}" scripts/phase2_consumer_negotiate.sh || exit 1
source runtime/env/latest/phase2_env.sh
"${BASH_BIN}" scripts/phase3_transfer_edr.sh || exit 1
source runtime/env/latest/phase3_env.sh
"${BASH_BIN}" scripts/phase4_save_download.sh || exit 1
jq -e '.phases.phase0.status == "ok" and .phases.phase1.status == "ok" and .phases.phase2.status == "ok" and .phases.phase3.status == "ok" and .phases.phase4.status == "ok"' "evidencias/runs/${SUFFIX}/summary.json" >/dev/null || exit 1
DOWNLOAD_FILE="downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}"
MANIFEST_FILE="downloads/manifests/${ASSET_ID}/latest.manifest.json"
test -s "$DOWNLOAD_FILE" && echo "OK download" || exit 1
test -s "$MANIFEST_FILE" && echo "OK manifest" || exit 1
jq -e 'type == "object" and (.head | type == "object") and (.results | type == "object") and (.results.bindings | type == "array") and all(.results.bindings[]; type == "object")' "$DOWNLOAD_FILE" >/dev/null && echo "OK — valid SPARQL Results JSON" || exit 1
jq '{vars: .head.vars, binding_count: (.results.bindings | length)}' "$DOWNLOAD_FILE"
jq '{suffix, asset_id, bytes, media_type, sha256}' "$MANIFEST_FILE"
LATEST_FILE=$(jq -r '.latest_file' "$MANIFEST_FILE")
EXPECTED_SHA=$(jq -r '.sha256' "$MANIFEST_FILE")
if command -v shasum >/dev/null 2>&1; then ACTUAL_SHA=$(shasum -a 256 "$LATEST_FILE" | awk '{print $1}'); elif command -v sha256sum >/dev/null 2>&1; then ACTUAL_SHA=$(sha256sum "$LATEST_FILE" | awk '{print $1}'); else ACTUAL_SHA=""; fi
[ -n "$ACTUAL_SHA" ] && [ "$EXPECTED_SHA" = "$ACTUAL_SHA" ] && echo "OK SHA256" || exit 1
```

## 13. Run isolation and SUFFIX

Each asset requires:

- a new Phase 0;
- a new `SUFFIX`.

Do not reuse `runtime/env/latest` from a different asset. Those files are overwritten every time a later run exports phase state.

Recommended order:

1. Ingestion API PRE GET: Phase 0 → 4, then save `INGESTION_SUFFIX`.
2. Ingestion API PROD POST (Industrias Ebro): new Phase 0 → 4, then save `INGESTION_PROD_SUFFIX` (optional).
3. CIRCE PROD: new Phase 0 → 3 only unless a CIRCE-specific body is available.
4. WFS city: new Phase 0 → 4, then save `WFS_CITY_SUFFIX`.
5. WFS juntas: new Phase 0 → 4, then save `WFS_JUNTAS_SUFFIX`.
6. SPARQL: new Phase 0 → 4, then save `SPARQL_SUFFIX`.

If another asset overwrote `runtime/env/latest` before the current run was completed, restart that asset from Phase 0.

`runtime/env/latest` is the operational handoff for the run in progress. Run-specific files under `evidencias/runs/<SUFFIX>/` are historical traceability, not a supported resume mechanism.

## 14. Runtime, traceability, and inspection

```text
run_id = SUFFIX
```

The same `SUFFIX` correlates publication, negotiation, transfer, evidence, download, and manifest.

```text
evidencias/runs/<SUFFIX>/
  phase0/
  phase1/
  phase2/
  phase3/
  phase4/                    # materialized response or POST metadata-only
  summary.json

runtime/env/latest/

downloads/assets/<ASSET_ID>/           # materialized-response flows only
  <SUFFIX>.<extension>
  latest.<extension>

downloads/manifests/<ASSET_ID>/         # materialized-response flows only
  <SUFFIX>.manifest.json
  latest.manifest.json
```

- `runtime/env/latest/` is the operational handoff for the run in progress.
- Run-specific files under `evidencias/runs/<SUFFIX>/` and `downloads/.../<SUFFIX>.*` (materialized-response flows) are historical traceability.
- `latest.*` is overwritten when a new materialized result is generated for the same `ASSET_ID`. Do not use `latest.*` alone to identify historical evidence.
- PROD POST runs do not create GET-style downloads; inspect `phase4/post_result.json` and `phase4/post_manifest.json` instead.

Select the run explicitly before inspecting:

```bash
export SUFFIX="<suffix>"
export ASSET_ID="<asset_id>"
RUN_DIR="evidencias/runs/${SUFFIX}"
test -d "$RUN_DIR" && echo "OK run dir" || echo "FAIL run dir"
test -f "$RUN_DIR/summary.json" && echo "OK summary" || echo "FAIL summary"
```

Inspect the current run without printing secrets:

```bash
RUN_DIR="evidencias/runs/${SUFFIX}"

jq '{suffix, ds_name, started_at, phases}' "$RUN_DIR/summary.json"

if test -f "${RUN_DIR}/phase4/post_manifest.json"; then
  jq '{manifest_kind, http_status, download_persisted, response_body_persisted}' \
    "${RUN_DIR}/phase4/post_manifest.json"
else
  MANIFEST_FILE="downloads/manifests/${ASSET_ID}/latest.manifest.json"
  jq '{suffix, asset_id, content_kind, extension, media_type, bytes, sha256, latest_file}' \
    "${MANIFEST_FILE}"
fi
```

Verify SHA-256 on macOS (`shasum`) or Linux (`sha256sum`) for **materialized-response** runs only:

```bash
MANIFEST_FILE="downloads/manifests/${ASSET_ID}/latest.manifest.json"
LATEST_FILE=$(jq -r '.latest_file' "${MANIFEST_FILE}")
EXPECTED_SHA=$(jq -r '.sha256' "${MANIFEST_FILE}")

if command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA=$(shasum -a 256 "${LATEST_FILE}" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA=$(sha256sum "${LATEST_FILE}" | awk '{print $1}')
else
  echo "No SHA-256 tool found"
  ACTUAL_SHA=""
fi

echo "EXPECTED_SHA=$EXPECTED_SHA"
echo "ACTUAL_SHA=$ACTUAL_SHA"

[ -n "$ACTUAL_SHA" ] && [ "$EXPECTED_SHA" = "$ACTUAL_SHA" ] && echo "OK SHA256" || echo "FAIL SHA256"
```

Prefer the run-specific files when comparing historical runs:

```text
downloads/assets/<ASSET_ID>/<SUFFIX>.<extension>
downloads/manifests/<ASSET_ID>/<SUFFIX>.manifest.json
```

### Inspect summary and phase artifacts

```bash
jq '{suffix, ds_name, started_at, phases}' "$RUN_DIR/summary.json"
jq '.phases.phase0' "$RUN_DIR/summary.json"
jq '.phases.phase4' "$RUN_DIR/summary.json"
find "$RUN_DIR" -maxdepth 2 -type f -print | sort
```

### PROD POST metadata-only inspection

Do not expect `downloads/assets/` or a GET-style manifest for PROD POST.

```bash
POST_RESULT="$RUN_DIR/phase4/post_result.json"
POST_MANIFEST="$RUN_DIR/phase4/post_manifest.json"
test -s "$POST_RESULT" && echo "OK post_result" || echo "FAIL post_result"
test -s "$POST_MANIFEST" && echo "OK post_manifest" || echo "FAIL post_manifest"
jq '{manifest_kind, http_status, download_persisted, response_body_persisted, request_body_persisted}' "$POST_MANIFEST"
```

### Compare run-specific vs latest (materialized-response flows)

```bash
RUN_DOWNLOAD=$(find "downloads/assets/${ASSET_ID}" -maxdepth 1 -type f -name "${SUFFIX}.*" | head -1)
LATEST_DOWNLOAD=$(find "downloads/assets/${ASSET_ID}" -maxdepth 1 -type f -name 'latest.*' | head -1)
echo "RUN_DOWNLOAD=$RUN_DOWNLOAD"
echo "LATEST_DOWNLOAD=$LATEST_DOWNLOAD"
test -n "$RUN_DOWNLOAD" -a -n "$LATEST_DOWNLOAD" && cmp -s "$RUN_DOWNLOAD" "$LATEST_DOWNLOAD" && echo "OK same bytes" || echo "DIFFERENT or missing"
```

### Check runtime env presence (do not print contents on screen)

```bash
for f in phase0_env.sh phase1_env.sh phase2_env.sh phase3_env.sh; do
  test -f "runtime/env/latest/$f" && echo "OK $f" || echo "MISSING $f"
done
```

### Search for suspicious artifact names

```bash
find "$RUN_DIR" -type f \( -name '*.sensitive.json' -o -name '*.secret.json' \) -print
rg -n -i 'authorization|bearer|api[_-]?key|password|token|secret' "$RUN_DIR" || true
```

## 15. Full-run success validation

Use the validator that matches the profile. A missing `phase4` must **never** pass as a complete PRE GET, Industrias Ebro PROD, WFS, or SPARQL run.

### Strict phases 0–4 validator

For PRE GET, Industrias Ebro PROD, WFS city, WFS juntas, and SPARQL:

```bash
jq -e '
  .phases.phase0.status == "ok"
  and .phases.phase1.status == "ok"
  and .phases.phase2.status == "ok"
  and .phases.phase3.status == "ok"
  and .phases.phase4.status == "ok"
' "evidencias/runs/${SUFFIX}/summary.json" >/dev/null \
  && echo "OK — complete run phases 0-4" \
  || echo "FAIL — review summary"
```

### Strict phases 0–3 validator (CIRCE PROD only)

```bash
jq -e '
  .phases.phase0.status == "ok"
  and .phases.phase1.status == "ok"
  and .phases.phase2.status == "ok"
  and .phases.phase3.status == "ok"
' "evidencias/runs/${SUFFIX}/summary.json" >/dev/null \
  && echo "OK — CIRCE validated through phase3" \
  || echo "FAIL — review summary"
```

Also require the profile-specific check:

- **PRE GET Ingestion API, WFS, SPARQL:** semantic validation from sections 6, 9–11; non-empty download; manifest SHA-256.
- **PROD POST Industrias Ebro:** HTTP 2xx; `post_manifest.json` with `manifest_kind=post_metadata_only`; no GET-style download required.
- **CIRCE PROD (phases 0–4):** validated end-to-end with a CIRCE-specific request body; do not reuse the Industrias Ebro payload.

**STOP if:** any required phase is not `ok`, or profile-specific validation failed.

## 16. Evidence tooling

T1–T4 are **presentation slots**, not asset types.

```text
run  ->  asset classification
asset  ->  critical / publication_profile / publication_safe
```

The tool classifies each run from `summary.json`, asset metadata, phases, and media type. Slot order is arbitrary.

Do not restore the obsolete mapping `T1=CSV`, `T2=WFS`, `T3=SPARQL`, `T4=Ingestion API`. Do not use `--only-tests T4` as the Ingestion API Golden Path.

Practical commands below. Semantics: [tools/tools_README.md](../tools/tools_README.md), [tools/evidence_tooling.md](../tools/evidence_tooling.md), [Evidence and traceability](evidence-and-traceability.md), [Evidence publication](evidence-publication.md).

Evidence tooling requires **Python 3.10 or newer**. Conda is optional and is not required.

```bash
python3 --version
command -v jq
command -v unzip
command -v rg
python3 -m pip install -r tools/requirements-evidence-export.txt
```

Optional clean venv:

```bash
python3 -m venv .venv-evidence
source .venv-evidence/bin/activate
python -m pip install --upgrade pip
python -m pip install -r tools/requirements-evidence-export.txt
```

### Slot selection examples

T1–T4 are presentation slots. Without `--tests` or `--preset`, there is no implicit selection.

```bash
TESTS="T1=$INGESTION_SUFFIX"
TESTS="T1=$INGESTION_SUFFIX,T3=$SPARQL_SUFFIX"
TESTS="T1=$INGESTION_SUFFIX,T2=$WFS_JUNTAS_SUFFIX,T3=$WFS_CITY_SUFFIX,T4=$SPARQL_SUFFIX"
```

`--only-tests` filters an already selected set; it does not invent slots. Example:

```bash
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --preset legacy_assessment \
  --only-tests T1 \
  --timestamp "$(date +%Y%m%d_%H%M%S)" \
  --export-dir reports/exports/legacy_subset \
  --strict
```

Historical presets:

```text
--preset legacy_assessment
--preset legacy_test3
```

Use placeholder suffix variables from your local runs. Never paste real suffixes into documentation.

```bash
: "${INGESTION_SUFFIX:?Set INGESTION_SUFFIX from the Ingestion API run}"
: "${WFS_JUNTAS_SUFFIX:?Set WFS_JUNTAS_SUFFIX from the juntas run}"
: "${WFS_CITY_SUFFIX:?Set WFS_CITY_SUFFIX from the city run}"
: "${SPARQL_SUFFIX:?Set SPARQL_SUFFIX from the SPARQL run}"
```

COMPLETE and SINGLE use independent timestamps and export directories. Run SINGLE after COMPLETE without overwriting COMPLETE artifacts.

### COMPLETE example

This assignment is an example only. Slot order is arbitrary:

- T1 = Ingestion API
- T2 = WFS juntas
- T3 = WFS city
- T4 = SPARQL

```bash
COMPLETE_TS=$(date +%Y%m%d_%H%M%S)
COMPLETE_EXPORT_DIR="reports/exports/complete_$COMPLETE_TS"
COMPLETE_WORKBOOK="$COMPLETE_EXPORT_DIR/ippcp_evidence_summary_${COMPLETE_TS}.xlsx"
COMPLETE_ZIP="$COMPLETE_EXPORT_DIR/ippcp_evidence_package_${COMPLETE_TS}.zip"
COMPLETE_TESTS="T1=$INGESTION_SUFFIX,T2=$WFS_JUNTAS_SUFFIX,T3=$WFS_CITY_SUFFIX,T4=$SPARQL_SUFFIX"

python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "$COMPLETE_TESTS" \
  --timestamp "$COMPLETE_TS" \
  --export-dir "$COMPLETE_EXPORT_DIR" \
  --strict

python3 tools/package_evidence_bundle.py \
  --config tools/evidence_export.tests.yaml \
  --tests "$COMPLETE_TESTS" \
  --excel "$COMPLETE_WORKBOOK" \
  --timestamp "$COMPLETE_TS" \
  --export-dir "$COMPLETE_EXPORT_DIR" \
  --strict
```

Use the same `COMPLETE_TS` for the workbook and the ZIP. Do not recompute it between the two commands.

Inspect publication status from the generated ZIP:

```bash
unzip -p "$COMPLETE_ZIP" ippcp_evidence_package/package_status.json | jq '{publication_ready, publication_blockers}'
unzip -p "$COMPLETE_ZIP" ippcp_evidence_package/slot_inventory.json | jq .
```

`publication_ready=true` means package policies permit publication. Manual review is still required.

`publication_ready=false` means this is an internal artifact. Do not share it externally.

A COMPLETE package that includes WFS or SPARQL is normally `publication_ready=false`.

**STOP if:** `publication_ready=false` and the artifact is intended for external sharing.

### SINGLE example

SINGLE is independently executable after COMPLETE. It uses its own timestamp and export directory.

This deliberately puts Ingestion API in T3 to show slot independence.

The workbook is a local review artifact. `minimal_publication` excludes Excel from the publication ZIP, so the package command does not receive `--excel`. That allows `--strict` package validation without weakening the command.

```bash
SINGLE_TS=$(date +%Y%m%d_%H%M%S)
SINGLE_EXPORT_DIR="reports/exports/single_$SINGLE_TS"
SINGLE_WORKBOOK="$SINGLE_EXPORT_DIR/ippcp_evidence_summary_${SINGLE_TS}.xlsx"
SINGLE_ZIP="$SINGLE_EXPORT_DIR/ippcp_evidence_package_${SINGLE_TS}.zip"
SINGLE_TESTS="T3=$INGESTION_SUFFIX"

python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "$SINGLE_TESTS" \
  --timestamp "$SINGLE_TS" \
  --export-dir "$SINGLE_EXPORT_DIR" \
  --strict

python3 tools/package_evidence_bundle.py \
  --config tools/evidence_export.tests.yaml \
  --tests "$SINGLE_TESTS" \
  --timestamp "$SINGLE_TS" \
  --export-dir "$SINGLE_EXPORT_DIR" \
  --strict
```

`--tests "T3=$INGESTION_SUFFIX"` is already exact. Golden Path SINGLE does not need `--only-tests`.

Inspect publication status:

```bash
unzip -p "$SINGLE_ZIP" \
  ippcp_evidence_package/package_status.json \
  | jq '{publication_ready, publication_blockers}'

unzip -p "$SINGLE_ZIP" \
  ippcp_evidence_package/slot_inventory.json \
  | jq .
```

A current SINGLE ingestion-only package may be `publication_ready=true`. Manual review is still required before any external sharing.

**STOP if:** `publication_ready=false` and the artifact is intended for external sharing.

### `publication_ready`

Each classified asset has `publication_profile` and `publication_safe`.

- `minimal_publication` → `publication_safe=true` (current Ingestion API v2 profile).
- `standard` → `publication_safe=false` (current WFS, SPARQL, and legacy CSV/B2 profile).

```text
package.publication_ready = all included slots are publication_safe
```

### Two-slot example (arbitrary order)

```bash
TS=$(date +%Y%m%d_%H%M%S)
EXPORT_DIR="reports/exports/two_slot_$TS"
TESTS="T3=$SPARQL_SUFFIX,T1=$WFS_CITY_SUFFIX"

python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "$TESTS" \
  --timestamp "$TS" \
  --export-dir "$EXPORT_DIR" \
  --strict
```

### Preset export and packaging

```bash
TS=$(date +%Y%m%d_%H%M%S)
EXPORT_DIR="reports/exports/legacy_$TS"

python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --preset legacy_assessment \
  --timestamp "$TS" \
  --export-dir "$EXPORT_DIR" \
  --strict

WORKBOOK="$EXPORT_DIR/ippcp_evidence_summary_${TS}.xlsx"
python3 tools/package_evidence_bundle.py \
  --config tools/evidence_export.tests.yaml \
  --preset legacy_assessment \
  --excel "$WORKBOOK" \
  --timestamp "$TS" \
  --export-dir "$EXPORT_DIR" \
  --strict
```

### Dry-run package planning

```bash
python3 tools/package_evidence_bundle.py \
  --config tools/evidence_export.tests.yaml \
  --tests "$COMPLETE_TESTS" \
  --excel "$COMPLETE_WORKBOOK" \
  --dry-run \
  --verbose
```

### Common CLI flags

Exporter (`export_evidence_to_excel.py`):

```text
--config --tests --preset --only-tests --repo-root --evidence-dir --downloads-dir
--output --export-dir --timestamp --timestamp-suffix --strict --profile
--sanitize-connectors / --no-sanitize-connectors
--redact-local-paths / --no-redact-local-paths --verbose --help
```

Packager (`package_evidence_bundle.py`):

```text
--config --tests --preset --only-tests --excel --output --export-dir --timestamp
--timestamp-suffix --repo-root --profile --include-downloaded-assets
--sanitize-connectors / --no-sanitize-connectors
--redact-local-paths / --no-redact-local-paths --strict --dry-run --verbose --help
```

Example with explicit paths and output:

```bash
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "T1=$INGESTION_SUFFIX" \
  --repo-root "$(pwd)" \
  --evidence-dir evidencias/runs \
  --downloads-dir downloads \
  --output reports/exports/manual_ingestion.xlsx \
  --strict
```

Inspect ZIP contents:

```bash
unzip -l "$COMPLETE_ZIP"
unzip -l "$COMPLETE_ZIP" | rg -i 'secret|sensitive|phase[0-9]_env|request|response|token|credential' || true
```

Run tool unit tests from repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  tools.tests.test_evidence_export \
  tools.tests.test_dataspace_resolution \
  tools.tests.test_ingesta_api_post_support \
  -v
```

CLI help:

```bash
python3 tools/export_evidence_to_excel.py --help
python3 tools/package_evidence_bundle.py --help
```

## 17. Stop conditions

STOP if:

- Phase 0 fails;
- the expected `phase*_env.sh` file is missing;
- credentials are missing or still set to placeholders;
- `git check-ignore` does not list every local secret listed in [section 5](#5-verify-secrets-are-ignored-by-git);
- semantic validation fails;
- run phases are not all `ok`;
- `publication_ready=false` and the artifact is intended for external sharing;
- HTTP 409 occurs in Phase 1 (start a new run instead of mutating the asset);
- SPARQL returns XML;
- WFS JSON is not a `FeatureCollection`;
- PROD POST phase 4 is run without `INGESTA_API_REQUEST_BODY_FILE` or with the wrong company's body;
- CIRCE phase 4 is attempted with an Industrias Ebro payload;
- you are about to print passwords, API keys, JWTs, EDR authorization, or POST request bodies.

## 18. Security

Never place in repository documentation, commits, screenshots, recordings, or public packages:

- real passwords;
- real API keys;
- JWT / Bearer tokens;
- EDR authorization;
- actual `user_*.sh` contents;
- actual `ingesta_api_key.env`;
- current real `SUFFIX` values;
- personal local paths;
- sensitive payloads.

Before recording a demo: `set +x`, keep the terminal clean, and do not open `user_*.sh`, `ingesta_api_key*.env`, `INGESTA_API_REQUEST_BODY_FILE` contents, or `phase*_env.sh` on screen.

Provider EdD credentials authenticate connectors. The Ingestion API key protects a different hop and must not be shared with the consumer.

## 19. Reference documentation

This workshop is the executable path. The following documents are detailed reference:

- [Getting started](getting-started.md)
- [Execution phases](execution-phases.md)
- [Ingestion API](flows/ingestion-api.md)
- [WFS](flows/wfs.md)
- [SPARQL](flows/sparql.md)
- [Evidence and traceability](evidence-and-traceability.md)
- [Evidence publication](evidence-publication.md)
- [Troubleshooting](troubleshooting.md)
- [Authentication](authentication.md)
- [Architecture](architecture.md)
- [tools/tools_README.md](../tools/tools_README.md)
- [tools/evidence_tooling.md](../tools/evidence_tooling.md)

## 20. Legacy / reference material

Current Golden Path:

- `v2`
- `HttpData-PULL`
- `phase0` → `phase4`

Historical / reference only. Do not mix into this workshop:

- CSV / B2 / InesDataStore
- `v1`
- `test3`
- `phase1b_provider_upload_file.sh`
- `phase3b_inesdata_transfer.sh`
- `phase4b_consumer_storage_fetch.sh`

Those paths remain in the repository for reproducibility. They are not the recommended route for new tests or the current demo.
