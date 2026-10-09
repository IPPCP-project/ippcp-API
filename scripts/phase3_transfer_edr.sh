#!/usr/bin/env bash
# phase3_transfer_edr.sh — Fase 3: transfer HttpData-PULL y obtención de EDR.
#
# Requisitos: Bash 4.3+, curl, jq (ver scripts/scripts_README.md).
#
# Variables mínimas Fase 3 (export): SUFFIX, ASSET_ID, AGREEMENT_ID, TRANSFER_ID, EDR_URL
# lib_export_phase_env 3 también persiste IDs heredados de fases anteriores.
#
# Prerrequisito: phase2 OK (phase2_env.sh o SUFFIX+ASSET_ID+AGREEMENT_ID exportados).
# Relanzar con transfer previo en la misma ejecución: PHASE3_FORCE=1
# Continuar ejecución fallida (sin crear transfer nuevo): PHASE3_RESUME=1
# Compat legacy: PHASE3_TRY_DATA_CONSUMPTION=1 intenta consumir datos en phase3.
#
# Uso:
#   source runtime/env/latest/phase2_env.sh
#   /opt/homebrew/bin/bash scripts/phase3_transfer_edr.sh
#
# Continuar tras fallo en EDR:
#   PHASE3_RESUME=1 /opt/homebrew/bin/bash scripts/phase3_transfer_edr.sh

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "${_SCRIPT_DIR}/lib_common.sh"

PHASE3_STEP="init"
PHASE3_EDR_TMP_DIR=""
PHASE3_EDR_RAW_FILE=""
PHASE3_EDR_HTTP=""
PHASE3_EDR_SOURCE=""
PHASE3_EDR_AUTHORIZATION=""
PHASE3_EDR_AUTH_CODE=""
PHASE3_EDR_AUTH_KEY=""
PHASE3_EDR_AUTH_TYPE=""
PHASE3_AUTH_CANDIDATE_LABEL=""
FINAL_STATE=""
STATE=""

declare -a EDR_AUTH_CURL_ARGS=()
declare -a PHASE3_AUTH_CANDIDATE_LABELS=()
declare -a PHASE3_AUTH_CANDIDATE_HEADERS=()

_phase3_cleanup() {
  if [[ -n "${PHASE3_EDR_TMP_DIR}" && -d "${PHASE3_EDR_TMP_DIR}" ]]; then
    rm -rf "${PHASE3_EDR_TMP_DIR}"
    PHASE3_EDR_TMP_DIR=""
  fi
}

_phase3_on_err() {
  local rc=$?
  _phase3_cleanup
  if [[ -n "${RUN_DIR:-}" && -d "${RUN_DIR}" ]]; then
    lib_write_summary 3 "${PHASE3_STEP}" fail "{\"exit_code\":${rc}}" 2>/dev/null || true
    lib_set_phase_status 3 fail 2>/dev/null || true
  fi
  exit "${rc}"
}
trap _phase3_on_err ERR

_phase3_write_json() {
  local dest="$1"
  local tmp="${dest}.$$"
  cat > "${tmp}"
  mv "${tmp}" "${dest}"
}

