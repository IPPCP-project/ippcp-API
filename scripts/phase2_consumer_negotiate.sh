#!/usr/bin/env bash
# phase2_consumer_negotiate.sh — Fase 2: consumer negocia contrato (test3).
#
# Requisitos: Bash 4.3+, curl, jq (ver scripts/scripts_README.md).
#
# Prerrequisito: phase1 OK (phase1_env.sh o SUFFIX+ASSET_ID exportados).
# Relanzar con agreement previo en la misma ejecución: PHASE2_FORCE=1
#
# Uso:
#   /opt/homebrew/bin/bash scripts/phase2_consumer_negotiate.sh

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "${_SCRIPT_DIR}/lib_common.sh"

readonly REQUEST_LIST_BODY='{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"offset":0,"limit":50,"filterExpression":[]}'

PHASE2_STEP="init"

_phase2_on_err() {
  local rc=$?
  if [[ -n "${RUN_DIR:-}" && -d "${RUN_DIR}" ]]; then
    lib_write_summary 2 "${PHASE2_STEP}" fail "{\"exit_code\":${rc}}" 2>/dev/null || true
    lib_set_phase_status 2 fail 2>/dev/null || true
  fi
  exit "${rc}"
}
trap _phase2_on_err ERR

_phase2_write_json() {
  local dest="$1"
  local tmp="${dest}.$$"
  cat > "${tmp}"
  mv "${tmp}" "${dest}"
}

_phase2_read_env_field() {
  local env_file="$1"
  local field="$2"
  local line value

  [[ -f "${env_file}" ]] || return 1
  line="$(grep -E "^export ${field}=" "${env_file}" 2>/dev/null | head -1 || true)"
  [[ -n "${line}" ]] || return 1
  value="${line#export ${field}=}"
  value="${value#\'}"; value="${value%\'}"
  value="${value#\"}"; value="${value%\"}"
  printf '%s' "${value}"
}

_phase2_agreement_is_set() {
  local value="${1:-}"
  [[ -n "${value}" && "${value}" != "null" ]]
}

