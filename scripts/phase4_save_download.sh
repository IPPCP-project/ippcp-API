#!/usr/bin/env bash
# phase4_save_download.sh — Fase 4: consumir EDR y materializar descarga local.
#
# Requisitos: Bash 4.3+, curl, jq, shasum u openssl (ver scripts/scripts_README.md).
#
# Prerrequisito: phase3 OK (phase3_env.sh o variables exportadas).
# Sobrescribir descarga existente con hash distinto: DOWNLOAD_FORCE=1
# Permitir body vacío: ALLOW_EMPTY_DOWNLOAD=1
# Modo experimental Ingesta API protegida: PHASE4_REQUIRES_INGESTA_API_AUTH=1
#
# Assets POST (ASSET_HTTP_METHOD=POST):
#   INGESTA_API_REQUEST_BODY_FILE=ruta/al/body.json  (obligatorio; no versionar payloads PROD)
#   Un POST de negocio se envía como máximo una vez por ejecución.
#   Si el EDR produce varios candidatos, hace falta PHASE4_POST_AUTH_LABEL
#   antes de enviar. Un intento ya registrado no se reintenta en el mismo run.
#
# Uso:
#   source runtime/env/latest/phase3_env.sh
#   /opt/homebrew/bin/bash scripts/phase4_save_download.sh

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "${_SCRIPT_DIR}/lib_common.sh"

PHASE4_STEP="init"
PHASE4_EDR_TMP_DIR=""
PHASE4_EDR_RAW_FILE=""
PHASE4_EDR_HTTP=""
PHASE4_EDR_SOURCE=""
PHASE4_EDR_AUTHORIZATION=""
PHASE4_EDR_AUTH_CODE=""
PHASE4_EDR_AUTH_KEY=""
PHASE4_EDR_AUTH_TYPE=""
PHASE4_AUTH_CANDIDATE_LABEL=""
PHASE4_DATA_RESPONSE_FILE=""
PHASE4_REQUEST_BODY_FILE=""
PHASE4_HTTP_METHOD="GET"
COPY_ACTION=""

declare -a PHASE4_AUTH_CANDIDATE_LABELS=()
declare -a PHASE4_AUTH_CANDIDATE_HEADERS=()

_phase4_cleanup() {
  if [[ -n "${PHASE4_EDR_TMP_DIR}" && -d "${PHASE4_EDR_TMP_DIR}" ]]; then
    rm -rf "${PHASE4_EDR_TMP_DIR}"
    PHASE4_EDR_TMP_DIR=""
  fi
}

_phase4_on_err() {
  local rc=$?
  _phase4_cleanup
  if [[ -n "${RUN_DIR:-}" && -d "${RUN_DIR}" ]]; then
    lib_write_summary 4 "${PHASE4_STEP}" fail "{\"exit_code\":${rc}}" 2>/dev/null || true
    lib_set_phase_status 4 fail 2>/dev/null || true
  fi
  exit "${rc}"
}
trap _phase4_on_err ERR
trap _phase4_cleanup EXIT

_phase4_id_is_set() {
  local value="${1:-}"
  [[ -n "${value}" && "${value}" != "null" ]]
}

_phase4_write_json() {
  local dest="$1"
  local tmp="${dest}.$$"
  cat > "${tmp}"
  mv "${tmp}" "${dest}"
}

_phase4_require_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    return 0
  fi
  lib_die "Se requiere shasum -a 256 u openssl para calcular SHA256"
}

_phase4_sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
    return 0
  fi
  openssl dgst -sha256 "${file}" | awk '{print $NF}'
}

_phase4_file_bytes() {
  local file="$1"
  wc -c < "${file}" | tr -d ' '
}

_phase4_sanitize_asset_id() {
  local asset_id="$1"
  printf '%s' "${asset_id}" | sed 's/[^A-Za-z0-9._-]/_/g'
}

_phase4_atomic_copy() {
  local src="$1"
  local dest="$2"
  local tmp="${dest}.$$"
  cp "${src}" "${tmp}"
  mv "${tmp}" "${dest}"
}

_phase4_extension_allowed() {
  case "${1}" in
    json|xml|gml|csv|txt|ttl|rdf|xlsx|zip) return 0 ;;
    *) return 1 ;;
  esac
}

_phase4_validate_content_kind_value() {
  case "${1}" in
    json|text|binary) return 0 ;;
    *)
      lib_die "ASSET_CONTENT_KIND debe ser json, text o binary (recibido: ${1})"
      ;;
  esac
}

_phase4_validate_extension_value() {
  _phase4_extension_allowed "${1}" \
    || lib_die "ASSET_EXTENSION no permitida (recibido: ${1}). Permitidas: json, xml, gml, csv, txt, ttl, rdf, xlsx, zip"
}

_phase4_validate_kind_extension_pair() {
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

_phase4_apply_asset_content_defaults() {
  ASSET_CONTENT_KIND="${ASSET_CONTENT_KIND:-json}"
  ASSET_EXTENSION="${ASSET_EXTENSION:-json}"
  ASSET_MEDIA_TYPE="${ASSET_MEDIA_TYPE:-application/json}"

  _phase4_validate_content_kind_value "${ASSET_CONTENT_KIND}"
  _phase4_validate_extension_value "${ASSET_EXTENSION}"
  _phase4_validate_kind_extension_pair "${ASSET_CONTENT_KIND}" "${ASSET_EXTENSION}"

  export ASSET_CONTENT_KIND ASSET_EXTENSION ASSET_MEDIA_TYPE
}

_phase4_resolve_http_method() {
  local method="${ASSET_HTTP_METHOD:-}"
  if [[ -z "${method}" ]]; then
    PHASE4_HTTP_METHOD="GET"
    return 0
  fi
  case "${method}" in
    GET|POST)
      PHASE4_HTTP_METHOD="${method}"
      ;;
    *)
      lib_die "ASSET_HTTP_METHOD no soportado en phase4: ${method} (esperado GET o POST)"
      ;;
  esac
}