_phase3_read_env_field() {
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

_phase3_id_is_set() {
  local value="${1:-}"
  [[ -n "${value}" && "${value}" != "null" ]]
}

_phase3_edr_url_has_sensitive_params() {
  local value="${1:-}"
  [[ -n "${value}" && "${value}" != "null" ]]
}

_phase3_safe_summary_edr_url() {
  lib_diagnostic_edr_endpoint "${EDR_URL:-}"
}

# Ejecuta un bloque jq definido como readonly en este script sin expansión bash de $variables jq.
_phase3_jq_from_block() {
  local start_marker="$1"
  local jq_prog jq_prog_tmp
  shift

  jq_prog_tmp="$(mktemp "${TMPDIR:-/tmp}/phase3_jq_prog.XXXXXX")"
  awk -v start="${start_marker}" -v q="'" '
    $0 ~ ("^readonly " start) { capture=1; next }
    capture && $0 == q { capture=0; next }
    capture { print }
  ' "${_SCRIPT_DIR}/phase3_transfer_edr.sh" > "${jq_prog_tmp}"

  jq -f "${jq_prog_tmp}" "$@"
  local rc=$?
  rm -f "${jq_prog_tmp}"
  return "${rc}"
}

readonly _PHASE3_JQ_HAS_HTTPDATA_PULL='
  def distributions:
    (.["dcat:distribution"] // .["http://www.w3.org/ns/dcat#distribution"] // [])
    | if type == "array" then . else if . == null then [] else [.] end end;

  def format_id($dist):
    ($dist["dct:format"] // $dist["http://purl.org/dc/terms/format"] // null)
    | if . == null then ""
      elif type == "object" then (."@id" // .id // empty)
      else (. | tostring)
      end;

  distributions
  | any(format_id(.) == "HttpData-PULL")
'

_phase3_validate_httpdata_pull() {
  local dataset_file="$1"

  [[ -f "${dataset_file}" ]] \
    || lib_die "Dataset remoto de Fase 2 no encontrado: ${dataset_file} (¿ejecutaste phase2?)"

  _phase3_jq_from_block "_PHASE3_JQ_HAS_HTTPDATA_PULL=" -e "${dataset_file}" >/dev/null \
    || lib_die "El asset ${ASSET_ID} no anuncia distribución HttpData-PULL; no se puede ejecutar esta Fase 3."
}

_phase3_transfer_state() {
  jq -r '.state // ."edc:state" // empty'
}

_phase3_transfer_id_from_json() {
  jq -r '."@id" // .id // empty'
}

_phase3_state_acceptable() {
  local state="${1:-}"
  [[ "${state}" == "STARTED" || "${state}" == "COMPLETED" ]]
}

_phase3_state_pollable() {
  local state="${1:-}"
  [[ "${state}" == "INITIAL" || "${state}" == "REQUESTED" ]]
}

_phase3_state_failed() {
  local state="${1:-}"
  [[ "${state}" == "TERMINATED" || "${state}" == "ERROR" ]]
}

readonly _PHASE3_JQ_EXTRACT_EDR_URL='
  .endpoint // .endpointUrl // ."edc:endpoint" // empty
'

readonly _PHASE3_JQ_EXTRACT_EDR_AUTH='
  def as_string:
    if . == null or . == "" then empty
    elif type == "string" then .
    elif type == "object" then
      (."@value" // .value // .token // .authorization // empty) | as_string
    else empty
    end;

  def key_is_authtype($k):
    ($k | ascii_downcase) == "authtype";

  def key_matches_authorization_token($k):
    key_is_authtype($k) | not
    and (
      ($k | ascii_downcase | test("authorization"))
      or (($k | ascii_downcase) == "token")
      or ($k | ascii_downcase | test("accesstoken"))
      or ($k | ascii_downcase | test("access_token"))
      or ($k | ascii_downcase | test("bearertoken"))
      or ($k | ascii_downcase | test("bearer_token"))
    );

  def key_matches_auth_code($k):
    key_is_authtype($k) | not
    and (
      ($k | ascii_downcase | test("authcode"))
      or ($k | ascii_downcase | test("auth_code"))
      or (($k | ascii_downcase) == "code")
    );

  def key_matches_auth_key($k):
    key_is_authtype($k) | not
    and (
      ($k | ascii_downcase | test("authkey"))
      or ($k | ascii_downcase | test("auth_key"))
      or (($k | ascii_downcase) == "header")
    );

  def find_authorization_recursive:
    [
      .. | objects | to_entries[]
      | select(key_matches_authorization_token(.key))
      | .value | as_string
      | select(. != "")
    ] | first // empty;

  def find_auth_code_recursive:
    [
      .. | objects | to_entries[]
      | select(key_matches_auth_code(.key))
      | .value | as_string
      | select(. != "")
    ] | first // empty;

  def find_auth_key_recursive:
    [
      .. | objects | to_entries[]
      | select(key_matches_auth_key(.key))
      | .value | as_string
      | select(. != "")
    ] | first // empty;

  def direct_authorization:
    (
      .authorization // .Authorization
      // ."edc:authorization"
      // ."https://w3id.org/edc/v0.0.1/ns/authorization"
      // .auth // .token // .accessToken // .access_token
      // .bearerToken // .bearer_token // .credential
      // (.credentials.authorization // .credentials.auth // empty)
      // (.properties.authorization // .properties.auth // .properties.token
         // .properties.accessToken // .properties.access_token // empty)
    ) | as_string;

  def direct_auth_code:
    (
      .authCode // ."edc:authCode"
      // ."https://w3id.org/edc/v0.0.1/ns/authCode"
      // .auth_code // .code
      // (.properties.authCode // .properties.auth_code // .properties.code // empty)
    ) | as_string;

  def direct_auth_key:
    (
      .authKey // ."edc:authKey"
      // ."https://w3id.org/edc/v0.0.1/ns/authKey"
      // .auth_key // .key // .header
      // (.properties.authKey // .properties.auth_key // .properties.key
         // .properties.header // empty)
    ) | as_string;

  {
    authorization: (
      direct_authorization // find_authorization_recursive // ""
    ),
    authCode: (
      direct_auth_code // find_auth_code_recursive // ""
    ),
    authKey: (
      direct_auth_key // find_auth_key_recursive // ""
    ),
    authType: (
      (.authType // ."edc:authType" // ."https://w3id.org/edc/v0.0.1/ns/authType" // "")
      | if type == "string" then . else "" end
    )
  }
'

readonly _PHASE3_JQ_EDR_KEYS_DIAGNOSTIC='
  def path_label($p):
    $p
    | map(if type == "number" then "[\(. | tostring)]" else . end)
    | join(".");

  def key_sensitive($k):
    ($k | ascii_downcase) as $kl
    | ($kl | test("auth"))
    or ($kl | test("token"))
    or ($kl | test("secret"))
    or ($kl | test("code"))
    or ($kl | test("key"))
    or ($kl | test("credential"));

  {
    top_level_keys: (if type == "object" then (keys | sort) else [] end),
    sensitive_key_paths: (
      [
        paths(scalars) as $p
        | ($p[-1] | tostring) as $k
        | select(key_sensitive($k))
        | path_label($p)
      ]
      | unique
      | sort
    )
  }
'

readonly _PHASE3_JQ_REDACT_EDR='
  def key_is_endpoint($k):
    ($k | ascii_downcase) as $kl
    | $kl == "endpoint" or $kl == "endpointurl" or $kl == "edc:endpoint"
      or ($kl | test("(^|[/:])endpoint$"));

  def key_should_redact($k):
    ($k | ascii_downcase | test("token"))
    or ($k | ascii_downcase | test("secret"))
    or ($k | ascii_downcase | test("authorization"))
    or ($k | ascii_downcase | test("auth"))
    or ($k | ascii_downcase | test("code"));

  def redact:
    if type == "object" then
      with_entries(
        if key_is_endpoint(.key) then
          .value = "<redacted-edr-endpoint>"
        elif (.key | ascii_downcase | endswith("header:x-api-key")) then
          .value = "<redacted>"
        elif key_should_redact(.key) then
          .value = "***REDACTED***"
        elif (.value | type) == "object" or (.value | type) == "array" then
          .value |= redact
        else
          .
        end
      )
    elif type == "array" then
      map(redact)
    else
      .
    end;

  redact
'

readonly _PHASE3_JQ_SELECT_EDR_ENTRY='
  def as_array:
    if type == "array" then . else if . == null then [] else [.] end end;

  def entry_transfer_id:
    .transferProcessId // ."edc:transferProcessId" // empty;

  def entry_asset_id:
    .assetId // ."edc:assetId" // empty;

  def entry_agreement_id:
    .agreementId // .contractAgreementId // ."edc:contractAgreementId"
    // ."edc:agreementId" // empty;

  def entry_data_address:
    if (.dataAddress // null) != null then .dataAddress else . end;

  . as $root
  | ($root | as_array)
  | map(select(
      (entry_transfer_id == $transfer_id)
      or (
        (entry_asset_id == $asset_id)
        and (entry_agreement_id == $agreement_id)
      )
    ))
  | .[0] // empty
  | if . == null or . == {} then empty else entry_data_address end
'

_phase3_load_edr_auth_fields() {
  local edr_raw_file="$1"
  local auth_json

  auth_json="$(_phase3_jq_from_block "_PHASE3_JQ_EXTRACT_EDR_AUTH=" -c "${edr_raw_file}")"
  PHASE3_EDR_AUTHORIZATION="$(jq -r '.authorization // empty' <<< "${auth_json}")"
  PHASE3_EDR_AUTH_CODE="$(jq -r '.authCode // empty' <<< "${auth_json}")"
  PHASE3_EDR_AUTH_KEY="$(jq -r '.authKey // empty' <<< "${auth_json}")"
  PHASE3_EDR_AUTH_TYPE="$(jq -r '.authType // empty' <<< "${auth_json}")"

  if _phase3_id_is_set "${PHASE3_EDR_AUTHORIZATION}" \
    || { _phase3_id_is_set "${PHASE3_EDR_AUTH_KEY}" && _phase3_id_is_set "${PHASE3_EDR_AUTH_CODE}"; }; then
    return 0
  fi

  lib_die "EDR DataAddress sin credenciales reconocibles. Revisar phase3/30_edr_dataaddress_redacted.json y phase3/30_edr_dataaddress_keys.json"
}

_phase3_authorization_has_bearer_prefix() {
  local value="${1:-}"
  [[ "${value}" =~ ^[Bb][Ee][Aa][Rr][Ee][Rr][[:space:]] ]]
}

_phase3_normalize_auth_type_prefix() {
  local auth_type="${1:-}"
  local lower="${auth_type,,}"
  case "${lower}" in
    bearer) printf 'Bearer' ;;
    *) printf '%s' "${auth_type}" ;;
  esac
}

_phase3_register_auth_candidate() {
  local label="$1"
  local header="$2"
  local existing

  for existing in "${PHASE3_AUTH_CANDIDATE_HEADERS[@]}"; do
    [[ "${existing}" == "${header}" ]] && return 0
  done

  PHASE3_AUTH_CANDIDATE_LABELS+=("${label}")
  PHASE3_AUTH_CANDIDATE_HEADERS+=("${header}")
}

_phase3_build_auth_candidates() {
  PHASE3_AUTH_CANDIDATE_LABELS=()
  PHASE3_AUTH_CANDIDATE_HEADERS=()

  if _phase3_id_is_set "${PHASE3_EDR_AUTH_KEY}" && _phase3_id_is_set "${PHASE3_EDR_AUTH_CODE}"; then
    _phase3_register_auth_candidate "authkey_authcode" "${PHASE3_EDR_AUTH_KEY}: ${PHASE3_EDR_AUTH_CODE}"
  fi

  if _phase3_id_is_set "${PHASE3_EDR_AUTHORIZATION}"; then
    if _phase3_authorization_has_bearer_prefix "${PHASE3_EDR_AUTHORIZATION}"; then
      _phase3_register_auth_candidate "authorization_as_is" "Authorization: ${PHASE3_EDR_AUTHORIZATION}"
    fi

    _phase3_register_auth_candidate "authorization_raw" "Authorization: ${PHASE3_EDR_AUTHORIZATION}"

    if ! _phase3_authorization_has_bearer_prefix "${PHASE3_EDR_AUTHORIZATION}"; then
      _phase3_register_auth_candidate "authorization_bearer" "Authorization: Bearer ${PHASE3_EDR_AUTHORIZATION}"

      if _phase3_id_is_set "${PHASE3_EDR_AUTH_TYPE}"; then
        _phase3_register_auth_candidate "authorization_authtype" \
          "Authorization: $(_phase3_normalize_auth_type_prefix "${PHASE3_EDR_AUTH_TYPE}") ${PHASE3_EDR_AUTHORIZATION}"
      fi
    fi
  fi

  (( ${#PHASE3_AUTH_CANDIDATE_LABELS[@]} > 0 )) \
    || lib_die "No hay candidatos de autenticación EDR tras extraer credenciales"
}

_phase3_extension_allowed() {
  case "${1}" in
    json|xml|gml|csv|txt|ttl|rdf|xlsx|zip) return 0 ;;
    *) return 1 ;;
  esac
}

_phase3_validate_content_kind_value() {
  case "${1}" in
    json|text|binary) return 0 ;;
    *)
      lib_die "ASSET_CONTENT_KIND debe ser json, text o binary (recibido: ${1})"
      ;;
  esac
}

_phase3_validate_extension_value() {
  _phase3_extension_allowed "${1}" \
    || lib_die "ASSET_EXTENSION no permitida (recibido: ${1}). Permitidas: json, xml, gml, csv, txt, ttl, rdf, xlsx, zip"
}

_phase3_validate_kind_extension_pair() {
  local content_kind="$1"
  local extension="$2"

  case "${content_kind}" in
    json)
      [[ "${extension}" == "json" ]] \
        || lib_die "ASSET_CONTENT_KIND=json requiere ASSET_EXTENSION=json (recibido: ${extension})"
      ;;
    text)
      case "${extension}" in
        xml|gml|csv|txt|ttl|rdf) return 0 ;;
        *)
          lib_die "ASSET_CONTENT_KIND=text requiere ASSET_EXTENSION xml,gml,csv,txt,ttl o rdf (recibido: ${extension})"
          ;;
      esac
      ;;
    binary)
      case "${extension}" in
        xlsx|zip) return 0 ;;
        *)
          lib_die "ASSET_CONTENT_KIND=binary requiere ASSET_EXTENSION xlsx o zip (recibido: ${extension})"
          ;;
      esac
      ;;
  esac
}