# jq defs compartidas para validación/selección de offer policy
readonly _PHASE2_JQ_OFFER_DEFS='
  def action_value:
    . as $a
    | if $a == null then ""
      elif ($a | type) == "object" then
        ($a."@id" // $a.id // $a.type // $a."@value" // ($a | tostring))
      else ($a | tostring)
      end;

  def last_fragment_is_use:
    . as $s
    | ($s | ascii_downcase | split("#") | last | split("/") | last | split(":") | last) == "use";

  def is_use_action:
    action_value | last_fragment_is_use;

  def policy_permissions:
    (.permission // ."odrl:permission" // ."http://www.w3.org/ns/odrl/2/permission" // [])
    | if type == "array" then . else [.] end;

  def policy_obligations:
    (.obligation // ."odrl:obligation" // ."http://www.w3.org/ns/odrl/2/obligation" // [])
    | if type == "array" then . else [.] end;

  def policy_prohibitions:
    (.prohibition // ."odrl:prohibition" // ."http://www.w3.org/ns/odrl/2/prohibition" // [])
    | if type == "array" then . else [.] end;

  def collection_len:
    if type == "array" then length else (if . == null then 0 else 1 end) end;

  def permission_action($perm):
    ($perm.action // $perm."odrl:action" // $perm."http://www.w3.org/ns/odrl/2/action" // null);

  def offer_is_valid:
    (policy_permissions | any(permission_action(.) | is_use_action))
    and ((policy_obligations | collection_len) == 0)
    and ((policy_prohibitions | collection_len) == 0);
'

_phase2_extract_catalog_dataset() {
  local catalog_file="$1"
  local output_file="$2"
  local tmp="${output_file}.$$"

  jq -e --arg id "${ASSET_ID}" '
    (."dcat:dataset" // ."http://www.w3.org/ns/dcat#dataset")
    | (if type == "array" then . else [.] end)
    | map(select(."@id" == $id))
    | .[0] // empty
  ' "${catalog_file}" > "${tmp}"

  if [[ ! -s "${tmp}" ]] || ! jq -e . "${tmp}" >/dev/null 2>&1; then
    rm -f "${tmp}"
    lib_die "ASSET_ID ${ASSET_ID} no aparece en catálogo remoto del provider"
  fi

  mv "${tmp}" "${output_file}"
}

_phase2_extract_offer_policy() {
  local dataset_file="$1"
  local output_file="$2"
  local tmp="${output_file}.$$"

  jq -e "${_PHASE2_JQ_OFFER_DEFS}"'
    (
      .hasPolicy
      // ."odrl:hasPolicy"
      // ."http://www.w3.org/ns/odrl/2/hasPolicy"
    )
    | (if type == "array" then . else [.] end)
    | map(select(offer_is_valid))
    | .[0] // empty
  ' "${dataset_file}" > "${tmp}"

  if [[ ! -s "${tmp}" ]] || ! jq -e . "${tmp}" >/dev/null 2>&1; then
    rm -f "${tmp}"
    lib_die "No se encontró offer policy válida (USE, sin obligation/prohibition) en el dataset ${ASSET_ID}"
  fi

  mv "${tmp}" "${output_file}"
}

_phase2_validate_offer_policy() {
  local offer_file="$1"

  jq -e "${_PHASE2_JQ_OFFER_DEFS}"' offer_is_valid ' "${offer_file}" >/dev/null \
    || lib_die "Offer policy inválida en ${offer_file}: requiere permission/action USE, obligation [] y prohibition []"
}

_phase2_extract_participant_id() {
  local catalog_file="$1"
  jq -r '
    ."dspace:participantId"
    // .participantId
    // ."edc:participantId"
    // ."http://www.w3.org/ns/dspace/participantId"
    // empty
  ' "${catalog_file}"
}

_phase2_negotiation_state() {
  jq -r '.state // ."edc:state" // empty'
}

_phase2_agreement_id() {
  jq -r '
    .contractAgreementId // ."edc:contractAgreementId"
    | if type == "object" then (."@id" // .id // empty) else . end
  '
}

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

PHASE2_STEP="init"
api_find_root

if [[ -z "${SUFFIX:-}" || -z "${ASSET_ID:-}" ]]; then
  if [[ ! -f "$(lib_phase_env_path 1)" ]]; then
    lib_die "Ejecuta primero phase1_provider_publish.sh"
  fi
  # shellcheck source=/dev/null
  source "$(lib_phase_env_path 1)"
fi

if [[ "${PHASE2_FORCE:-}" != "1" && -f "$(lib_phase_env_path 2)" ]]; then
  _existing_agreement="$(_phase2_read_env_field "$(lib_phase_env_path 2)" AGREEMENT_ID || true)"
  _existing_suffix="$(_phase2_read_env_field "$(lib_phase_env_path 2)" SUFFIX || true)"
  if _phase2_agreement_is_set "${_existing_agreement}" \
    && [[ -n "${_existing_suffix}" && "${_existing_suffix}" == "${SUFFIX}" ]]; then
    lib_die "phase2_env.sh ya contiene AGREEMENT_ID para SUFFIX=${SUFFIX}. Export PHASE2_FORCE=1 para relanzar."
  fi
fi

lib_load_env
[[ -n "${ENDPOINTS[contractAgreement]:-}" ]] \
  || lib_die "ENDPOINTS[contractAgreement] no definido tras cargar endpoints.sh"

lib_require_cmds
lib_require_vars_group LIB_VARS_DATASPACE
lib_require_vars_group LIB_VARS_PROVIDER
lib_require_vars_group LIB_VARS_CONSUMER
lib_derive_phase1_ids
lib_require_vars_group LIB_VARS_PHASE1
lib_init_run_dirs
lib_init_summary

# ---------------------------------------------------------------------------
# JWT consumer
# ---------------------------------------------------------------------------

PHASE2_STEP="jwt_renew"
lib_renew_jwt consumer
lib_jwt_check_console consumer

PHASE2_STEP="jwt_claims"
lib_jwt_claims_to_json consumer "${PHASE2_DIR}/jwt_claims_consumer.json"
lib_write_summary 2 jwt_consumer ok '{"artifact":"phase2/jwt_claims_consumer.json"}'

# ---------------------------------------------------------------------------
# Contexto
# ---------------------------------------------------------------------------

PHASE2_STEP="write_context"
context_file="${PHASE2_DIR}/00_context.txt"
context_tmp="${context_file}.$$"
{
  printf 'Fecha: %s\n' "$(date)"
  printf 'API_ROOT=%s\n' "${API_ROOT}"
  printf 'SUFFIX=%s\n' "${SUFFIX}"
  printf 'RUN_DIR=%s\n' "${RUN_DIR}"
  printf 'DS_NAME=%s\n' "${DS_NAME}"
  printf 'PROVIDER=%s\n' "${PROVIDER}"
  printf 'PROVIDER_PROTOCOL=%s\n' "${PROVIDER_PROTOCOL}"
  printf 'CONSUMER=%s\n' "${CONSUMER}"
  printf 'CONSUMER_BASE=%s\n' "${CONSUMER_BASE}"
  printf 'ASSET_ID=%s\n' "${ASSET_ID}"
  printf 'CD_ID=%s\n' "${CD_ID}"
  [[ -n "${ASSET_SLUG:-}" ]] && printf 'ASSET_SLUG=%s\n' "${ASSET_SLUG}"
  [[ -n "${ASSET_NAME:-}" ]] && printf 'ASSET_NAME=%s\n' "${ASSET_NAME}"
  [[ -n "${ASSET_BASE_URL:-}" ]] && printf 'ASSET_BASE_URL=%s\n' "${ASSET_BASE_URL}"
  [[ -n "${ASSET_CONTENT_KIND:-}" ]] && printf 'ASSET_CONTENT_KIND=%s\n' "${ASSET_CONTENT_KIND}"
  [[ -n "${ASSET_EXTENSION:-}" ]] && printf 'ASSET_EXTENSION=%s\n' "${ASSET_EXTENSION}"
} > "${context_tmp}"
mv "${context_tmp}" "${context_file}"

# ---------------------------------------------------------------------------
# A. Catálogo remoto
# ---------------------------------------------------------------------------

PHASE2_STEP="remote_catalog"
catalog_body="${PHASE2_DIR}/10_remote_catalog_request_body.json"
_phase2_write_json "${catalog_body}" <<EOF
{
  "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
  "@type": "CatalogRequest",
  "counterPartyAddress": "${PROVIDER_PROTOCOL}",
  "counterPartyId": "${PROVIDER}",
  "protocol": "dataspace-protocol-http",
  "querySpec": {
    "offset": 0,
    "limit": 100,
    "filterExpression": [
      {
        "operandLeft": "https://w3id.org/edc/v0.0.1/ns/id",
        "operator": "=",
        "operandRight": "${ASSET_ID}"
      }
    ]
  }
}
EOF

lib_curl_json "${PHASE2_DIR}/10_remote_catalog_request" \
  -X POST "${CONSUMER_BASE}/management/v3/catalog/request" \
  -H "Authorization: Bearer ${CONSUMER_JWT}" \
  -H "Content-Type: application/json" \
  -d "@${catalog_body}"

catalog_http="$(tr -d '\n' < "${PHASE2_DIR}/10_remote_catalog_request.http")"
lib_write_summary 2 remote_catalog ok \
  "{\"http\":${catalog_http},\"artifact\":\"phase2/10_remote_catalog_request\"}"

# ---------------------------------------------------------------------------
# B. Selección dataset + offer
# ---------------------------------------------------------------------------

PHASE2_STEP="catalog_asset_found"
selected_dataset="${PHASE2_DIR}/selected_remote_catalog_dataset.json"
selected_offer="${PHASE2_DIR}/selected_remote_offer_policy.json"

_phase2_extract_catalog_dataset \
  "${PHASE2_DIR}/10_remote_catalog_request.json" \
  "${selected_dataset}"

_phase2_extract_offer_policy "${selected_dataset}" "${selected_offer}"
_phase2_validate_offer_policy "${selected_offer}"

lib_write_summary 2 catalog_asset_found ok \
  "{\"asset_id\":\"${ASSET_ID}\",\"artifact\":\"phase2/selected_remote_catalog_dataset.json\"}"

PHASE2_STEP="offer_policy_valid"
lib_write_summary 2 offer_policy_valid ok \
  "{\"artifact\":\"phase2/selected_remote_offer_policy.json\"}"

CATALOG_ASSET_ID="$(jq -r '."@id" // empty' "${selected_dataset}")"
OFFER_POLICY_ID="$(jq -r '."@id" // empty' "${selected_offer}")"
PROVIDER_PARTICIPANT_ID="$(_phase2_extract_participant_id "${PHASE2_DIR}/10_remote_catalog_request.json")"
PARTICIPANT_SOURCE="catalog"

if [[ -z "${PROVIDER_PARTICIPANT_ID}" ]]; then
  PROVIDER_PARTICIPANT_ID="${PROVIDER}"
  PARTICIPANT_SOURCE="fallback_PROVIDER"
  lib_log WARN "participantId no encontrado en catálogo; usando PROVIDER=${PROVIDER}"
fi

[[ "${CATALOG_ASSET_ID}" == "${ASSET_ID}" ]] \
  || lib_die "CATALOG_ASSET_ID (${CATALOG_ASSET_ID}) != ASSET_ID (${ASSET_ID})"
[[ -n "${OFFER_POLICY_ID}" ]] || lib_die "OFFER_POLICY_ID vacío tras extraer offer policy"
[[ -n "${PROVIDER_PARTICIPANT_ID}" ]] || lib_die "PROVIDER_PARTICIPANT_ID vacío"

PHASE2_STEP="selected_ids"
selected_ids_file="${PHASE2_DIR}/20_selected_ids.json"
jq -n \
  --arg suffix "${SUFFIX}" \
  --arg asset_id "${ASSET_ID}" \
  --arg catalog_asset_id "${CATALOG_ASSET_ID}" \
  --arg offer_policy_id "${OFFER_POLICY_ID}" \
  --arg provider_participant_id "${PROVIDER_PARTICIPANT_ID}" \
  --arg participant_source "${PARTICIPANT_SOURCE}" \
  '{
    SUFFIX: $suffix,
    ASSET_ID: $asset_id,
    CATALOG_ASSET_ID: $catalog_asset_id,
    OFFER_POLICY_ID: $offer_policy_id,
    PROVIDER_PARTICIPANT_ID: $provider_participant_id,
    PROVIDER_PARTICIPANT_ID_source: $participant_source
  }' > "${selected_ids_file}"

lib_write_summary 2 selected_ids ok \
  "$(jq -c \
    --arg ps "${PARTICIPANT_SOURCE}" \
    '{offer_policy_id: .OFFER_POLICY_ID, provider_participant_id: .PROVIDER_PARTICIPANT_ID, participant_source: $ps}' \
    "${selected_ids_file}")"

export PROVIDER_PARTICIPANT_ID OFFER_POLICY_ID CATALOG_ASSET_ID

# ---------------------------------------------------------------------------
# C. Negociación contractual
# ---------------------------------------------------------------------------

PHASE2_STEP="contract_negotiation_started"
neg_request="${PHASE2_DIR}/30_contract_negotiation_request.json"
_phase2_write_json "${neg_request}" <<EOF
{
  "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
  "@type": "ContractRequest",
  "counterPartyAddress": "${PROVIDER_PROTOCOL}",
  "counterPartyId": "${PROVIDER_PARTICIPANT_ID}",
  "protocol": "dataspace-protocol-http",
  "policy": {
    "@context": "http://www.w3.org/ns/odrl.jsonld",
    "@type": "Offer",
    "@id": "${OFFER_POLICY_ID}",
    "assigner": "${PROVIDER_PARTICIPANT_ID}",
    "target": "${CATALOG_ASSET_ID}",
    "permission": [ { "action": "USE" } ],
    "prohibition": [],
    "obligation": []
  }
}
EOF

lib_curl_json "${PHASE2_DIR}/30_contract_negotiation_response" \
  -X POST "${CONSUMER_BASE}/management/v3/contractnegotiations" \
  -H "Authorization: Bearer ${CONSUMER_JWT}" \
  -H "Content-Type: application/json" \
  -d "@${neg_request}"

NEG_ID="$(jq -r '."@id" // empty' "${PHASE2_DIR}/30_contract_negotiation_response.json")"
[[ -n "${NEG_ID}" ]] || lib_die "NEG_ID vacío tras iniciar negociación"

neg_http="$(tr -d '\n' < "${PHASE2_DIR}/30_contract_negotiation_response.http")"
lib_write_summary 2 contract_negotiation_started ok \
  "{\"http\":${neg_http},\"neg_id\":\"${NEG_ID}\",\"artifact\":\"phase2/30_contract_negotiation_response\"}"

export NEG_ID

# ---------------------------------------------------------------------------
# D. Polling negociación
# ---------------------------------------------------------------------------

PHASE2_STEP="negotiation_finalized"
AGREEMENT_ID=""
FINAL_STATE=""
last_poll_base=""

for i in $(seq 1 20); do
  poll_n="$(printf '%02d' "${i}")"
  poll_base="${PHASE2_DIR}/31_negotiation_state_${poll_n}"
  last_poll_base="${poll_base}"

  lib_curl_json "${poll_base}" \
    -X GET "${CONSUMER_BASE}/management/v3/contractnegotiations/${NEG_ID}" \
    -H "Authorization: Bearer ${CONSUMER_JWT}"

  STATE="$(_phase2_negotiation_state < "${poll_base}.json")"
  STATE="${STATE^^}"
  AGREEMENT_ID="$(_phase2_agreement_id < "${poll_base}.json")"

  lib_log INFO "[${i}] state=${STATE:-<none>} agreement=${AGREEMENT_ID:-<none>}"

  if _phase2_agreement_is_set "${AGREEMENT_ID}"; then
    FINAL_STATE="${STATE}"
    break
  fi

  if [[ "${STATE}" == "TERMINATED" ]]; then
    lib_die "Negociación TERMINATED (revisar phase2/31_negotiation_state_${poll_n}.json; causas: policy mismatch, NOTIFY residual, JWT caducado)"
  fi

  sleep 3
done

if ! _phase2_agreement_is_set "${AGREEMENT_ID}"; then
  lib_die "Timeout: no contractAgreementId tras 20 intentos (último estado: ${STATE:-desconocido})"
fi

cp "${last_poll_base}.json" "${PHASE2_DIR}/32_negotiation_final_state.json"
cp "${last_poll_base}.http" "${PHASE2_DIR}/32_negotiation_final_state.http"

lib_write_summary 2 negotiation_finalized ok \
  "{\"neg_id\":\"${NEG_ID}\",\"agreement_id\":\"${AGREEMENT_ID}\",\"final_state\":\"${FINAL_STATE}\",\"artifact\":\"phase2/32_negotiation_final_state\"}"

export AGREEMENT_ID

# ---------------------------------------------------------------------------
# E. Verificación agreement
# ---------------------------------------------------------------------------

PHASE2_STEP="get_contract_agreement"
lib_curl_json "${PHASE2_DIR}/40_get_contract_agreement" \
  -X GET "${CONSUMER_BASE}/management/v3/contractagreements/${AGREEMENT_ID}" \
  -H "Authorization: Bearer ${CONSUMER_JWT}"

get_agreement_http="$(tr -d '\n' < "${PHASE2_DIR}/40_get_contract_agreement.http")"
lib_write_summary 2 get_contract_agreement ok \
  "{\"http\":${get_agreement_http},\"agreement_id\":\"${AGREEMENT_ID}\",\"artifact\":\"phase2/40_get_contract_agreement\"}"

PHASE2_STEP="list_contract_agreements"
lib_curl_json "${PHASE2_DIR}/41_list_contract_agreements" \
  -X POST "${CONSUMER_BASE}${ENDPOINTS[contractAgreement]}" \
  -H "Authorization: Bearer ${CONSUMER_JWT}" \
  -H "Content-Type: application/json" \
  -d "${REQUEST_LIST_BODY}"

list_agreements_http="$(tr -d '\n' < "${PHASE2_DIR}/41_list_contract_agreements.http")"
list_agreements_count="$(jq 'length' "${PHASE2_DIR}/41_list_contract_agreements.json")"
lib_write_summary 2 list_contract_agreements ok \
  "{\"http\":${list_agreements_http},\"count\":${list_agreements_count},\"artifact\":\"phase2/41_list_contract_agreements\"}"

# ---------------------------------------------------------------------------
# Cierre
# ---------------------------------------------------------------------------

PHASE2_STEP="export_env"
lib_export_phase_env 2
lib_set_phase_status 2 ok

trap - ERR
lib_log INFO "Fase 2 OK — SUFFIX=${SUFFIX} AGREEMENT_ID=${AGREEMENT_ID}"