_phase4_resolve_asset_config_path() {
  local config_path="${ASSET_CONFIG:-}"
  [[ -n "${config_path}" ]] || return 1
  if [[ "${config_path}" != /* ]]; then
    [[ -n "${API_ROOT:-}" ]] || return 1
    config_path="${API_ROOT}/${config_path}"
  fi
  [[ -f "${config_path}" ]] || return 1
  printf '%s\n' "${config_path}"
}

# El perfil paralelo no se reconoce por un substring. Hace falta la
# configuración local sin asset_id, el mismo upstream que la canónica,
# y el identificador exacto slug-SUFFIX.
_phase4_ebro_parallel_identity_config() {
  local config_path canonical
  config_path="$(_phase4_resolve_asset_config_path)" || return 1
  canonical="${API_ROOT}/asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json"
  [[ -f "${canonical}" ]] \
    || lib_die "configuración canónica de Ebro no disponible para clasificar el perfil paralelo"
  jq -e --slurpfile canon "${canonical}" '
    def absent_or_empty:
      (. == null) or (type == "string" and length == 0);
    type == "object"
    and (.asset_slug == "ippcp_ingesta_pull_industrias_ebro_prod")
    and (.asset_slug == $canon[0].asset_slug)
    and ((.asset_id | absent_or_empty))
    and ($canon[0].asset_id == "ippcp-ingesta-pull-industrias-ebro-prod")
    and (.type == "HttpData")
    and (.base_url == $canon[0].base_url)
    and (.base_url | type == "string" and length > 0)
    and (has("proxyMethod") | not)
    and (has("proxyPath") | not)
    and (has("proxyQueryParams") | not)
    and (has("header:X-Api-Key") | not)
    and (has("centers") | not)
    and (has("INGESTA_API_KEY") | not)
  ' "${config_path}" >/dev/null 2>&1
}

_phase4_asset_id_is_ebro_parallel_pattern() {
  local suffix="${SUFFIX:-}"
  [[ "${suffix}" =~ ^[0-9]+$ ]] || return 1
  [[ "${ASSET_ID:-}" == "ippcp_ingesta_pull_industrias_ebro_prod-${suffix}" ]]
}

_phase4_assert_ebro_parallel_gates() {
  local config_path method proxy provider
  config_path="$(_phase4_resolve_asset_config_path)" \
    || lib_die "perfil paralelo de Ebro rechazado: configuración ausente"
  method="$(jq -r '.http_method // empty' "${config_path}")"
  proxy="$(jq -r 'if .proxy_body == true then "true" else "false" end' "${config_path}")"
  provider="$(jq -r '.provider_id // empty | tostring' "${config_path}")"
  [[ "${method}" == "POST" ]] \
    || lib_die "perfil paralelo de Ebro rechazado: method distinto de POST"
  [[ "${proxy}" == "true" ]] \
    || lib_die "perfil paralelo de Ebro rechazado: proxyBody no está activo"
  [[ "${provider}" == "1" ]] \
    || lib_die "perfil paralelo de Ebro rechazado: provider id distinto de 1"
  [[ "${ASSET_HTTP_METHOD:-}" == "POST" ]] \
    || lib_die "perfil paralelo de Ebro rechazado: method distinto de POST"
  [[ "${ASSET_PROXY_BODY:-}" == "1" ]] \
    || lib_die "perfil paralelo de Ebro rechazado: proxyBody no está activo"
  [[ "${ASSET_PROVIDER_ID:-}" == "1" ]] \
    || lib_die "perfil paralelo de Ebro rechazado: provider id distinto de 1"
  [[ "${ASSET_SLUG:-}" == "ippcp_ingesta_pull_industrias_ebro_prod" ]] \
    || lib_die "perfil paralelo de Ebro rechazado: el slug no coincide con la configuración validada"
  _phase4_asset_id_is_ebro_parallel_pattern \
    || lib_die "perfil paralelo de Ebro rechazado: el identificador no es el derivado del slug y el SUFFIX"
}

_phase4_classify_prod_company_profile() {
  local asset_id="${ASSET_ID:-}"
  local identity=0
  local id_pattern=0

  if _phase4_ebro_parallel_identity_config; then
    identity=1
  fi
  if _phase4_asset_id_is_ebro_parallel_pattern; then
    id_pattern=1
  fi

  if [[ "${asset_id}" == "ippcp-ingesta-pull-industrias-ebro-prod" || "${asset_id}" == "ippcp-ingesta-pull-circe-prod" ]]; then
    if (( identity == 1 || id_pattern == 1 )); then
      lib_die "clasificación de asset PROD ambigua: el identificador estable no puede combinarse con el perfil paralelo de Ebro"
    fi
    if [[ "${asset_id}" == "ippcp-ingesta-pull-industrias-ebro-prod" ]]; then
      printf 'ebro\n'
    else
      printf 'circe\n'
    fi
    return 0
  fi

  if (( identity == 1 )); then
    _phase4_assert_ebro_parallel_gates
    printf 'ebro\n'
    return 0
  fi

  if (( id_pattern == 1 )); then
    lib_die "clasificación de asset PROD ambigua: el identificador paralelo de Ebro no está respaldado por su configuración"
  fi

  printf '\n'
}

_phase4_validate_prod_company_payload() {
  local body_path="$1"
  local profile
  profile="$(_phase4_classify_prod_company_profile)"
  if [[ -z "${profile}" ]]; then
    return 0
  fi

  [[ -f "${body_path}" ]] || lib_die "payload PROD ausente"
  [[ -s "${body_path}" ]] || lib_die "payload PROD vacío"
  jq empty "${body_path}" >/dev/null 2>&1 \
    || lib_die "payload PROD no es JSON válido"

  if ! jq -e '
    type == "object"
    and (.centers | type == "array" and length > 0)
    and (.centers[0] | type == "object")
  ' "${body_path}" >/dev/null 2>&1; then
    lib_die "payload PROD: se requiere un objeto raíz con centers no vacío"
  fi

  if [[ "${profile}" == "ebro" ]]; then
    if ! jq -e '
      (.centers[0].centerId | type == "number" and . == floor)
      and ((.centers[0] | has("districtCode")) | not)
    ' "${body_path}" >/dev/null 2>&1; then
      lib_die "payload Industrias Ebro inválido: se requiere centers[0].centerId entero y no debe contener districtCode"
    fi
  elif [[ "${profile}" == "circe" ]]; then
    if ! jq -e '
      (.centers[0].districtCode | type == "string" and length > 0)
      and ((.centers[0] | has("centerId")) | not)
    ' "${body_path}" >/dev/null 2>&1; then
      lib_die "payload CIRCE inválido: se requiere centers[0].districtCode cadena no vacía y no debe contener centerId"
    fi
  else
    lib_die "clasificación de asset PROD ambigua"
  fi
}

_phase4_prepare_request_body() {
  PHASE4_REQUEST_BODY_FILE=""
  if [[ "${PHASE4_HTTP_METHOD}" != "POST" ]]; then
    return 0
  fi

  [[ -n "${INGESTA_API_REQUEST_BODY_FILE:-}" ]] \
    || lib_die "INGESTA_API_REQUEST_BODY_FILE requerido para assets POST antes de llamar al Data Plane"

  local body_path="${INGESTA_API_REQUEST_BODY_FILE}"
  if [[ "${body_path}" != /* ]]; then
    body_path="${API_ROOT}/${body_path}"
  fi

  [[ -f "${body_path}" ]] \
    || lib_die "INGESTA_API_REQUEST_BODY_FILE no encontrado: ${body_path}"
  [[ -s "${body_path}" ]] \
    || lib_die "INGESTA_API_REQUEST_BODY_FILE vacío: ${body_path}"

  if [[ "${ASSET_CONTENT_KIND}" == "json" ]]; then
    jq empty "${body_path}" \
      || lib_die "INGESTA_API_REQUEST_BODY_FILE no es JSON válido"
  fi

  _phase4_validate_prod_company_payload "${body_path}"

  PHASE4_REQUEST_BODY_FILE="${body_path}"
  lib_log INFO "phase4 POST request configured (body file present; content not logged)"
}

_phase4_data_response_basename() {
  printf '40_data_response.%s' "${ASSET_EXTENSION}"
}

_phase4_edr_url_has_sensitive_params() {
  local value="${1:-}"
  [[ -n "${value}" && "${value}" != "null" ]]
}

_phase4_safe_edr_url() {
  lib_diagnostic_edr_endpoint "${EDR_URL:-}"
}

_phase4_assert_no_sensitive_control_artifact() {
  local file="$1"
  [[ -f "${file}" ]] || return 0

  if awk '/Authorization|Bearer |access_token|INGESTA_API_BEARER_TOKEN|client_secret/ { found = 1; exit } END { exit found ? 0 : 1 }' "${file}"; then
    lib_die "Artefacto phase4 contiene material sensible o header Authorization: ${file}"
  fi

  if [[ "${file}" == *.json ]] && jq -e '
    . as $root
    | any(paths(scalars) as $p;
        (($p[-1] | tostring | ascii_downcase | endswith("header:x-api-key")))
        and (($root | getpath($p)) != "<redacted>"))
  ' "${file}" >/dev/null 2>&1; then
    lib_die "Artefacto phase4 contiene header:X-Api-Key sin <redacted>: ${file}"
  fi

  if [[ -n "${PHASE4_REQUEST_BODY_FILE:-}" && -f "${PHASE4_REQUEST_BODY_FILE}" ]]; then
    local compact_body=""
    compact_body="$(jq -c . "${PHASE4_REQUEST_BODY_FILE}" 2>/dev/null || true)"
    if [[ -n "${compact_body}" && ${#compact_body} -ge 24 ]] \
      && grep -Fq -- "${compact_body}" "${file}"; then
      lib_die "Artefacto phase4 contiene el body POST de entrada: ${file}"
    fi
  fi
}

_phase4_redact_edr_file() {
  local raw_file="$1"
  local redacted_file="$2"
  local tmp="${redacted_file}.$$"

  jq '
    def key_is_endpoint($k):
      ($k | ascii_downcase) as $kl
      | $kl == "endpoint" or $kl == "endpointurl" or $kl == "edc:endpoint"
        or ($kl | test("(^|[/:])endpoint$"));
    def key_should_redact($k):
      ($k | ascii_downcase | test("token"))
      or ($k | ascii_downcase | test("secret"))
      or ($k | ascii_downcase | test("authorization"))
      or ($k | ascii_downcase | test("auth"))
      or ($k | ascii_downcase | test("code"))
      or ($k | ascii_downcase | test("credential"));
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
  ' "${raw_file}" > "${tmp}"
  mv "${tmp}" "${redacted_file}"
}

_phase4_write_edr_keys_diagnostic() {
  local raw_file="$1"
  local keys_file="$2"
  local tmp="${keys_file}.$$"

  jq '
    def path_label($p):
      $p | map(if type == "number" then "[\(. | tostring)]" else . end) | join(".");
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
        ] | unique | sort
      )
    }
  ' "${raw_file}" > "${tmp}"
  mv "${tmp}" "${keys_file}"
}

_phase4_extract_edr_url() {
  jq -r '.endpoint // .endpointUrl // ."edc:endpoint" // empty' "$1"
}

_phase4_extract_auth_json() {
  local raw_file="$1"

  jq -c '
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
      authorization: (direct_authorization // find_authorization_recursive // ""),
      authCode: (direct_auth_code // find_auth_code_recursive // ""),
      authKey: (direct_auth_key // find_auth_key_recursive // ""),
      authType: ((.authType // ."edc:authType" // ."https://w3id.org/edc/v0.0.1/ns/authType" // "") | if type == "string" then . else "" end)
    }
  ' "${raw_file}"
}

_phase4_load_edr_auth_fields() {
  local raw_file="$1"
  local auth_json

  auth_json="$(_phase4_extract_auth_json "${raw_file}")"
  PHASE4_EDR_AUTHORIZATION="$(jq -r '.authorization // empty' <<< "${auth_json}")"
  PHASE4_EDR_AUTH_CODE="$(jq -r '.authCode // empty' <<< "${auth_json}")"
  PHASE4_EDR_AUTH_KEY="$(jq -r '.authKey // empty' <<< "${auth_json}")"
  PHASE4_EDR_AUTH_TYPE="$(jq -r '.authType // empty' <<< "${auth_json}")"

  if _phase4_id_is_set "${PHASE4_EDR_AUTHORIZATION}" \
    || { _phase4_id_is_set "${PHASE4_EDR_AUTH_KEY}" && _phase4_id_is_set "${PHASE4_EDR_AUTH_CODE}"; }; then
    return 0
  fi

  lib_die "EDR DataAddress sin credenciales reconocibles. Revisar phase4/30_edr_dataaddress_redacted.json y phase4/30_edr_dataaddress_keys.json"
}

_phase4_authorization_has_bearer_prefix() {
  local value="${1:-}"
  [[ "${value}" =~ ^[Bb][Ee][Aa][Rr][Ee][Rr][[:space:]] ]]
}

_phase4_normalize_auth_type_prefix() {
  local auth_type="${1:-}"
  local lower="${auth_type,,}"
  case "${lower}" in
    bearer) printf 'Bearer' ;;
    *) printf '%s' "${auth_type}" ;;
  esac
}

_phase4_register_auth_candidate() {
  local label="$1"
  local header="$2"
  local existing

  for existing in "${PHASE4_AUTH_CANDIDATE_HEADERS[@]}"; do
    [[ "${existing}" == "${header}" ]] && return 0
  done

  PHASE4_AUTH_CANDIDATE_LABELS+=("${label}")
  PHASE4_AUTH_CANDIDATE_HEADERS+=("${header}")
}

_phase4_build_auth_candidates() {
  PHASE4_AUTH_CANDIDATE_LABELS=()
  PHASE4_AUTH_CANDIDATE_HEADERS=()

  if _phase4_id_is_set "${PHASE4_EDR_AUTH_KEY}" && _phase4_id_is_set "${PHASE4_EDR_AUTH_CODE}"; then
    _phase4_register_auth_candidate "authkey_authcode" "${PHASE4_EDR_AUTH_KEY}: ${PHASE4_EDR_AUTH_CODE}"
  fi

  if _phase4_id_is_set "${PHASE4_EDR_AUTHORIZATION}"; then
    if _phase4_authorization_has_bearer_prefix "${PHASE4_EDR_AUTHORIZATION}"; then
      _phase4_register_auth_candidate "authorization_as_is" "Authorization: ${PHASE4_EDR_AUTHORIZATION}"
    fi

    _phase4_register_auth_candidate "authorization_raw" "Authorization: ${PHASE4_EDR_AUTHORIZATION}"

    if ! _phase4_authorization_has_bearer_prefix "${PHASE4_EDR_AUTHORIZATION}"; then
      _phase4_register_auth_candidate "authorization_bearer" "Authorization: Bearer ${PHASE4_EDR_AUTHORIZATION}"

      if _phase4_id_is_set "${PHASE4_EDR_AUTH_TYPE}"; then
        _phase4_register_auth_candidate "authorization_authtype" \
          "Authorization: $(_phase4_normalize_auth_type_prefix "${PHASE4_EDR_AUTH_TYPE}") ${PHASE4_EDR_AUTHORIZATION}"
      fi
    fi
  fi

  (( ${#PHASE4_AUTH_CANDIDATE_LABELS[@]} > 0 )) \
    || lib_die "No hay candidatos de autenticación EDR tras extraer credenciales"
}

_phase4_header_is_authorization() {
  local header="${1:-}"
  [[ "${header}" =~ ^[Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]: ]]
}

_phase4_ensure_edr_tmp_dir() {
  if [[ -z "${PHASE4_EDR_TMP_DIR}" || ! -d "${PHASE4_EDR_TMP_DIR}" ]]; then
    PHASE4_EDR_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase4_edr.XXXXXX")"
  fi
}

_phase4_select_edr_entry() {
  local raw_file="$1"
  local selected_file="$2"

  jq -e \
    --arg transfer_id "${TRANSFER_ID}" \
    --arg asset_id "${ASSET_ID}" \
    --arg agreement_id "${AGREEMENT_ID}" \
    '
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
    ' "${raw_file}" > "${selected_file}"
}

_phase4_finalize_edr() {
  local raw_file="$1"

  EDR_URL="$(_phase4_extract_edr_url "${raw_file}")"
  [[ -n "${EDR_URL}" && "${EDR_URL}" != "null" ]] \
    || lib_die "EDR_URL vacío tras resolver DataAddress"

  _phase4_redact_edr_file "${raw_file}" "${PHASE4_DIR}/30_edr_dataaddress_redacted.json"
  _phase4_write_edr_keys_diagnostic "${raw_file}" "${PHASE4_DIR}/30_edr_dataaddress_keys.json"
  _phase4_load_edr_auth_fields "${raw_file}"
}

_phase4_poll_edr_direct() {
  local i poll_n http_code curl_exit raw_base url

  _phase4_ensure_edr_tmp_dir
  PHASE4_EDR_RAW_FILE=""
  PHASE4_EDR_HTTP=""

  for i in $(seq 1 20); do
    poll_n="$(printf '%02d' "${i}")"
    raw_base="${PHASE4_EDR_TMP_DIR}/dataaddress_${poll_n}"
    rm -f "${raw_base}.json"

    set +e
    http_code="$(
      curl -sS -o "${raw_base}.json" -w '%{http_code}' \
        -X GET "${CONSUMER_BASE}/management/v3/edrs/${TRANSFER_ID}/dataaddress" \
        -H "Authorization: Bearer ${CONSUMER_JWT}"
    )"
    curl_exit=$?
    set -e

    printf '%s\n' "${http_code}" > "${PHASE4_DIR}/30_edr_direct_${poll_n}.http"
    lib_log INFO "[phase4 edr-direct ${i}] HTTP=${http_code} curl_exit=${curl_exit}"

    if (( curl_exit != 0 )); then
      [[ "${i}" -lt 20 ]] && sleep 3
      continue
    fi

    if [[ "${http_code}" =~ ^2[0-9]{2}$ ]] \
      && [[ -s "${raw_base}.json" ]] \
      && jq empty "${raw_base}.json" 2>/dev/null; then
      url="$(_phase4_extract_edr_url "${raw_base}.json")"
      if _phase4_id_is_set "${url}"; then
        PHASE4_EDR_RAW_FILE="${raw_base}.json"
        PHASE4_EDR_HTTP="${http_code}"
        return 0
      fi
    fi

    [[ "${i}" -lt 20 ]] && sleep 3
  done

  return 1
}

_phase4_fetch_edr_fallback() {
  local req_file raw_base http_code curl_exit selected_file url

  _phase4_ensure_edr_tmp_dir
  req_file="${PHASE4_DIR}/31_edrs_request_body.json"
  raw_base="${PHASE4_EDR_TMP_DIR}/edrs_request"
  selected_file="${PHASE4_EDR_TMP_DIR}/selected_dataaddress.json"

  _phase4_write_json "${req_file}" <<'EOF'
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

  printf '%s\n' "${http_code}" > "${PHASE4_DIR}/31_edrs_request.http"

  if (( curl_exit != 0 )) || [[ ! "${http_code}" =~ ^2[0-9]{2}$ ]]; then
    lib_log WARN "Fallback phase4 edrs/request falló: HTTP=${http_code} curl_exit=${curl_exit}"
    return 1
  fi

  _phase4_redact_edr_file "${raw_base}.json" "${PHASE4_DIR}/31_edrs_request_redacted.json"
  _phase4_select_edr_entry "${raw_base}.json" "${selected_file}" || return 1

  if [[ ! -s "${selected_file}" ]] || ! jq -e . "${selected_file}" >/dev/null 2>&1; then
    return 1
  fi

  url="$(_phase4_extract_edr_url "${selected_file}")"
  if ! _phase4_id_is_set "${url}"; then
    return 1
  fi

  PHASE4_EDR_RAW_FILE="${selected_file}"
  PHASE4_EDR_HTTP="${http_code}"
  return 0
}

_phase4_obtain_edr() {
  if _phase4_poll_edr_direct; then
    PHASE4_EDR_SOURCE="direct"
  else
    lib_log WARN "EDR directo no disponible en phase4; probando fallback edrs/request"
    if _phase4_fetch_edr_fallback; then
      PHASE4_EDR_SOURCE="fallback"
    else
      lib_die "No hay EDR resoluble en phase4 (directo ni listado edrs/request)"
    fi
  fi

  _phase4_finalize_edr "${PHASE4_EDR_RAW_FILE}"
}

_phase4_load_ingesta_api_token_if_needed() {
  if [[ "${PHASE4_REQUIRES_INGESTA_API_AUTH:-0}" != "1" ]]; then
    return 0
  fi

  if [[ -n "${INGESTA_API_BEARER_TOKEN:-}" ]]; then
    return 0
  fi

  local env_file="${INGESTA_API_AUTH_ENV:-${API_ROOT}/data/real/ingesta/auth/ingesta_api_auth.env}"
  local token_helper="${API_ROOT}/data/real/ingesta/auth/get_ingesta_api_token.sh"

  if [[ -f "${env_file}" ]]; then
    # shellcheck source=/dev/null
    source "${env_file}"
  fi

  [[ -x "${token_helper}" || -f "${token_helper}" ]] \
    || lib_die "Helper de token no encontrado: ${token_helper}"

  INGESTA_API_BEARER_TOKEN="$("${token_helper}")" \
    || lib_die "No se pudo obtener token de Ingesta API en runtime"
  [[ -n "${INGESTA_API_BEARER_TOKEN}" ]] \
    || lib_die "Token de Ingesta API vacío"
}

_phase4_attempt_is_successful() {
  local attempt_file="$1"
  local http_code="$2"
  local curl_exit="$3"
  local bytes

  (( curl_exit == 0 )) || return 1
  [[ "${http_code}" =~ ^2[0-9]{2}$ ]] || return 1
  [[ -f "${attempt_file}" ]] || return 1

  # POST intake: Geoslab has not fixed a response contract (200/201/202/204, empty or JSON).
  # Treat any 2xx as success; do not inherit GET download emptiness/JSON requirements.
  if [[ "${PHASE4_HTTP_METHOD}" == "POST" ]]; then
    return 0
  fi

  bytes="$(_phase4_file_bytes "${attempt_file}")"
  if (( bytes == 0 )) && [[ "${ALLOW_EMPTY_DOWNLOAD:-}" != "1" ]]; then
    return 1
  fi

  if [[ "${ASSET_CONTENT_KIND}" == "json" ]]; then
    jq empty "${attempt_file}" 2>/dev/null || return 1
  fi

  return 0
}

_phase4_write_data_preview() {
  local data_file="$1"
  local preview_file="$2"
  local tmp="${preview_file}.$$"

  # GET-only preview. POST never embeds response bodies in evidence.
  if [[ "${ASSET_CONTENT_KIND}" == "json" ]]; then
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
  else
    jq -n \
      --arg content_kind "${ASSET_CONTENT_KIND}" \
      --arg extension "${ASSET_EXTENSION}" \
      --arg media_type "${ASSET_MEDIA_TYPE}" \
      --argjson bytes "$(_phase4_file_bytes "${data_file}")" \
      '{content_kind: $content_kind, extension: $extension, media_type: $media_type, bytes: $bytes, preview_available: false}' \
      > "${tmp}"
  fi

  mv "${tmp}" "${preview_file}"
}

_phase4_ensure_post_tmp_dir() {
  if [[ -z "${PHASE4_EDR_TMP_DIR}" || ! -d "${PHASE4_EDR_TMP_DIR}" ]]; then
    PHASE4_EDR_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase4_edr.XXXXXX")"
  fi
}

_phase4_scrub_file() {
  local file="$1"
  if [[ -n "${file}" && -e "${file}" ]]; then
    rm -f "${file}"
  fi
}

_phase4_write_post_metadata_manifest() {
  local dest="$1"
  local tmp="${dest}.$$"

  jq -n \
    --arg suffix "${SUFFIX}" \
    --arg asset_id "${ASSET_ID}" \
    --arg agreement_id "${AGREEMENT_ID}" \
    --arg transfer_id "${TRANSFER_ID}" \
    --arg edr_url "$(_phase4_safe_edr_url)" \
    --arg operation "POST" \
    --arg auth_candidate_label "${PHASE4_AUTH_CANDIDATE_LABEL}" \
    --arg response_media_type "${PHASE4_POST_RESPONSE_MEDIA_TYPE:-}" \
    --arg created_at "$(lib_now_iso)" \
    --argjson http_status "${DATA_HTTP}" \
    --argjson response_bytes "${PHASE4_POST_RESPONSE_BYTES:-0}" \
    --argjson edr_url_redacted "$(_phase4_edr_url_has_sensitive_params "${EDR_URL:-}" && echo true || echo false)" \
    --argjson request_body_bytes "${PHASE4_POST_REQUEST_BODY_BYTES:-0}" \
    --arg attempt_consumed "${PHASE4_POST_ATTEMPT_CONSUMED:-}" \
    --arg business_count "${PHASE4_BUSINESS_POST_COUNT:-}" \
    '{
      suffix: $suffix,
      asset_id: $asset_id,
      agreement_id: $agreement_id,
      transfer_id: $transfer_id,
      edr_url: $edr_url,
      edr_url_redacted: $edr_url_redacted,
      operation: $operation,
      http_method: "POST",
      http_status: $http_status,
      response_bytes: $response_bytes,
      response_media_type: $response_media_type,
      response_body_persisted: false,
      request_body_persisted: false,
      request_body_bytes: $request_body_bytes,
      download_persisted: false,
      auth_candidate_label: $auth_candidate_label,
      created_at: $created_at,
      status: "ok",
      manifest_kind: "post_metadata_only"
    }
    + (if $attempt_consumed == "1" then {post_attempt_consumed: true} else {} end)
    + (if $business_count != "" then {business_post_count: ($business_count | tonumber)} else {} end)
    ' > "${tmp}"

  mv "${tmp}" "${dest}"
}

_phase4_finalize_post_metadata_only() {
  local result_file="${PHASE4_DIR}/post_result.json"
  local manifest_file="${PHASE4_DIR}/post_manifest.json"

  [[ -n "${DATA_HTTP:-}" ]] || lib_die "POST phase4: DATA_HTTP vacío tras consumo"
  [[ -n "${PHASE4_AUTH_CANDIDATE_LABEL:-}" ]] || lib_die "POST phase4: auth candidate vacío"

  jq -n \
    --arg operation "POST" \
    --arg auth_candidate_label "${PHASE4_AUTH_CANDIDATE_LABEL}" \
    --arg response_media_type "${PHASE4_POST_RESPONSE_MEDIA_TYPE:-}" \
    --arg created_at "$(lib_now_iso)" \
    --argjson http_status "${DATA_HTTP}" \
    --argjson response_bytes "${PHASE4_POST_RESPONSE_BYTES:-0}" \
    --argjson request_body_bytes "${PHASE4_POST_REQUEST_BODY_BYTES:-0}" \
    --arg attempt_consumed "${PHASE4_POST_ATTEMPT_CONSUMED:-}" \
    --arg business_count "${PHASE4_BUSINESS_POST_COUNT:-}" \
    '{
      operation: $operation,
      http_method: "POST",
      http_status: $http_status,
      response_bytes: $response_bytes,
      response_media_type: $response_media_type,
      response_body_persisted: false,
      request_body_persisted: false,
      request_body_bytes: $request_body_bytes,
      download_persisted: false,
      auth_candidate_label: $auth_candidate_label,
      status: "ok",
      created_at: $created_at
    }
    + (if $attempt_consumed == "1" then {post_attempt_consumed: true} else {} end)
    + (if $business_count != "" then {business_post_count: ($business_count | tonumber)} else {} end)
    ' > "${result_file}"

  _phase4_write_post_metadata_manifest "${manifest_file}"

  # Scrub any residual response bodies under phase4 (attempts or canonical).
  local residual
  shopt -s nullglob
  for residual in \
    "${PHASE4_DIR}/40_data_response."* \
    "${PHASE4_DIR}/40_data_response_attempt_"* \
    "${PHASE4_DIR}/41_data_preview.json"
  do
    case "${residual}" in
      *.http) continue ;;
    esac
    _phase4_scrub_file "${residual}"
  done
  shopt -u nullglob

  _phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/42_data_attempts_summary.json"
  _phase4_assert_no_sensitive_control_artifact "${result_file}"
  _phase4_assert_no_sensitive_control_artifact "${manifest_file}"
}

_phase4_select_post_auth_candidate() {
  local count="${#PHASE4_AUTH_CANDIDATE_LABELS[@]}"
  local wanted="${PHASE4_POST_AUTH_LABEL:-}"
  local i found=-1

  if (( count < 1 )); then
    lib_die "No hay candidatos de autenticación EDR tras extraer credenciales"
  fi

  if [[ -n "${wanted}" ]]; then
    for i in "${!PHASE4_AUTH_CANDIDATE_LABELS[@]}"; do
      if [[ "${PHASE4_AUTH_CANDIDATE_LABELS[$i]}" == "${wanted}" ]]; then
        if (( found >= 0 )); then
          lib_die "PHASE4_POST_AUTH_LABEL ambiguo; no se envía el POST"
        fi
        found="${i}"
      fi
    done
    if (( found < 0 )); then
      lib_die "PHASE4_POST_AUTH_LABEL no coincide con un candidato; no se envía el POST"
    fi
  elif (( count != 1 )); then
    lib_die "autenticación POST ambigua (${count} candidatos); no se envía ninguna petición de negocio"
  else
    found=0
  fi

  PHASE4_AUTH_CANDIDATE_LABEL="${PHASE4_AUTH_CANDIDATE_LABELS[$found]}"
  PHASE4_POST_AUTH_HEADER="${PHASE4_AUTH_CANDIDATE_HEADERS[$found]}"
}

_phase4_post_attempt_marker_path() {
  printf '%s/post_attempt_consumed.json' "${PHASE4_DIR}"
}

_phase4_refuse_repeated_post_attempt() {
  local marker
  marker="$(_phase4_post_attempt_marker_path)"
  if [[ -f "${marker}" ]]; then
    lib_die "POST phase4 ya fue intentado para SUFFIX=${SUFFIX}. No se reintenta. Hace falta una operación nueva autorizada por separado."
  fi
}

_phase4_write_post_attempt_marker() {
  local outcome="$1"
  local http_status="$2"
  local curl_exit_value="$3"
  local marker tmp

  marker="$(_phase4_post_attempt_marker_path)"
  tmp="${marker}.$$"
  jq -n \
    --arg suffix "${SUFFIX}" \
    --arg asset_id "${ASSET_ID}" \
    --arg outcome "${outcome}" \
    --arg auth_label "${PHASE4_AUTH_CANDIDATE_LABEL}" \
    --arg http_status "${http_status}" \
    --arg curl_exit "${curl_exit_value}" \
    '{
      suffix: $suffix,
      asset_id: $asset_id,
      post_attempt_consumed: true,
      business_post_count: 1,
      outcome: $outcome,
      auth_candidate_label: $auth_label,
      http_status: (if $http_status == "" then null else ($http_status | tonumber) end),
      curl_exit: (if $curl_exit == "" then null else ($curl_exit | tonumber) end)
    }' > "${tmp}"
  mv "${tmp}" "${marker}"
  chmod 600 "${marker}"
}

_phase4_consume_prod_post_once() {
  local request_body_bytes="$1"
  local label header base attempt_n="01"
  local -a curl_headers=()
  local -a curl_extra=()
  local post_tmp_body curl_meta curl_exit http_code
  local response_media_type="" data_bytes=0 success=0
  local summary_file="${PHASE4_DIR}/42_data_attempts_summary.json"
  local summary_tmp="${summary_file}.$$"
  local outcome="transport_or_ambiguous"
  local http_json="null"

  _phase4_select_post_auth_candidate
  _phase4_refuse_repeated_post_attempt

  label="${PHASE4_AUTH_CANDIDATE_LABEL}"
  header="${PHASE4_POST_AUTH_HEADER}"
  base="${PHASE4_DIR}/40_data_response_attempt_${attempt_n}"

  _phase4_write_post_attempt_marker "pending" "" ""

  _phase4_ensure_post_tmp_dir
  post_tmp_body="${PHASE4_EDR_TMP_DIR}/post_attempt_${attempt_n}.body"
  curl_headers=(-H "${header}")
  if [[ "${PHASE4_REQUIRES_INGESTA_API_AUTH:-0}" == "1" ]]; then
    if _phase4_header_is_authorization "${header}"; then
      lib_die "No se puede usar Authorization simultáneamente para autenticar contra el EDR/Data Plane y contra la Ingesta API upstream. Hace falta proxy/backend, trust Data Plane-backend, header alternativo o credencial gestionada en infraestructura."
    fi
    curl_headers+=(-H "Authorization: Bearer ${INGESTA_API_BEARER_TOKEN}")
  fi
  curl_headers+=(-H "Content-Type: ${ASSET_MEDIA_TYPE:-application/json}")
  curl_extra=(--data-binary @"${PHASE4_REQUEST_BODY_FILE}")

  set +e
  curl_meta="$(
    curl -sS --retry 0 -o "${post_tmp_body}" -w '%{http_code}\t%{content_type}' \
      -X POST "${EDR_URL}" \
      "${curl_headers[@]}" \
      "${curl_extra[@]}"
  )"
  curl_exit=$?
  set -e

  http_code="$(printf '%s' "${curl_meta}" | awk -F '\t' '{print $1}')"
  response_media_type="$(printf '%s' "${curl_meta}" | awk -F '\t' '{print $2}')"
  if [[ ! "${http_code}" =~ ^[0-9]{3}$ ]]; then
    http_code=""
  fi
  if [[ -n "${http_code}" ]]; then
    printf '%s\n' "${http_code}" > "${base}.http"
  else
    printf '%s\n' "000" > "${base}.http"
  fi
  lib_log INFO "[phase4 data 01] label=${label} method=POST HTTP=${http_code:-none} curl_exit=${curl_exit}"

  data_bytes=0
  if [[ -f "${post_tmp_body}" ]]; then
    data_bytes="$(_phase4_file_bytes "${post_tmp_body}")"
  fi

  if [[ "${curl_exit}" -ne 0 || -z "${http_code}" ]]; then
    outcome="transport_or_ambiguous"
    success=0
  elif _phase4_attempt_is_successful "${post_tmp_body}" "${http_code}" "${curl_exit}"; then
    outcome="http_2xx"
    success=1
    cp "${base}.http" "${PHASE4_DIR}/40_data_response.http"
    PHASE4_POST_RESPONSE_BYTES="${data_bytes}"
    PHASE4_POST_RESPONSE_MEDIA_TYPE="${response_media_type}"
    PHASE4_DATA_RESPONSE_FILE=""
    export PHASE4_DATA_RESPONSE_FILE
  else
    outcome="http_error"
    success=0
  fi

  _phase4_scrub_file "${post_tmp_body}"
  _phase4_write_post_attempt_marker "${outcome}" "${http_code}" "${curl_exit}"

  PHASE4_POST_ATTEMPT_CONSUMED=1
  PHASE4_BUSINESS_POST_COUNT=1
  export PHASE4_POST_ATTEMPT_CONSUMED PHASE4_BUSINESS_POST_COUNT PHASE4_AUTH_CANDIDATE_LABEL

  if [[ "${http_code}" =~ ^[0-9]+$ ]]; then
    http_json="${http_code}"
  fi

  jq -nc \
    --arg outcome "${outcome}" \
    --arg label "${label}" \
    --argjson http "${http_json}" \
    --argjson selected "$([[ "${success}" == 1 ]] && echo true || echo false)" \
    --argjson response_bytes "${data_bytes}" \
    --argjson request_body_bytes "${request_body_bytes}" \
    '{
      http_method: "POST",
      post_attempt_consumed: true,
      business_post_count: 1,
      outcome: $outcome,
      request_body_bytes: $request_body_bytes,
      response_body_persisted: false,
      request_body_persisted: false,
      download_persisted: false,
      attempts: [{
        attempt: 1,
        label: $label,
        http: $http,
        selected: $selected,
        http_method: "POST",
        response_bytes: $response_bytes,
        response_body_persisted: false
      }]
    }' > "${summary_tmp}"
  mv "${summary_tmp}" "${summary_file}"

  if (( success == 1 )); then
    return 0
  fi

  if [[ "${outcome}" == "transport_or_ambiguous" ]]; then
    lib_die "POST phase4 con resultado de transporte ambiguo. No se reintenta: un timeout no demuestra que la petición no se procesó."
  fi
  lib_die "POST phase4 no satisfactorio (HTTP ${http_code:-desconocido}). No se prueba otro candidato ni se reintenta."
}

_phase4_consume_data_with_auth_candidates() {
  local i attempt_n label header http_code curl_exit base attempt_file selected=false success=0
  local summary_file="${PHASE4_DIR}/42_data_attempts_summary.json"
  local summary_tmp="${summary_file}.$$"
  local -a summary_lines=()
  local attempts_json data_bytes data_http_val
  local canonical_file="${PHASE4_DIR}/$(_phase4_data_response_basename)"
  local -a curl_headers=()
  local -a curl_extra=()
  local request_body_bytes=0
  local curl_meta response_media_type=""
  local post_tmp_body=""
  local attempt_response_bytes=0
  local data_bytes=0

  PHASE4_DATA_RESPONSE_FILE="${canonical_file}"
  export PHASE4_DATA_RESPONSE_FILE
  PHASE4_POST_RESPONSE_BYTES=0
  PHASE4_POST_RESPONSE_MEDIA_TYPE=""
  PHASE4_POST_REQUEST_BODY_BYTES=0

  _phase4_resolve_http_method
  _phase4_prepare_request_body
  _phase4_build_auth_candidates
  _phase4_load_ingesta_api_token_if_needed

  if [[ -n "${PHASE4_REQUEST_BODY_FILE}" ]]; then
    request_body_bytes="$(_phase4_file_bytes "${PHASE4_REQUEST_BODY_FILE}")"
    PHASE4_POST_REQUEST_BODY_BYTES="${request_body_bytes}"
  fi

  if [[ "${PHASE4_HTTP_METHOD}" == "POST" ]]; then
    _phase4_consume_prod_post_once "${request_body_bytes}"
    return 0
  fi

  for i in "${!PHASE4_AUTH_CANDIDATE_LABELS[@]}"; do
    attempt_n="$(printf '%02d' "$((i + 1))")"
    label="${PHASE4_AUTH_CANDIDATE_LABELS[$i]}"
    header="${PHASE4_AUTH_CANDIDATE_HEADERS[$i]}"
    base="${PHASE4_DIR}/40_data_response_attempt_${attempt_n}"
    attempt_file="${base}.${ASSET_EXTENSION}"
    selected=false
    curl_headers=(-H "${header}")
    curl_extra=()
    response_media_type=""
    post_tmp_body=""

    if [[ "${PHASE4_REQUIRES_INGESTA_API_AUTH:-0}" == "1" ]]; then
      if _phase4_header_is_authorization "${header}"; then
        lib_die "No se puede usar Authorization simultáneamente para autenticar contra el EDR/Data Plane y contra la Ingesta API upstream. Hace falta proxy/backend, trust Data Plane-backend, header alternativo o credencial gestionada en infraestructura."
      fi
      curl_headers+=(-H "Authorization: Bearer ${INGESTA_API_BEARER_TOKEN}")
    fi

    if [[ "${PHASE4_HTTP_METHOD}" == "POST" ]]; then
      lib_die "POST phase4 no puede entrar en el bucle de candidatos de autenticación"
    fi

    set +e
    http_code="$(
      curl -sS -o "${attempt_file}" -w '%{http_code}' \
        -X GET "${EDR_URL}" \
        "${curl_headers[@]}"
    )"
    curl_exit=$?
    set -e
    printf '%s\n' "${http_code}" > "${base}.http"
    lib_log INFO "[phase4 data ${attempt_n}] label=${label} HTTP=${http_code} curl_exit=${curl_exit}"

    if _phase4_attempt_is_successful "${attempt_file}" "${http_code}" "${curl_exit}"; then
      cp "${attempt_file}" "${canonical_file}"
      cp "${base}.http" "${PHASE4_DIR}/40_data_response.http"
      _phase4_write_data_preview "${canonical_file}" "${PHASE4_DIR}/41_data_preview.json"

      PHASE4_AUTH_CANDIDATE_LABEL="${label}"
      selected=true
      success=1
    fi

    attempt_response_bytes=0
    if [[ "${PHASE4_HTTP_METHOD}" == "POST" ]]; then
      attempt_response_bytes="${data_bytes:-0}"
    elif [[ -f "${attempt_file}" ]]; then
      attempt_response_bytes="$(_phase4_file_bytes "${attempt_file}")"
    fi

    summary_lines+=("$(
      jq -nc \
        --argjson attempt "$((i + 1))" \
        --arg attempt_label "${label}" \
        --arg http_method "${PHASE4_HTTP_METHOD}" \
        --argjson http "$((http_code + 0))" \
        --argjson selected "$([[ "${selected}" == true ]] && echo true || echo false)" \
        --argjson response_bytes "${attempt_response_bytes}" \
        '{"attempt": $attempt, "label": $attempt_label, "http": $http, "selected": $selected}
        + (if $http_method == "POST" then {
            http_method: $http_method,
            response_bytes: $response_bytes,
            response_body_persisted: false
          } else {} end)'
    )")
    if (( success == 1 )); then
      break
    fi
  done

  attempts_json="$(jq -s '.' <<< "$(printf '%s\n' "${summary_lines[@]}")")"

  if (( success == 1 )); then
    data_http_val="$(tr -d '\n\r' < "${PHASE4_DIR}/40_data_response.http")"
    if [[ "${PHASE4_HTTP_METHOD}" == "POST" ]]; then
      jq -nc \
        --arg http_method "POST" \
        --arg media_type "${ASSET_MEDIA_TYPE}" \
        --arg response_media_type "${PHASE4_POST_RESPONSE_MEDIA_TYPE:-}" \
        --argjson data_http "${data_http_val}" \
        --argjson response_bytes "${PHASE4_POST_RESPONSE_BYTES:-0}" \
        --argjson request_body_bytes "${request_body_bytes}" \
        --argjson attempts "${attempts_json}" \
        '{
          http_method: $http_method,
          media_type: $media_type,
          response_media_type: $response_media_type,
          data_http: $data_http,
          response_bytes: $response_bytes,
          response_body_persisted: false,
          request_body_persisted: false,
          request_body_bytes: $request_body_bytes,
          download_persisted: false,
          attempts: $attempts
        }' > "${summary_tmp}"
    else
      data_bytes="$(_phase4_file_bytes "${canonical_file}")"
      jq -nc \
        --arg content_kind "${ASSET_CONTENT_KIND}" \
        --arg extension "${ASSET_EXTENSION}" \
        --arg media_type "${ASSET_MEDIA_TYPE}" \
        --arg data_response_file "phase4/$(_phase4_data_response_basename)" \
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
    fi
  else
    jq -nc \
      --arg http_method "${PHASE4_HTTP_METHOD}" \
      --argjson request_body_bytes "${request_body_bytes}" \
      --argjson attempts "${attempts_json}" \
      '{attempts: $attempts}
      + (if $http_method == "POST" then {
          http_method: $http_method,
          request_body_bytes: $request_body_bytes,
          response_body_persisted: false,
          request_body_persisted: false,
          download_persisted: false
        } else {} end)' \
      > "${summary_tmp}"
  fi

  mv "${summary_tmp}" "${summary_file}"

  if (( success == 1 )); then
    return 0
  fi

  lib_die "No se pudo consumir el endpoint EDR desde phase4. Revisar phase4/40_data_response_attempt_*.http y phase4/42_data_attempts_summary.json"
}

_phase4_validate_prerequisites() {
  local summary_file="${RUN_DIR}/summary.json"

  [[ -f "${summary_file}" ]] || lib_die "No existe ${summary_file}"

  jq -e '.phases.phase3.status == "ok"' "${summary_file}" >/dev/null \
    || lib_die "summary.json: phases.phase3.status != ok"

  lib_require_vars SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID
}

_phase4_write_manifest() {
  local dest="$1"
  local tmp="${dest}.$$"

  jq -n \
    --arg suffix "${SUFFIX}" \
    --arg asset_id "${ASSET_ID}" \
    --arg agreement_id "${AGREEMENT_ID}" \
    --arg transfer_id "${TRANSFER_ID}" \
    --arg edr_url "$(_phase4_safe_edr_url)" \
    --arg content_kind "${ASSET_CONTENT_KIND}" \
    --arg extension "${ASSET_EXTENSION}" \
    --arg media_type "${ASSET_MEDIA_TYPE}" \
    --arg source_artifact "evidencias/runs/${SUFFIX}/phase4/40_data_response.${ASSET_EXTENSION}" \
    --arg download_file "downloads/assets/${SAFE_ASSET_ID}/${SUFFIX}.${ASSET_EXTENSION}" \
    --arg latest_file "downloads/assets/${SAFE_ASSET_ID}/latest.${ASSET_EXTENSION}" \
    --arg manifest_file "downloads/manifests/${SAFE_ASSET_ID}/${SUFFIX}.manifest.json" \
    --arg latest_manifest "downloads/manifests/${SAFE_ASSET_ID}/latest.manifest.json" \
    --argjson bytes "${FILE_BYTES}" \
    --arg sha256 "${FILE_SHA256}" \
    --arg created_at "$(lib_now_iso)" \
    --arg phase3_status "ok" \
    --argjson data_http "${DATA_HTTP}" \
    --arg copy_action "${COPY_ACTION}" \
    --arg auth_candidate_label "${PHASE4_AUTH_CANDIDATE_LABEL}" \
    --argjson phase4_ingesta_auth "$([[ "${PHASE4_REQUIRES_INGESTA_API_AUTH:-0}" == "1" ]] && echo true || echo false)" \
    --argjson edr_url_redacted "$(_phase4_edr_url_has_sensitive_params "${EDR_URL:-}" && echo true || echo false)" \
    --arg http_method "${PHASE4_HTTP_METHOD}" \
    '{
      suffix: $suffix,
      asset_id: $asset_id,
      agreement_id: $agreement_id,
      transfer_id: $transfer_id,
      edr_url: $edr_url,
      edr_url_redacted: $edr_url_redacted,
      content_kind: $content_kind,
      extension: $extension,
      media_type: $media_type,
      source_artifact: $source_artifact,
      download_file: $download_file,
      latest_file: $latest_file,
      manifest_file: $manifest_file,
      latest_manifest: $latest_manifest,
      bytes: $bytes,
      sha256: $sha256,
      created_at: $created_at,
      phase3_status: $phase3_status,
      data_http: $data_http,
      copy_action: $copy_action,
      auth_candidate_label: $auth_candidate_label,
      phase4_ingesta_auth: $phase4_ingesta_auth
    }
    + (if $http_method == "POST" then {http_method: $http_method} else {} end)' > "${tmp}"

  mv "${tmp}" "${dest}"
}

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

# Allow unit tests to source helper functions without running the phase.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi

PHASE4_STEP="init"
api_find_root

if ! _phase4_id_is_set "${SUFFIX:-}" \
  || ! _phase4_id_is_set "${ASSET_ID:-}" \
  || ! _phase4_id_is_set "${AGREEMENT_ID:-}" \
  || ! _phase4_id_is_set "${TRANSFER_ID:-}"; then
  if [[ ! -f "$(lib_phase_env_path 3)" ]]; then
    lib_die "Ejecuta primero phase3_transfer_edr.sh"
  fi
  # shellcheck source=/dev/null
  source "$(lib_phase_env_path 3)"
fi

lib_load_env
lib_require_cmds
_phase4_require_sha256
lib_require_vars_group LIB_VARS_CONSUMER
lib_require_vars SUFFIX ASSET_ID AGREEMENT_ID TRANSFER_ID
_phase4_apply_asset_content_defaults
lib_init_run_dirs
lib_init_summary

PHASE4_DIR="${RUN_DIR}/phase4"
DOWNLOADS_DIR="${API_ROOT}/downloads"
mkdir -p "${PHASE4_DIR}" "${DOWNLOADS_DIR}"
export PHASE4_DIR DOWNLOADS_DIR

PHASE4_STEP="jwt_renew"
lib_renew_jwt consumer
lib_jwt_check_console consumer

PHASE4_STEP="jwt_claims"
lib_jwt_claims_to_json consumer "${PHASE4_DIR}/jwt_claims_consumer.json"
lib_write_summary 4 jwt_consumer ok '{"artifact":"phase4/jwt_claims_consumer.json"}'

# ---------------------------------------------------------------------------
# Validaciones + EDR runtime
# ---------------------------------------------------------------------------

PHASE4_STEP="validate"
_phase4_validate_prerequisites

PHASE4_STEP="edr_obtained"
_phase4_obtain_edr
[[ -n "${EDR_URL:-}" && "${EDR_URL}" != "null" ]] || lib_die "EDR_URL no quedó disponible en phase4"
lib_write_summary 4 edr_obtained ok \
  "$(jq -nc \
    --argjson http "${PHASE4_EDR_HTTP}" \
    --arg transfer_id "${TRANSFER_ID}" \
    --arg edr_url "$(_phase4_safe_edr_url)" \
    --arg source "${PHASE4_EDR_SOURCE}" \
    --arg artifact "phase4/30_edr_dataaddress_redacted.json" \
    --argjson edr_url_redacted "$(_phase4_edr_url_has_sensitive_params "${EDR_URL:-}" && echo true || echo false)" \
    '{http: $http, transfer_id: $transfer_id, edr_url: $edr_url, source: $source, artifact: $artifact, edr_url_redacted: $edr_url_redacted}')"

# ---------------------------------------------------------------------------
# Descarga efectiva
# ---------------------------------------------------------------------------

PHASE4_STEP="data_consumed"
_phase4_consume_data_with_auth_candidates

DATA_HTTP="$(tr -d '\n\r' < "${PHASE4_DIR}/40_data_response.http")"

if [[ "${PHASE4_HTTP_METHOD}" == "POST" ]]; then
  PHASE4_STEP="post_result"
  _phase4_finalize_post_metadata_only

  _phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/30_edr_dataaddress_redacted.json"
  _phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/30_edr_dataaddress_keys.json"
  _phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/31_edrs_request_body.json"
  _phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/31_edrs_request_redacted.json"
  _phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/42_data_attempts_summary.json"
  _phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/post_result.json"
  _phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/post_manifest.json"

  PHASE4_STEP="export_summary"
  lib_write_summary 4 post_result ok \
    "$(jq -nc \
      --arg operation "POST" \
      --arg auth_candidate_label "${PHASE4_AUTH_CANDIDATE_LABEL}" \
      --arg response_media_type "${PHASE4_POST_RESPONSE_MEDIA_TYPE:-}" \
      --arg manifest "phase4/post_manifest.json" \
      --arg result_artifact "phase4/post_result.json" \
      --argjson http_status "${DATA_HTTP}" \
      --argjson response_bytes "${PHASE4_POST_RESPONSE_BYTES:-0}" \
      --argjson request_body_bytes "${PHASE4_POST_REQUEST_BODY_BYTES:-0}" \
      '{
        operation: $operation,
        http_method: "POST",
        http_status: $http_status,
        response_bytes: $response_bytes,
        response_media_type: $response_media_type,
        response_body_persisted: false,
        request_body_persisted: false,
        request_body_bytes: $request_body_bytes,
        download_persisted: false,
        auth_candidate_label: $auth_candidate_label,
        manifest: $manifest,
        result_artifact: $result_artifact,
        status: "ok"
      }')"

  _phase4_assert_no_sensitive_control_artifact "${RUN_DIR}/summary.json"
  lib_set_phase_status 4 ok

  trap - ERR
  _phase4_cleanup
  lib_log INFO "Fase 4 OK — POST metadata-only http=${DATA_HTTP} response_bytes=${PHASE4_POST_RESPONSE_BYTES:-0} response_body_persisted=false"
  exit 0
fi

SOURCE_DATA_FILE="${PHASE4_DATA_RESPONSE_FILE}"

SAFE_ASSET_ID="$(_phase4_sanitize_asset_id "${ASSET_ID}")"
ASSET_DOWNLOAD_DIR="${DOWNLOADS_DIR}/assets/${SAFE_ASSET_ID}"
MANIFEST_DOWNLOAD_DIR="${DOWNLOADS_DIR}/manifests/${SAFE_ASSET_ID}"

mkdir -p "${ASSET_DOWNLOAD_DIR}" "${MANIFEST_DOWNLOAD_DIR}"
export ASSET_DOWNLOAD_DIR MANIFEST_DOWNLOAD_DIR

DOWNLOAD_FILE="${ASSET_DOWNLOAD_DIR}/${SUFFIX}.${ASSET_EXTENSION}"
LATEST_FILE="${ASSET_DOWNLOAD_DIR}/latest.${ASSET_EXTENSION}"

MANIFEST_FILE="${MANIFEST_DOWNLOAD_DIR}/${SUFFIX}.manifest.json"
LATEST_MANIFEST="${MANIFEST_DOWNLOAD_DIR}/latest.manifest.json"

SOURCE_SHA256="$(_phase4_sha256_file "${SOURCE_DATA_FILE}")"

if [[ ! -f "${DOWNLOAD_FILE}" ]]; then
  COPY_ACTION="created"
elif [[ "$(_phase4_sha256_file "${DOWNLOAD_FILE}")" == "${SOURCE_SHA256}" ]]; then
  COPY_ACTION="already_exists_same_hash"
  lib_log INFO "Destino ya existe con mismo SHA256; no se sobrescribe ${DOWNLOAD_FILE}"
else
  if [[ "${DOWNLOAD_FORCE:-}" != "1" ]]; then
    lib_die "Destino ${DOWNLOAD_FILE} existe con contenido distinto. Export DOWNLOAD_FORCE=1 para sobrescribir."
  fi
  COPY_ACTION="overwritten"
fi

PHASE4_STEP="save_download"
if [[ "${COPY_ACTION}" != "already_exists_same_hash" ]]; then
  _phase4_atomic_copy "${SOURCE_DATA_FILE}" "${DOWNLOAD_FILE}"
fi

_phase4_atomic_copy "${DOWNLOAD_FILE}" "${LATEST_FILE}"

FILE_SHA256="$(_phase4_sha256_file "${DOWNLOAD_FILE}")"
FILE_BYTES="$(_phase4_file_bytes "${DOWNLOAD_FILE}")"

# ---------------------------------------------------------------------------
# Manifests
# ---------------------------------------------------------------------------

PHASE4_STEP="write_manifest"
_phase4_write_manifest "${MANIFEST_FILE}"
_phase4_write_manifest "${LATEST_MANIFEST}"
_phase4_write_manifest "${PHASE4_DIR}/download_manifest.json"
_phase4_write_manifest "${PHASE4_DIR}/download_summary.json"

_phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/30_edr_dataaddress_redacted.json"
_phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/30_edr_dataaddress_keys.json"
_phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/31_edrs_request_body.json"
_phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/31_edrs_request_redacted.json"
_phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/42_data_attempts_summary.json"
_phase4_assert_no_sensitive_control_artifact "${MANIFEST_FILE}"
_phase4_assert_no_sensitive_control_artifact "${LATEST_MANIFEST}"
_phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/download_manifest.json"
_phase4_assert_no_sensitive_control_artifact "${PHASE4_DIR}/download_summary.json"

# ---------------------------------------------------------------------------
# Cierre
# ---------------------------------------------------------------------------

PHASE4_STEP="export_summary"
lib_write_summary 4 save_download ok \
  "$(jq -nc \
    --arg download_file "downloads/assets/${SAFE_ASSET_ID}/${SUFFIX}.${ASSET_EXTENSION}" \
    --arg latest_file "downloads/assets/${SAFE_ASSET_ID}/latest.${ASSET_EXTENSION}" \
    --arg manifest_file "downloads/manifests/${SAFE_ASSET_ID}/${SUFFIX}.manifest.json" \
    --arg latest_manifest "downloads/manifests/${SAFE_ASSET_ID}/latest.manifest.json" \
    --arg content_kind "${ASSET_CONTENT_KIND}" \
    --arg extension "${ASSET_EXTENSION}" \
    --arg media_type "${ASSET_MEDIA_TYPE}" \
    --arg sha256 "${FILE_SHA256}" \
    --arg copy_action "${COPY_ACTION}" \
    --arg auth_candidate_label "${PHASE4_AUTH_CANDIDATE_LABEL}" \
    --argjson bytes "${FILE_BYTES}" \
    --argjson data_http "${DATA_HTTP}" \
    --argjson phase4_ingesta_auth "$([[ "${PHASE4_REQUIRES_INGESTA_API_AUTH:-0}" == "1" ]] && echo true || echo false)" \
    '{
      download_file: $download_file,
      latest_file: $latest_file,
      manifest: "phase4/download_manifest.json",
      manifest_file: $manifest_file,
      latest_manifest: $latest_manifest,
      content_kind: $content_kind,
      extension: $extension,
      media_type: $media_type,
      sha256: $sha256,
      copy_action: $copy_action,
      bytes: $bytes,
      data_http: $data_http,
      auth_candidate_label: $auth_candidate_label,
      phase4_ingesta_auth: $phase4_ingesta_auth
    }')"

_phase4_assert_no_sensitive_control_artifact "${RUN_DIR}/summary.json"
lib_set_phase_status 4 ok

trap - ERR
_phase4_cleanup
lib_log INFO "Fase 4 OK — download_file=downloads/assets/${SAFE_ASSET_ID}/latest.${ASSET_EXTENSION} sha256=${FILE_SHA256}"