_phase3_apply_asset_content_defaults() {
  ASSET_CONTENT_KIND="${ASSET_CONTENT_KIND:-json}"
  ASSET_EXTENSION="${ASSET_EXTENSION:-json}"
  ASSET_MEDIA_TYPE="${ASSET_MEDIA_TYPE:-application/json}"

  _phase3_validate_content_kind_value "${ASSET_CONTENT_KIND}"
  _phase3_validate_extension_value "${ASSET_EXTENSION}"
  _phase3_validate_kind_extension_pair "${ASSET_CONTENT_KIND}" "${ASSET_EXTENSION}"

  export ASSET_CONTENT_KIND ASSET_EXTENSION ASSET_MEDIA_TYPE
}

_phase3_data_response_basename() {
  printf '40_data_response.%s' "${ASSET_EXTENSION}"
}

_phase3_file_bytes() {
  local file="$1"
  wc -c < "${file}" | tr -d ' '
}

_phase3_attempt_is_successful() {
  local attempt_file="$1"
  local http_code="$2"
  local curl_exit="$3"
  local bytes

  (( curl_exit == 0 )) || return 1
  [[ "${http_code}" =~ ^2[0-9]{2}$ ]] || return 1
  [[ -f "${attempt_file}" ]] || return 1

  bytes="$(_phase3_file_bytes "${attempt_file}")"
  if (( bytes == 0 )) && [[ "${ALLOW_EMPTY_DOWNLOAD:-}" != "1" ]]; then
    return 1
  fi

  if [[ "${ASSET_CONTENT_KIND}" == "json" ]]; then
    jq empty "${attempt_file}" 2>/dev/null || return 1
  fi

  return 0
}

_phase3_write_data_preview_metadata() {
  local data_file="$1"
  local preview_file="$2"
  local tmp="${preview_file}.$$"
  local bytes

  bytes="$(_phase3_file_bytes "${data_file}")"

  jq -n \
    --arg content_kind "${ASSET_CONTENT_KIND}" \
    --arg extension "${ASSET_EXTENSION}" \
    --arg media_type "${ASSET_MEDIA_TYPE}" \
    --argjson bytes "${bytes}" \
    '{
      content_kind: $content_kind,
      extension: $extension,
      media_type: $media_type,
      bytes: $bytes,
      preview_available: false
    }' > "${tmp}"

  mv "${tmp}" "${preview_file}"
}

_phase3_consume_data_with_auth_candidates() {
  local i attempt_n label header http_code curl_exit
  local base attempt_file selected=false success=0
  local summary_file="${PHASE3_DIR}/42_data_attempts_summary.json"
  local summary_tmp="${summary_file}.$$"
  local -a summary_lines=()
  local attempts_json data_bytes data_http_val
  local canonical_file="${PHASE3_DIR}/$(_phase3_data_response_basename)"

  PHASE3_DATA_RESPONSE_FILE="${canonical_file}"
  export PHASE3_DATA_RESPONSE_FILE

  _phase3_build_auth_candidates

  for i in "${!PHASE3_AUTH_CANDIDATE_LABELS[@]}"; do
    attempt_n="$(printf '%02d' "$((i + 1))")"
    label="${PHASE3_AUTH_CANDIDATE_LABELS[$i]}"
    header="${PHASE3_AUTH_CANDIDATE_HEADERS[$i]}"
    base="${PHASE3_DIR}/40_data_response_attempt_${attempt_n}"
    attempt_file="${base}.${ASSET_EXTENSION}"
    selected=false

    set +e
    http_code="$(
      curl -sS -o "${attempt_file}" -w '%{http_code}' \
        -X GET "${EDR_URL}" \
        -H "${header}"
    )"
    curl_exit=$?
    set -e

    printf '%s\n' "${http_code}" > "${base}.http"
    lib_log INFO "[data ${attempt_n}] label=${label} HTTP=${http_code} curl_exit=${curl_exit}"

    if _phase3_attempt_is_successful "${attempt_file}" "${http_code}" "${curl_exit}"; then
      cp "${attempt_file}" "${canonical_file}"
      cp "${base}.http" "${PHASE3_DIR}/40_data_response.http"

      if [[ "${ASSET_CONTENT_KIND}" == "json" ]]; then
        _phase3_write_data_preview \
          "${canonical_file}" \
          "${PHASE3_DIR}/41_data_preview.json"
      else
        _phase3_write_data_preview_metadata \
          "${canonical_file}" \
          "${PHASE3_DIR}/41_data_preview.json"
      fi

      PHASE3_AUTH_CANDIDATE_LABEL="${label}"
      selected=true
      success=1
    fi

    summary_lines+=("$(
      jq -nc \
        --argjson attempt "$((i + 1))" \
        --arg label "${label}" \
        --argjson http "$((http_code + 0))" \
        --argjson selected "$([[ "${selected}" == true ]] && echo true || echo false)" \
        '{attempt: $attempt, label: $label, http: $http, selected: $selected}'
    )")
    if (( success == 1 )); then
      break
    fi
  done

  attempts_json="$(jq -s '.' <<< "$(printf '%s\n' "${summary_lines[@]}")")"

  if (( success == 1 )); then
    data_bytes="$(_phase3_file_bytes "${canonical_file}")"
    data_http_val="$(tr -d '\n\r' < "${PHASE3_DIR}/40_data_response.http")"
    jq -nc \
      --arg content_kind "${ASSET_CONTENT_KIND}" \
      --arg extension "${ASSET_EXTENSION}" \
      --arg media_type "${ASSET_MEDIA_TYPE}" \
      --arg data_response_file "phase3/$(_phase3_data_response_basename)" \
      --argjson data_http "${data_http_val}" \
      --argjson bytes "${data_bytes}" \
      --argjson attempts "${attempts_json}" \
      '{
        content_kind: $content_kind,
        extension: $extension,
        media_type: $media_type,
        data_response_file: $data_response_file,
        data_http: $data_http,
        bytes: $bytes,
        attempts: $attempts
      }' > "${summary_tmp}"
  else
    jq -nc \
      --argjson attempts "${attempts_json}" \
      '{attempts: $attempts}' > "${summary_tmp}"
  fi

  mv "${summary_tmp}" "${summary_file}"

  if (( success == 1 )); then
    return 0
  fi

  lib_die "No se pudo consumir el endpoint EDR con ninguna variante de autenticación. Revisar phase3/40_data_response_attempt_*.${ASSET_EXTENSION} y phase3/42_data_attempts_summary.json"
}

_phase3_write_edr_diagnostics() {
  local raw_file="$1"
  local edr_redacted="${PHASE3_DIR}/30_edr_dataaddress_redacted.json"
  local edr_keys="${PHASE3_DIR}/30_edr_dataaddress_keys.json"
  local tmp_red="${edr_redacted}.$$"
  local tmp_keys="${edr_keys}.$$"

  _phase3_jq_from_block "_PHASE3_JQ_REDACT_EDR=" "${raw_file}" > "${tmp_red}"
  mv "${tmp_red}" "${edr_redacted}"

  _phase3_jq_from_block "_PHASE3_JQ_EDR_KEYS_DIAGNOSTIC=" "${raw_file}" > "${tmp_keys}"
  mv "${tmp_keys}" "${edr_keys}"
}

_phase3_write_data_preview() {
  local data_file="$1"
  local preview_file="$2"
  local tmp="${preview_file}.$$"

  jq '
    if type == "array" then .[0:5]
    elif (tostring | length) < 4096 then .
    else {
      _preview: "truncated",
      type: (type),
      length: (if type == "array" then length else null end)
    }
    end
  ' "${data_file}" > "${tmp}"
  mv "${tmp}" "${preview_file}"
}

_phase3_ensure_edr_tmp_dir() {
  if [[ -z "${PHASE3_EDR_TMP_DIR}" || ! -d "${PHASE3_EDR_TMP_DIR}" ]]; then
    PHASE3_EDR_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase3_edr.XXXXXX")"
  fi
}

_phase3_finalize_edr() {
  local raw_file="$1"

  EDR_URL="$(jq -r "${_PHASE3_JQ_EXTRACT_EDR_URL}" "${raw_file}")"
  [[ -n "${EDR_URL}" && "${EDR_URL}" != "null" ]] \
    || lib_die "EDR_URL vacío tras resolver DataAddress"

  _phase3_write_edr_diagnostics "${raw_file}"

  EDR_AUTH_CURL_ARGS=()
  _phase3_load_edr_auth_fields "${raw_file}"
}

_phase3_poll_edr_direct() {
  local i poll_n http_code curl_exit raw_base url

  _phase3_ensure_edr_tmp_dir
  PHASE3_EDR_RAW_FILE=""
  PHASE3_EDR_HTTP=""

  for i in $(seq 1 20); do
    poll_n="$(printf '%02d' "${i}")"
    raw_base="${PHASE3_EDR_TMP_DIR}/dataaddress_${poll_n}"
    rm -f "${raw_base}.json"

    set +e
    http_code="$(
      curl -sS -o "${raw_base}.json" -w '%{http_code}' \
        -X GET "${CONSUMER_BASE}/management/v3/edrs/${TRANSFER_ID}/dataaddress" \
        -H "Authorization: Bearer ${CONSUMER_JWT}"
    )"
    curl_exit=$?
    set -e

    printf '%s\n' "${http_code}" > "${PHASE3_DIR}/30_edr_direct_${poll_n}.http"
    lib_log INFO "[edr-direct ${i}] HTTP=${http_code} curl_exit=${curl_exit}"

    if (( curl_exit != 0 )); then
      [[ "${i}" -lt 20 ]] && sleep 3
      continue
    fi

    if [[ "${http_code}" =~ ^2[0-9]{2}$ ]] \
      && [[ -s "${raw_base}.json" ]] \
      && jq empty "${raw_base}.json" 2>/dev/null; then
      url="$(jq -r "${_PHASE3_JQ_EXTRACT_EDR_URL}" "${raw_base}.json")"
      if _phase3_id_is_set "${url}"; then
        PHASE3_EDR_RAW_FILE="${raw_base}.json"
        PHASE3_EDR_HTTP="${http_code}"
        return 0
      fi
    fi

    [[ "${i}" -lt 20 ]] && sleep 3
  done

  return 1
}

_phase3_fetch_edr_fallback() {
  local req_file raw_base http_code curl_exit selected_file

  _phase3_ensure_edr_tmp_dir
  req_file="${PHASE3_EDR_TMP_DIR}/edrs_request_body.json"
  raw_base="${PHASE3_EDR_TMP_DIR}/edrs_request"
  selected_file="${PHASE3_EDR_TMP_DIR}/selected_dataaddress.json"

  _phase3_write_json "${req_file}" <<'EOF'
{
  "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
  "offset": 0,
  "limit": 50,
  "filterExpression": []
}
EOF

  set +e
  http_code="$(
    curl -sS -o "${raw_base}.json" -w '%{http_code}' \
      -X POST "${CONSUMER_BASE}/management/v3/edrs/request" \
      -H "Authorization: Bearer ${CONSUMER_JWT}" \
      -H "Content-Type: application/json" \
      -d "@${req_file}"
  )"
  curl_exit=$?
  set -e

  printf '%s\n' "${http_code}" > "${PHASE3_DIR}/31_edrs_request.http"

  if (( curl_exit != 0 )) || [[ ! "${http_code}" =~ ^2[0-9]{2}$ ]]; then
    lib_log WARN "Fallback edrs/request falló: HTTP=${http_code} curl_exit=${curl_exit}"
    return 1
  fi

  _phase3_jq_from_block "_PHASE3_JQ_REDACT_EDR=" "${raw_base}.json" \
    > "${PHASE3_DIR}/31_edrs_request_redacted.json"

  _phase3_jq_from_block "_PHASE3_JQ_SELECT_EDR_ENTRY=" -e \
    --arg transfer_id "${TRANSFER_ID}" \
    --arg asset_id "${ASSET_ID}" \
    --arg agreement_id "${AGREEMENT_ID}" \
    "${raw_base}.json" > "${selected_file}"

  if [[ ! -s "${selected_file}" ]] || ! jq -e . "${selected_file}" >/dev/null 2>&1; then
    return 1
  fi

  url="$(jq -r "${_PHASE3_JQ_EXTRACT_EDR_URL}" "${selected_file}")"
  if ! _phase3_id_is_set "${url}"; then
    return 1
  fi

  PHASE3_EDR_RAW_FILE="${selected_file}"
  PHASE3_EDR_HTTP="${http_code}"
  return 0
}

_phase3_obtain_edr() {
  local edr_source=""

  if _phase3_poll_edr_direct; then
    edr_source="direct"
  else
    lib_log WARN "EDR directo no disponible tras 20 intentos; probando fallback edrs/request"
    if _phase3_fetch_edr_fallback; then
      edr_source="fallback"
    else
      lib_die "Transfer en ${FINAL_STATE:-desconocido} pero no hay EDR resoluble (directo ni listado edrs/request)"
    fi
  fi

  _phase3_finalize_edr "${PHASE3_EDR_RAW_FILE}"
  PHASE3_EDR_SOURCE="${edr_source}"
}

_phase3_copy_transfer_final_state() {
  local poll_base="$1"
  cp "${poll_base}.json" "${PHASE3_DIR}/21_transfer_final_state.json"
  cp "${poll_base}.http" "${PHASE3_DIR}/21_transfer_final_state.http"
}

_phase3_poll_transfer_until_ready() {
  local start_i="${1:-1}"
  local i poll_n last_poll_base=""

  for i in $(seq "${start_i}" 20); do
    poll_n="$(printf '%02d' "${i}")"
    last_poll_base="${PHASE3_DIR}/20_transfer_state_${poll_n}"

    lib_curl_json "${last_poll_base}" \
      -X GET "${CONSUMER_BASE}/management/v3/transferprocesses/${TRANSFER_ID}" \
      -H "Authorization: Bearer ${CONSUMER_JWT}"

    STATE="$(_phase3_transfer_state < "${last_poll_base}.json")"
    STATE="${STATE^^}"

    lib_log INFO "[transfer ${i}] state=${STATE:-<none>}"

    if _phase3_state_acceptable "${STATE}"; then
      FINAL_STATE="${STATE}"
      _phase3_copy_transfer_final_state "${last_poll_base}"
      return 0
    fi

    if _phase3_state_failed "${STATE}"; then
      lib_die "Transfer ${STATE} (revisar phase3/20_transfer_state_${poll_n}.json)"
    fi

    [[ "${i}" -lt 20 ]] && sleep 3
  done

  lib_die "Timeout: transfer no alcanzó STARTED/COMPLETED tras 20 intentos (último estado: ${STATE:-desconocido})"
}

_phase3_resolve_transfer_id_resume() {
  local tid="" env_suffix="" last_state_file=""

  if [[ -f "$(lib_phase_env_path 3)" ]]; then
    env_suffix="$(_phase3_read_env_field "$(lib_phase_env_path 3)" SUFFIX || true)"
    if [[ -n "${env_suffix}" && "${env_suffix}" == "${SUFFIX}" ]]; then
      tid="$(_phase3_read_env_field "$(lib_phase_env_path 3)" TRANSFER_ID || true)"
      if _phase3_id_is_set "${tid}"; then
        printf '%s' "${tid}"
        return 0
      fi
    fi
  fi

  if [[ -f "${PHASE3_DIR}/21_transfer_final_state.json" ]]; then
    tid="$(_phase3_transfer_id_from_json < "${PHASE3_DIR}/21_transfer_final_state.json")"
    if _phase3_id_is_set "${tid}"; then
      printf '%s' "${tid}"
      return 0
    fi
  fi

  last_state_file="$(
    find "${PHASE3_DIR}" -maxdepth 1 -name '20_transfer_state_*.json' -print 2>/dev/null \
      | sort \
      | tail -1
  )"
  if [[ -n "${last_state_file}" && -f "${last_state_file}" ]]; then
    tid="$(_phase3_transfer_id_from_json < "${last_state_file}")"
    if _phase3_id_is_set "${tid}"; then
      printf '%s' "${tid}"
      return 0
    fi
  fi

  if [[ -f "${PHASE3_DIR}/10_transfer_response.json" ]]; then
    tid="$(_phase3_transfer_id_from_json < "${PHASE3_DIR}/10_transfer_response.json")"
    if _phase3_id_is_set "${tid}"; then
      printf '%s' "${tid}"
      return 0
    fi
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

PHASE3_STEP="init"
api_find_root

if [[ "${PHASE3_RESUME:-}" == "1" && "${PHASE3_FORCE:-}" == "1" ]]; then
  lib_die "PHASE3_RESUME=1 y PHASE3_FORCE=1 son incompatibles"
fi

if [[ -z "${SUFFIX:-}" || -z "${ASSET_ID:-}" ]] || ! _phase3_id_is_set "${AGREEMENT_ID:-}"; then
  if [[ ! -f "$(lib_phase_env_path 2)" ]]; then
    lib_die "Ejecuta primero phase2_consumer_negotiate.sh"
  fi
  # shellcheck source=/dev/null
  source "$(lib_phase_env_path 2)"
fi

if [[ "${PHASE3_FORCE:-}" != "1" && "${PHASE3_RESUME:-}" != "1" && -f "$(lib_phase_env_path 3)" ]]; then
  _existing_transfer="$(_phase3_read_env_field "$(lib_phase_env_path 3)" TRANSFER_ID || true)"
  _existing_suffix="$(_phase3_read_env_field "$(lib_phase_env_path 3)" SUFFIX || true)"
  if _phase3_id_is_set "${_existing_transfer}" \
    && [[ -n "${_existing_suffix}" && "${_existing_suffix}" == "${SUFFIX}" ]]; then
    lib_die "phase3_env.sh ya contiene TRANSFER_ID para SUFFIX=${SUFFIX}. Export PHASE3_FORCE=1 para relanzar o PHASE3_RESUME=1 para continuar."
  fi
fi

lib_load_env
lib_require_cmds
lib_require_vars_group LIB_VARS_DATASPACE
lib_require_vars_group LIB_VARS_PROVIDER
lib_require_vars_group LIB_VARS_CONSUMER
lib_require_vars_group LIB_VARS_PHASE2
lib_derive_phase1_ids
_phase3_apply_asset_content_defaults
lib_init_run_dirs
lib_init_summary

# ---------------------------------------------------------------------------
# JWT consumer
# ---------------------------------------------------------------------------

PHASE3_STEP="jwt_renew"
lib_renew_jwt consumer
lib_jwt_check_console consumer

PHASE3_STEP="jwt_claims"
lib_jwt_claims_to_json consumer "${PHASE3_DIR}/jwt_claims_consumer.json"
lib_write_summary 3 jwt_consumer ok '{"artifact":"phase3/jwt_claims_consumer.json"}'

# ---------------------------------------------------------------------------
# Contexto
# ---------------------------------------------------------------------------

PHASE3_STEP="write_context"
context_file="${PHASE3_DIR}/00_context.txt"
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
  printf 'AGREEMENT_ID=%s\n' "${AGREEMENT_ID}"
  printf 'PHASE3_RESUME=%s\n' "${PHASE3_RESUME:-0}"
  [[ -n "${ASSET_SLUG:-}" ]] && printf 'ASSET_SLUG=%s\n' "${ASSET_SLUG}"
  [[ -n "${ASSET_NAME:-}" ]] && printf 'ASSET_NAME=%s\n' "${ASSET_NAME}"
  [[ -n "${ASSET_BASE_URL:-}" ]] && printf 'ASSET_BASE_URL=%s\n' "${ASSET_BASE_URL}"
  [[ -n "${ASSET_CONTENT_KIND:-}" ]] && printf 'ASSET_CONTENT_KIND=%s\n' "${ASSET_CONTENT_KIND}"
  [[ -n "${ASSET_EXTENSION:-}" ]] && printf 'ASSET_EXTENSION=%s\n' "${ASSET_EXTENSION}"
  [[ -n "${ASSET_MEDIA_TYPE:-}" ]] && printf 'ASSET_MEDIA_TYPE=%s\n' "${ASSET_MEDIA_TYPE}"
} > "${context_tmp}"
mv "${context_tmp}" "${context_file}"

# ---------------------------------------------------------------------------
# Validación HttpData-PULL (dataset remoto Fase 2)
# ---------------------------------------------------------------------------

PHASE3_STEP="transfer_type_valid"
_phase2_dataset="${PHASE2_DIR}/selected_remote_catalog_dataset.json"
_phase3_validate_httpdata_pull "${_phase2_dataset}"
lib_write_summary 3 transfer_type_valid ok \
  "{\"asset_id\":\"${ASSET_ID}\",\"transfer_type\":\"HttpData-PULL\",\"artifact\":\"phase2/selected_remote_catalog_dataset.json\"}"

# ---------------------------------------------------------------------------
# A/B. Transfer (crear o reanudar)
# ---------------------------------------------------------------------------

if [[ "${PHASE3_RESUME:-}" == "1" ]]; then
  PHASE3_STEP="transfer_resumed"
  TRANSFER_ID="$(_phase3_resolve_transfer_id_resume || true)"
  [[ -n "${TRANSFER_ID}" ]] \
    || lib_die "PHASE3_RESUME=1: no se pudo resolver TRANSFER_ID (phase3_env.sh, 21_transfer_final_state.json o 20_transfer_state_*.json)"
  export TRANSFER_ID

  lib_log INFO "PHASE3_RESUME=1 — reutilizando TRANSFER_ID=${TRANSFER_ID}"

  resume_check="${PHASE3_DIR}/20_transfer_state_resume_00"
  lib_curl_json "${resume_check}" \
    -X GET "${CONSUMER_BASE}/management/v3/transferprocesses/${TRANSFER_ID}" \
    -H "Authorization: Bearer ${CONSUMER_JWT}"

  STATE="$(_phase3_transfer_state < "${resume_check}.json")"
  STATE="${STATE^^}"

  if _phase3_state_acceptable "${STATE}"; then
    FINAL_STATE="${STATE}"
    _phase3_copy_transfer_final_state "${resume_check}"
  elif _phase3_state_pollable "${STATE}"; then
    _phase3_poll_transfer_until_ready 1
  elif _phase3_state_failed "${STATE}"; then
    lib_die "Transfer ${STATE} (revisar phase3/20_transfer_state_resume_00.json)"
  else
    lib_log WARN "Estado transfer desconocido (${STATE}); intentando polling"
    _phase3_poll_transfer_until_ready 1
  fi

  resume_http="$(tr -d '\n' < "${PHASE3_DIR}/21_transfer_final_state.http")"
  lib_write_summary 3 transfer_resumed ok \
    "{\"http\":${resume_http},\"transfer_id\":\"${TRANSFER_ID}\",\"final_state\":\"${FINAL_STATE}\",\"artifact\":\"phase3/21_transfer_final_state\"}"
else
  PHASE3_STEP="transfer_started"
  transfer_request="${PHASE3_DIR}/10_transfer_request.json"
  _phase3_write_json "${transfer_request}" <<EOF
{
  "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
  "@type": "TransferRequest",
  "assetId": "${ASSET_ID}",
  "contractId": "${AGREEMENT_ID}",
  "counterPartyAddress": "${PROVIDER_PROTOCOL}",
  "protocol": "dataspace-protocol-http",
  "transferType": "HttpData-PULL"
}
EOF

  lib_curl_json "${PHASE3_DIR}/10_transfer_response" \
    -X POST "${CONSUMER_BASE}/management/v3/transferprocesses" \
    -H "Authorization: Bearer ${CONSUMER_JWT}" \
    -H "Content-Type: application/json" \
    -d "@${transfer_request}"

  TRANSFER_ID="$(jq -r '."@id" // .id // empty' "${PHASE3_DIR}/10_transfer_response.json")"
  [[ -n "${TRANSFER_ID}" ]] || lib_die "TRANSFER_ID vacío tras iniciar transfer"

  transfer_http="$(tr -d '\n' < "${PHASE3_DIR}/10_transfer_response.http")"
  lib_write_summary 3 transfer_started ok \
    "{\"http\":${transfer_http},\"transfer_id\":\"${TRANSFER_ID}\",\"artifact\":\"phase3/10_transfer_response\"}"

  export TRANSFER_ID

  PHASE3_STEP="transfer_final_state"
  _phase3_poll_transfer_until_ready 1

  lib_write_summary 3 transfer_final_state ok \
    "{\"transfer_id\":\"${TRANSFER_ID}\",\"final_state\":\"${FINAL_STATE}\",\"artifact\":\"phase3/21_transfer_final_state\"}"
fi

# ---------------------------------------------------------------------------
# C. Obtener EDR / DataAddress (polling + fallback)
# ---------------------------------------------------------------------------

PHASE3_STEP="edr_obtained"
_phase3_obtain_edr
[[ -n "${EDR_URL:-}" && "${EDR_URL}" != "null" ]] || lib_die "EDR_URL no quedó disponible tras _phase3_obtain_edr"
PHASE3_EDR_URL_SENSITIVE=0
if _phase3_edr_url_has_sensitive_params "${EDR_URL}"; then
  PHASE3_EDR_URL_SENSITIVE=1
fi
if ! _phase3_id_is_set "${PHASE3_EDR_AUTHORIZATION:-}" \
  && ! { _phase3_id_is_set "${PHASE3_EDR_AUTH_KEY:-}" && _phase3_id_is_set "${PHASE3_EDR_AUTH_CODE:-}"; }; then
  lib_die "No quedaron credenciales EDR disponibles tras _phase3_obtain_edr"
fi
[[ -n "${PHASE3_EDR_HTTP:-}" ]] || lib_die "PHASE3_EDR_HTTP vacío tras _phase3_obtain_edr"
[[ -n "${PHASE3_EDR_SOURCE:-}" ]] || lib_die "PHASE3_EDR_SOURCE vacío tras _phase3_obtain_edr"
_phase3_cleanup

lib_write_summary 3 edr_obtained ok \
  "$(jq -nc \
    --argjson http "${PHASE3_EDR_HTTP}" \
    --arg transfer_id "${TRANSFER_ID}" \
    --arg edr_url "$(_phase3_safe_summary_edr_url)" \
    --arg source "${PHASE3_EDR_SOURCE}" \
    --arg artifact "phase3/30_edr_dataaddress_redacted.json" \
    --argjson edr_url_redacted "${PHASE3_EDR_URL_SENSITIVE}" \
    '{http: $http, transfer_id: $transfer_id, edr_url: $edr_url, source: $source, artifact: $artifact, edr_url_redacted: ($edr_url_redacted == 1)}')"

export EDR_URL

# ---------------------------------------------------------------------------
# D. Consumir endpoint final (legacy explícito)
# ---------------------------------------------------------------------------

if [[ "${PHASE3_TRY_DATA_CONSUMPTION:-0}" == "1" && "${ASSET_HTTP_METHOD:-}" == "POST" ]]; then
  lib_write_summary 3 data_consumed skipped \
    '{"reason":"PHASE3_TRY_DATA_CONSUMPTION skipped for POST assets; use phase4_save_download.sh with INGESTA_API_REQUEST_BODY_FILE","legacy_flag":"PHASE3_TRY_DATA_CONSUMPTION=1","http_method":"POST"}'
elif [[ "${PHASE3_TRY_DATA_CONSUMPTION:-0}" == "1" ]]; then
  PHASE3_STEP="data_consumed"
  _phase3_consume_data_with_auth_candidates

  data_http="$(tr -d '\n\r' < "${PHASE3_DIR}/40_data_response.http")"
  data_bytes="$(_phase3_file_bytes "${PHASE3_DATA_RESPONSE_FILE}")"
  data_response_rel="phase3/$(_phase3_data_response_basename)"

  lib_write_summary 3 data_consumed ok \
    "$(jq -nc \
      --argjson http "${data_http}" \
      --arg auth_candidate_label "${PHASE3_AUTH_CANDIDATE_LABEL}" \
      --arg asset_content_kind "${ASSET_CONTENT_KIND}" \
      --arg asset_extension "${ASSET_EXTENSION}" \
      --arg asset_media_type "${ASSET_MEDIA_TYPE}" \
      --arg data_response_file "${data_response_rel}" \
      --argjson bytes "${data_bytes}" \
      --arg attempts_artifact "phase3/42_data_attempts_summary.json" \
      --arg preview_artifact "phase3/41_data_preview.json" \
      '{
        http: $http,
        auth_candidate_label: $auth_candidate_label,
        asset_content_kind: $asset_content_kind,
        asset_extension: $asset_extension,
        asset_media_type: $asset_media_type,
        data_response_file: $data_response_file,
        bytes: $bytes,
        attempts_artifact: $attempts_artifact,
        preview_artifact: $preview_artifact,
        legacy_phase3_consumption: true
      }')"
else
  lib_write_summary 3 data_consumed skipped \
    '{"reason":"phase3 termina en transfer + EDR; phase4_save_download.sh realiza la descarga","legacy_flag":"PHASE3_TRY_DATA_CONSUMPTION=1"}'
fi

# ---------------------------------------------------------------------------
# E. Cierre
# ---------------------------------------------------------------------------

PHASE3_STEP="export_env"
# phase3_env.sh is private runtime state. It keeps EDR_URL so a later phase
# can resume. Diagnostic artifacts receive only the redacted placeholder.
lib_export_phase_env 3
lib_set_phase_status 3 ok

trap - ERR
_phase3_cleanup
lib_log INFO "Fase 3 OK — SUFFIX=${SUFFIX} TRANSFER_ID=${TRANSFER_ID} edr_endpoint_redacted=$(lib_edr_endpoint_redacted_json "${EDR_URL:-}")"
