#!/usr/bin/env bash
# lib_common.sh — Librería compartida para automatización API IPPCP.
# No ejecuta llamadas al dataspace al sourcearse; los scripts de fase invocan
# explícitamente las funciones que necesiten.

_LIB_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_ROOT="$(cd "${_LIB_COMMON_DIR}/.." && pwd)"

# Comprobación Bash 4.3+ (declare -A, ${var^^}, local -n / nameref en lib_require_vars_group).
_lib_die_raw() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

if [[ -z "${BASH_VERSION:-}" ]]; then
  _lib_die_raw "Se requiere Bash 4.3+. Ejecuta con 'bash scripts/...' (no sh). En macOS: brew install bash"
fi
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
  _lib_die_raw "Se requiere Bash 4.3+ por nameref (local -n) y declare -A (actual: ${BASH_VERSION}). En macOS el bash por defecto es 3.2; instala uno moderno: brew install bash"
fi

lib_require_bash4() {
  : # ya validado al sourcear; función disponible para scripts que re-sourceen
}

# Modo estricto: exit 1 en HTTP != 2xx (default 1).
: "${LIB_STRICT:=1}"

# Grupos de variables obligatorias (usados por lib_require_vars_group).
LIB_VARS_DATASPACE=(DS_NAME DS_DOMAIN KEYCLOAK_URL KC_CLIENT SUFFIX)
LIB_VARS_PROVIDER=(PROVIDER PROVIDER_BASE PROVIDER_PROTOCOL PROVIDER_USER PROVIDER_PASSWORD)
LIB_VARS_CONSUMER=(CONSUMER CONSUMER_BASE CONSUMER_PROTOCOL CONSUMER_USER CONSUMER_PASSWORD)
LIB_VARS_PHASE1=(VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID ASSET_ID CD_ID)
LIB_VARS_PHASE2=(PROVIDER_PARTICIPANT_ID OFFER_POLICY_ID CATALOG_ASSET_ID NEG_ID AGREEMENT_ID)
LIB_VARS_PHASE3=(AGREEMENT_ID ASSET_ID TRANSFER_ID)

# ---------------------------------------------------------------------------
# Logging y utilidades
# ---------------------------------------------------------------------------

lib_log() {
  local level="${1^^}"
  shift
  printf '[%s] %s\n' "${level}" "$*" >&2
}

lib_die() {
  lib_log ERROR "$*"
  exit 1
}

lib_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S"
}

lib_now_epoch() {
  date +%s
}

# ---------------------------------------------------------------------------
# Localizar raíz API
# ---------------------------------------------------------------------------

_lib_has_api_markers() {
  local dir="$1"
  [[ -f "${dir}/endpoints.sh" && -f "${dir}/export_suffix.sh" && -f "${dir}/scripts/lib_common.sh" ]]
}

api_find_root() {
  if _lib_has_api_markers "${API_ROOT}"; then
    export API_ROOT
    return 0
  fi

  local search_dir="${PWD}"
  local i
  for (( i = 0; i < 5; i++ )); do
    if _lib_has_api_markers "${search_dir}"; then
      API_ROOT="${search_dir}"
      export API_ROOT
      return 0
    fi
    if [[ "${search_dir}" == "/" ]]; then
      break
    fi
    search_dir="$(dirname "${search_dir}")"
  done

  lib_die "No se encontró la raíz API (marcadores: endpoints.sh, export_suffix.sh, scripts/lib_common.sh). API_ROOT esperado cerca de ${API_ROOT}"
}

# ---------------------------------------------------------------------------
# Dependencias externas
# ---------------------------------------------------------------------------

lib_require_cmds() {
  command -v curl >/dev/null 2>&1 || lib_die "curl no encontrado en PATH"
  command -v jq   >/dev/null 2>&1 || lib_die "jq no encontrado en PATH"
  if ! command -v python3 >/dev/null 2>&1; then
    lib_log WARN "python3 no encontrado; decodificación JWT usará fallback bash (menos robusto)"
  fi
}

lib_require_vars() {
  local name
  for name in "$@"; do
    if [[ -z "${!name+x}" ]] || [[ -z "${!name}" ]]; then
      lib_die "Variable obligatoria no definida o vacía: ${name} (¿source export_*.sh / phaseN_env.sh?)"
    fi
  done
}

# Identificadores verificados en esta ejecución para un asset ya publicado.
# No basta con IPPCP_PHASE1_REUSE_EXISTING: hace falta el marcador escrito
# tras la verificación, ligado al SUFFIX y al ASSET_ID actuales.
_lib_phase1_reuse_ids_are_current() {
  [[ "${IPPCP_PHASE1_REUSE_EXISTING:-0}" == "1" ]] \
    && [[ "${PHASE1_ASSET_ORIGIN:-}" == "verified_existing" ]] \
    && [[ "${PHASE1_REUSE_IDS_VERIFIED:-0}" == "1" ]] \
    && [[ -n "${SUFFIX:-}" && "${PHASE1_REUSE_SUFFIX:-}" == "${SUFFIX}" ]] \
    && [[ -n "${ASSET_ID:-}" && "${PHASE1_REUSE_ASSET_ID:-}" == "${ASSET_ID}" ]] \
    && [[ -n "${CD_ID:-}" && -n "${ACCESS_POLICY_ID:-}" && -n "${CONTRACT_POLICY_ID:-}" ]]
}

lib_require_vars_group() {
  local group_name="$1"
  local -n _group="${group_name}"
  # El asset ya publicado no crea vocabulario en esta ejecución. La negociación
  # usa la oferta del catálogo; VOCAB_ID no forma parte de ese contrato.
  if [[ "${group_name}" == "LIB_VARS_PHASE1" ]] && _lib_phase1_reuse_ids_are_current; then
    lib_require_vars ACCESS_POLICY_ID CONTRACT_POLICY_ID ASSET_ID CD_ID
    return 0
  fi
  lib_require_vars "${_group[@]}"
}

# ---------------------------------------------------------------------------
# Carga de entorno del taller
# ---------------------------------------------------------------------------

lib_resolve_flow_dir() {
  IPPCP_FLOW="${IPPCP_FLOW:-ingesta}"

  if [[ -z "${IPPCP_FLOW_DIR:-}" ]]; then
    if [[ -n "${IPPCP_DATASPACE_DIR:-}" && -n "${IPPCP_FLOW_VERSION:-}" && -d "${IPPCP_DATASPACE_DIR}/${IPPCP_FLOW_VERSION}/${IPPCP_FLOW}" ]]; then
      IPPCP_FLOW_DIR="${IPPCP_DATASPACE_DIR}/${IPPCP_FLOW_VERSION}/${IPPCP_FLOW}"
    elif [[ -n "${IPPCP_DATASPACE_DIR:-}" && -d "${IPPCP_DATASPACE_DIR}/${IPPCP_FLOW}" ]]; then
      IPPCP_FLOW_DIR="${IPPCP_DATASPACE_DIR}/${IPPCP_FLOW}"
    else
      IPPCP_FLOW_DIR="${API_ROOT}/flujos/${IPPCP_FLOW}"
    fi
  fi

  export IPPCP_FLOW IPPCP_FLOW_DIR
}

lib_resolve_dataspace_file() {
  local inferred_dataspace_dir inferred_dataspace_parent dataspace_file

  if [[ -n "${IPPCP_FLOW_DIR:-}" ]]; then
    inferred_dataspace_dir="$(dirname "${IPPCP_FLOW_DIR}")"
    inferred_dataspace_parent="$(dirname "${inferred_dataspace_dir}")"
  else
    inferred_dataspace_dir=""
    inferred_dataspace_parent=""
  fi

  if [[ -n "${IPPCP_DATASPACE_FILE:-}" ]]; then
    dataspace_file="${IPPCP_DATASPACE_FILE}"
  elif [[ -n "${IPPCP_DATASPACE_DIR:-}" ]]; then
    dataspace_file="${IPPCP_DATASPACE_DIR}/export_dataspace.sh"
  elif [[ -n "${IPPCP_DATASPACE:-}" ]]; then
    dataspace_file="${API_ROOT}/flujos/${IPPCP_DATASPACE}/export_dataspace.sh"
    IPPCP_DATASPACE_DIR="${API_ROOT}/flujos/${IPPCP_DATASPACE}"
  elif [[ -n "${inferred_dataspace_dir}" && -f "${inferred_dataspace_dir}/export_dataspace.sh" ]]; then
    dataspace_file="${inferred_dataspace_dir}/export_dataspace.sh"
    IPPCP_DATASPACE_DIR="${inferred_dataspace_dir}"
  elif [[ -n "${inferred_dataspace_parent}" && -f "${inferred_dataspace_parent}/export_dataspace.sh" ]]; then
    dataspace_file="${inferred_dataspace_parent}/export_dataspace.sh"
    IPPCP_DATASPACE_DIR="${inferred_dataspace_parent}"
  else
    lib_die "Unable to resolve dataspace. Set IPPCP_DATASPACE=ippcp (recommended) or define IPPCP_DATASPACE_DIR/IPPCP_DATASPACE_FILE explicitly."
  fi

  [[ -f "${dataspace_file}" ]] || lib_die "Missing dataspace export: ${dataspace_file}"

  IPPCP_DATASPACE_FILE="${dataspace_file}"
  export IPPCP_DATASPACE_DIR IPPCP_DATASPACE_FILE
}

lib_apply_credential_aliases() {
  if [[ -n "${PROVIDER_USERNAME:-}" && -z "${PROVIDER_USER:-}" ]]; then
    export PROVIDER_USER="${PROVIDER_USERNAME}"
  fi
  if [[ -n "${CONSUMER_USERNAME:-}" && -z "${CONSUMER_USER:-}" ]]; then
    export CONSUMER_USER="${CONSUMER_USERNAME}"
  fi
}

lib_load_flow_exports() {
  lib_resolve_flow_dir

  local export_provider="${IPPCP_FLOW_DIR}/export_provider.sh"
  local export_consumer="${IPPCP_FLOW_DIR}/export_consumer.sh"
  local user_provider="${IPPCP_FLOW_DIR}/user_provider.sh"
  local user_consumer="${IPPCP_FLOW_DIR}/user_consumer.sh"

  [[ -f "${export_provider}" ]] || lib_die "Missing flow export: ${export_provider}"
  [[ -f "${export_consumer}" ]] || lib_die "Missing flow export: ${export_consumer}"

  # shellcheck source=/dev/null
  source "${export_provider}"
  # shellcheck source=/dev/null
  source "${export_consumer}"

  if [[ ! -f "${user_provider}" ]]; then
    lib_die "Missing local credentials file: ${IPPCP_FLOW_DIR}/user_provider.sh
Copy user_provider.example.sh to user_provider.sh and fill credentials."
  fi
  if [[ ! -f "${user_consumer}" ]]; then
    lib_die "Missing local credentials file: ${IPPCP_FLOW_DIR}/user_consumer.sh
Copy user_consumer.example.sh to user_consumer.sh and fill credentials."
  fi

  # shellcheck source=/dev/null
  source "${user_provider}"
  # shellcheck source=/dev/null
  source "${user_consumer}"
  lib_apply_credential_aliases
}

lib_load_env() {
  api_find_root
  lib_resolve_dataspace_file
  # shellcheck source=/dev/null
  source "${IPPCP_DATASPACE_FILE}"
  lib_load_flow_exports

  # endpoints.sh declara ENDPOINTS con alcance local si se sourcea dentro de esta función.
  # unset ENDPOINTS aquí corrompe el array global en bash; serializamos en subshell y
  # reconstruimos ENDPOINTS global en el shell actual (mismo efecto que copiar local → global).
  local _endpoint_key _endpoint_path _restore_u=0

  if [[ $- == *u* ]]; then
    _restore_u=1
    set +u
  fi

  declare -gA ENDPOINTS=()

  while IFS=$'\t' read -r _endpoint_key _endpoint_path; do
    [[ -n "${_endpoint_key}" ]] || continue
    ENDPOINTS["${_endpoint_key}"]="${_endpoint_path}"
  done < <(
    # shellcheck source=/dev/null
    source "${API_ROOT}/endpoints.sh"
    for _endpoint_key in "${!ENDPOINTS[@]}"; do
      printf '%s\t%s\n' "${_endpoint_key}" "${ENDPOINTS[${_endpoint_key}]}"
    done
  )

  if (( _restore_u )); then
    set -u
  fi

  [[ -n "${ENDPOINTS[asset]:-}" ]] || lib_die "ENDPOINTS[asset] no definido tras cargar endpoints.sh"
  [[ -n "${ENDPOINTS[policyDefinition]:-}" ]] || lib_die "ENDPOINTS[policyDefinition] no definido tras cargar endpoints.sh"
  [[ -n "${ENDPOINTS[contractDefinition]:-}" ]] || lib_die "ENDPOINTS[contractDefinition] no definido tras cargar endpoints.sh"
  [[ -n "${ENDPOINTS[transferProcess]:-}" ]] || lib_die "ENDPOINTS[transferProcess] no definido tras cargar endpoints.sh"

  if [[ -z "${SUFFIX:-}" ]]; then
    # shellcheck source=/dev/null
    source "${API_ROOT}/export_suffix.sh"
  else
    lib_log INFO "Reutilizando SUFFIX existente: ${SUFFIX}"
  fi
}

lib_derive_phase1_ids() {
  lib_require_vars SUFFIX

  if _lib_phase1_reuse_ids_are_current; then
    export ACCESS_POLICY_ID CONTRACT_POLICY_ID ASSET_ID CD_ID
    if [[ -n "${VOCAB_ID:-}" ]]; then
      export VOCAB_ID
    fi
    return 0
  fi

  # Modo opt-in aún no verificado: no inventar cd-${SUFFIX} ni conservar
  # un CD_ID de runtime/env/latest o de una ejecución anterior.
  if [[ "${IPPCP_PHASE1_REUSE_EXISTING:-0}" == "1" ]]; then
    if [[ "${ASSET_ID_CUSTOM:-0}" != "1" || -z "${ASSET_ID:-}" ]]; then
      lib_die "IPPCP_PHASE1_REUSE_EXISTING requiere ASSET_ID estable cargado desde ASSET_CONFIG"
    fi
    unset CD_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID VOCAB_ID || true
    unset PHASE1_REUSE_IDS_VERIFIED PHASE1_REUSE_SUFFIX PHASE1_REUSE_ASSET_ID || true
    if [[ "${PHASE1_ASSET_ORIGIN:-}" == "verified_existing" ]]; then
      unset PHASE1_ASSET_ORIGIN || true
    fi
    export ASSET_ID
    return 0
  fi

  export VOCAB_ID="vocab-${SUFFIX}"
  export ACCESS_POLICY_ID="access-${SUFFIX}"
  export CONTRACT_POLICY_ID="contract-${SUFFIX}"

  if [[ "${ASSET_ID_CUSTOM:-0}" == "1" && -n "${ASSET_ID:-}" ]]; then
    export ASSET_ID
  else
    export ASSET_ID="asset-${SUFFIX}"
  fi

  export CD_ID="cd-${SUFFIX}"
}

# ---------------------------------------------------------------------------
# Directorios de evidencias por ejecución
# ---------------------------------------------------------------------------

lib_init_run_dirs() {
  lib_require_vars SUFFIX
  RUN_DIR="${API_ROOT}/evidencias/runs/${SUFFIX}"
  PHASE0_DIR="${RUN_DIR}/phase0"
  PHASE1_DIR="${RUN_DIR}/phase1"
  PHASE1B_DIR="${RUN_DIR}/phase1b"
  PHASE2_DIR="${RUN_DIR}/phase2"
  PHASE3_DIR="${RUN_DIR}/phase3"
  PHASE3B_DIR="${RUN_DIR}/phase3b"
  PHASE4_DIR="${RUN_DIR}/phase4"
  PHASE4B_DIR="${RUN_DIR}/phase4b"
  export RUN_DIR PHASE0_DIR PHASE1_DIR PHASE1B_DIR PHASE2_DIR PHASE3_DIR PHASE3B_DIR PHASE4_DIR PHASE4B_DIR
  mkdir -p "${PHASE0_DIR}" "${PHASE1_DIR}" "${PHASE1B_DIR}" "${PHASE2_DIR}" \
    "${PHASE3_DIR}" "${PHASE3B_DIR}" "${PHASE4_DIR}" "${PHASE4B_DIR}"
}

lib_phase_dir() {
  local phase="$1"
  case "${phase}" in
    0) printf '%s' "${PHASE0_DIR}" ;;
    1) printf '%s' "${PHASE1_DIR}" ;;
    1b) printf '%s' "${PHASE1B_DIR}" ;;
    2) printf '%s' "${PHASE2_DIR}" ;;
    3) printf '%s' "${PHASE3_DIR}" ;;
    3b) printf '%s' "${PHASE3B_DIR}" ;;
    4) printf '%s' "${PHASE4_DIR}" ;;
    4b) printf '%s' "${PHASE4B_DIR}" ;;
    *) lib_die "Fase inválida: ${phase} (esperado 0-4, 1b, 3b, 4b)" ;;
  esac
}

lib_artifact_base() {
  local phase_dir="$1"
  local step_name="$2"
  printf '%s/%s' "${phase_dir}" "${step_name}"
}

# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------

lib_is_json_file() {
  local json_file="$1"
  [[ -f "${json_file}" ]] || return 1
  [[ -s "${json_file}" ]] || return 1
  jq empty "${json_file}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# JWT — renovación (mismo flujo que Notion; no persiste tokens en evidencias)
# ---------------------------------------------------------------------------

lib_fetch_jwt() {
  local role="$1"
  local user_var password_var jwt_var token_url

  case "${role}" in
    provider)
      user_var=PROVIDER_USER
      password_var=PROVIDER_PASSWORD
      jwt_var=PROVIDER_JWT
      ;;
    consumer)
      user_var=CONSUMER_USER
      password_var=CONSUMER_PASSWORD
      jwt_var=CONSUMER_JWT
      ;;
    *)
      lib_die "Rol JWT inválido: ${role} (esperado provider|consumer)"
      ;;
  esac

  lib_require_vars KEYCLOAK_URL DS_NAME KC_CLIENT "${user_var}" "${password_var}"

  token_url="${KEYCLOAK_URL}/realms/${DS_NAME}/protocol/openid-connect/token"

  # shellcheck disable=SC2154
  local access_token
  access_token="$(
    curl -sS -X POST "${token_url}" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=password" \
      -d "client_id=${KC_CLIENT}" \
      -d "username=${!user_var}" \
      -d "password=${!password_var}" \
      -d "scope=openid profile email" \
      | jq -r '.access_token // empty'
  )"

  if [[ -z "${access_token}" || "${access_token}" == "null" ]]; then
    lib_die "No se pudo obtener JWT para ${role} (Keycloak devolvió token vacío o null)"
  fi

  printf -v "${jwt_var}" '%s' "${access_token}"
  export "${jwt_var?}"
}

lib_renew_jwt() {
  local target="${1:-both}"
  case "${target}" in
    provider)
      lib_fetch_jwt provider
      ;;
    consumer)
      lib_fetch_jwt consumer
      ;;
    both)
      lib_fetch_jwt provider
      lib_fetch_jwt consumer
      ;;
    *)
      lib_die "lib_renew_jwt: argumento inválido '${target}' (esperado provider|consumer|both)"
      ;;
  esac
}

lib_jwt_check_console() {
  local role jwt_var jwt min_len=100

  for role in "$@"; do
    case "${role}" in
      provider) jwt_var=PROVIDER_JWT ;;
      consumer) jwt_var=CONSUMER_JWT ;;
      *)
        lib_die "lib_jwt_check_console: rol inválido '${role}'"
        ;;
    esac
    jwt="${!jwt_var:-}"
    if [[ -z "${jwt}" || "${jwt}" == "null" ]]; then
      lib_die "JWT vacío o null para ${role}"
    fi
    if (( ${#jwt} < min_len )); then
      lib_die "JWT demasiado corto para ${role} (length=${#jwt}, mínimo=${min_len})"
    fi
    lib_log INFO "${role} JWT length: ${#jwt}"
  done
}

# Placeholder for diagnostic and publication-oriented artifacts.
# The operational endpoint stays in the process environment and in the
# private, Git-ignored phase*_env.sh file.
lib_diagnostic_edr_endpoint() {
  local value="${1:-}"
  if [[ -n "${value}" && "${value}" != "null" ]]; then
    printf '%s' '<redacted-edr-endpoint>'
  fi
}

lib_edr_endpoint_redacted_json() {
  local value="${1:-}"
  if [[ -n "${value}" && "${value}" != "null" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

_lib_jwt_decode_claims() {
  # stdout: JSON con iat, exp, now (epoch). Sin token.
  local token="$1"
  local role="$2"
  local payload part padded decoded

  part="${token#*.}"
  part="${part%%.*}"
  if [[ -z "${part}" ]]; then
    lib_die "JWT malformado para ${role}: no se pudo extraer payload"
  fi

  padded="${part}"
  case $(( ${#padded} % 4 )) in
    2) padded="${padded}==" ;;
    3) padded="${padded}=" ;;
  esac

  if command -v python3 >/dev/null 2>&1; then
    python3 - "${role}" "${padded}" "${#token}" <<'PY'
import base64, json, sys, time
role = sys.argv[1]
padded = sys.argv[2]
token_length = int(sys.argv[3])
raw = padded.replace("-", "+").replace("_", "/")
data = json.loads(base64.b64decode(raw + "=" * (-len(raw) % 4)))
print(json.dumps({
    "role": role,
    "iat": data.get("iat"),
    "exp": data.get("exp"),
    "now": int(time.time()),
    "token_length": token_length,
}, separators=(",", ":")))
PY
    return 0
  fi

  # Fallback bash + base64 (macOS base64 puede requerir -D)
  decoded=""
  if decoded="$(printf '%s' "${padded}" | tr '_-' '/+' | base64 -d 2>/dev/null)"; then
    :
  elif decoded="$(printf '%s' "${padded}" | tr '_-' '/+' | base64 -D 2>/dev/null)"; then
    :
  else
    lib_die "No se pudo decodificar JWT para ${role} (instala python3 o verifica base64)"
  fi

  local iat exp now
  now="$(lib_now_epoch)"
  printf '%s' "${decoded}" | jq \
    --arg role "${role}" \
    --argjson now "${now}" \
    --argjson token_length "${#token}" \
    '{role: $role, iat: .iat, exp: .exp, now: $now, token_length: $token_length}'
}

lib_jwt_claims_to_json() {
  local role="$1"
  local output_file="$2"
  local jwt_var jwt

  case "${role}" in
    provider) jwt_var=PROVIDER_JWT ;;
    consumer) jwt_var=CONSUMER_JWT ;;
    *) lib_die "lib_jwt_claims_to_json: rol inválido '${role}'" ;;
  esac

  jwt="${!jwt_var:-}"
  lib_require_vars "${jwt_var}"

  local claims_json
  claims_json="$(_lib_jwt_decode_claims "${jwt}" "${role}")"

  local tmp="${output_file}.$$"
  printf '%s\n' "${claims_json}" > "${tmp}"
  mv "${tmp}" "${output_file}"
}

# ---------------------------------------------------------------------------
# curl wrapper — body .json, status .http (nunca mezclar HTTP en el JSON)
# ---------------------------------------------------------------------------

lib_curl_json() {
  local artifact_base="$1"
  shift

  local allow_empty_body=0
  if [[ "${1:-}" == "--allow-empty-body" ]]; then
    allow_empty_body=1
    shift
  fi

  if [[ $# -lt 1 ]]; then
    lib_die "lib_curl_json: faltan argumentos curl tras artifact_base"
  fi

  local http_code curl_exit
  set +e
  http_code="$(curl -sS -o "${artifact_base}.json" -w '%{http_code}' "$@")"
  curl_exit=$?
  set -e

  if (( curl_exit != 0 )); then
    lib_log ERROR "curl falló (exit ${curl_exit}) — ver ${artifact_base}.json"
    return "${curl_exit}"
  fi

  printf '%s\n' "${http_code}" > "${artifact_base}.http"

  if [[ ! "${http_code}" =~ ^2[0-9]{2}$ ]]; then
    lib_log ERROR "HTTP ${http_code} — body: ${artifact_base}.json — status: ${artifact_base}.http"
    if [[ "${LIB_STRICT}" == "1" ]]; then
      return 1
    fi
    return 0
  fi

  # 204 No Content o body vacío permitido con --allow-empty-body
  if [[ "${http_code}" == "204" ]] || [[ ! -s "${artifact_base}.json" ]]; then
    if (( allow_empty_body == 1 )); then
      : > "${artifact_base}.json"
      return 0
    fi
    lib_log ERROR "Respuesta vacía inesperada (HTTP ${http_code}) — ${artifact_base}.json"
    if [[ "${LIB_STRICT}" == "1" ]]; then
      return 1
    fi
    return 0
  fi

  if ! lib_is_json_file "${artifact_base}.json"; then
    lib_log ERROR "Body no es JSON válido — ${artifact_base}.json (¿HTML 401/502?)"
    if [[ "${LIB_STRICT}" == "1" ]]; then
      return 1
    fi
  fi

  return 0
}

# Guarda body en ${artifact_base}.body y HTTP en ${artifact_base}.http (multipart u otro).
# No valida JSON; usar lib_curl_json cuando la respuesta deba ser JSON.
lib_curl_save() {
  local artifact_base="$1"
  shift

  if [[ $# -lt 1 ]]; then
    lib_die "lib_curl_save: faltan argumentos curl tras artifact_base"
  fi

  local http_code curl_exit
  set +e
  http_code="$(curl -sS -o "${artifact_base}.body" -w '%{http_code}' "$@")"
  curl_exit=$?
  set -e

  if (( curl_exit != 0 )); then
    lib_log ERROR "curl falló (exit ${curl_exit}) — ver ${artifact_base}.body"
    return "${curl_exit}"
  fi

  printf '%s\n' "${http_code}" > "${artifact_base}.http"

  if [[ ! "${http_code}" =~ ^2[0-9]{2}$ ]]; then
    lib_log ERROR "HTTP ${http_code} — body: ${artifact_base}.body — status: ${artifact_base}.http"
    if [[ "${LIB_STRICT:-}" == "1" ]]; then
      return 1
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# summary.json — merge atómico (tmp + mv)
# ---------------------------------------------------------------------------

lib_init_summary() {
  lib_require_vars SUFFIX
  if [[ -z "${RUN_DIR:-}" ]]; then
    lib_init_run_dirs
  fi

  local summary_file="${RUN_DIR}/summary.json"
  if [[ -f "${summary_file}" ]]; then
    return 0
  fi

  local tmp="${summary_file}.$$"
  local ds="${DS_NAME:-}"
  jq -n \
    --arg suffix "${SUFFIX}" \
    --arg ds_name "${ds}" \
    --arg started_at "$(lib_now_iso)" \
    '{
      suffix: $suffix,
      ds_name: $ds_name,
      started_at: $started_at,
      phases: {}
    }' > "${tmp}" || lib_die "lib_init_summary: no se pudo crear summary.json inicial"

  mv "${tmp}" "${summary_file}"
}

lib_write_summary() {
  local phase="$1"
  local step_id="$2"
  local status="$3"
  # Default JSON vacío: "${4-"{}"}" (no usar ${4:-{}} — bash interpreta mal las llaves)
  local metadata_json="${4-"{}"}"

  lib_init_summary
  local summary_file="${RUN_DIR}/summary.json"
  local phase_key="phase${phase}"
  local tmp="${summary_file}.$$"
  local ts
  ts="$(lib_now_iso)"

  if ! jq -e . >/dev/null 2>&1 <<< "${metadata_json}"; then
    lib_die "lib_write_summary: metadata_json no es JSON válido para step '${step_id}'"
  fi

  if ! jq \
    --arg phase_key "${phase_key}" \
    --arg step_id "${step_id}" \
    --arg status "${status}" \
    --arg ts "${ts}" \
    --argjson meta "${metadata_json}" \
    '
      .phases[$phase_key] = (.phases[$phase_key] // {status: "in_progress", steps: []}) |
      .phases[$phase_key].steps += [{
        id: $step_id,
        status: $status,
        ts: $ts
      } + $meta]
    ' \
    "${summary_file}" > "${tmp}"; then
    rm -f "${tmp}"
    lib_die "lib_write_summary: merge jq falló para step '${step_id}' en ${summary_file}"
  fi

  mv "${tmp}" "${summary_file}"
}

lib_set_phase_status() {
  local phase="$1"
  local status="$2"
  lib_init_summary
  local summary_file="${RUN_DIR}/summary.json"
  local phase_key="phase${phase}"
  local tmp="${summary_file}.$$"

  if ! jq \
    --arg phase_key "${phase_key}" \
    --arg status "${status}" \
    '.phases[$phase_key] = (.phases[$phase_key] // {steps: []}) | .phases[$phase_key].status = $status' \
    "${summary_file}" > "${tmp}"; then
    rm -f "${tmp}"
    lib_die "lib_set_phase_status: merge jq falló para ${phase_key}"
  fi

  mv "${tmp}" "${summary_file}"
}

# ---------------------------------------------------------------------------
# Exportación phaseN_env.sh (run dir + runtime/env/latest con backup por SUFFIX)
# ---------------------------------------------------------------------------

lib_env_dir() {
  if [[ -n "${IPPCP_ENV_DIR:-}" ]]; then
    printf '%s' "${IPPCP_ENV_DIR}"
  else
    printf '%s/runtime/env/latest' "${API_ROOT}"
  fi
}

lib_env_backup_dir() {
  if [[ -n "${IPPCP_ENV_BACKUP_DIR:-}" ]]; then
    printf '%s' "${IPPCP_ENV_BACKUP_DIR}"
  else
    printf '%s/runtime/env/backups' "${API_ROOT}"
  fi
}

lib_init_env_dirs() {
  mkdir -p "$(lib_env_dir)" "$(lib_env_backup_dir)"
}

lib_phase_env_path() {
  local phase="$1"
  printf '%s/phase%s_env.sh' "$(lib_env_dir)" "${phase}"
}

_lib_read_suffix_from_env_file() {
  local env_file="$1"
  local line value

  [[ -f "${env_file}" ]] || return 1

  line="$(grep -E '^export SUFFIX=' "${env_file}" 2>/dev/null | head -1 || true)"
  [[ -n "${line}" ]] || return 1

  value="${line#export SUFFIX=}"
  value="${value#\'}"; value="${value%\'}"
  value="${value#\"}"; value="${value%\"}"
  printf '%s' "${value}"
}

_lib_backup_env_file_if_needed() {
  local dest_file="$1"
  local current_suffix="$2"

  [[ -f "${dest_file}" ]] || return 0

  local existing_suffix
  existing_suffix="$(_lib_read_suffix_from_env_file "${dest_file}" || true)"

  if [[ -n "${existing_suffix}" && "${existing_suffix}" != "${current_suffix}" ]]; then
    local backup_dir dest_basename backup
    backup_dir="$(lib_env_backup_dir)"
    mkdir -p "${backup_dir}"
    dest_basename="$(basename "${dest_file}")"
    backup="${backup_dir}/${dest_basename}.bak.${existing_suffix}"
    cp "${dest_file}" "${backup}"
    lib_log INFO "Backup creado: ${backup} (SUFFIX anterior: ${existing_suffix})"
  fi
}

_lib_write_env_file() {
  local dest_file="$1"
  shift
  local tmp="${dest_file}.$$"
  local name value

  : > "${tmp}"
  for name in "$@"; do
    value="${!name:-}"
    if [[ -n "${value}" ]]; then
      printf 'export %s=%q\n' "${name}" "${value}" >> "${tmp}"
    fi
  done
  mv "${tmp}" "${dest_file}"
}

_lib_phase_env_var_names() {
  local phase="$1"
  case "${phase}" in
    0)
      printf '%s\n' \
        SUFFIX DS_NAME PROVIDER CONSUMER PROVIDER_BASE CONSUMER_BASE PROVIDER_PROTOCOL CONSUMER_PROTOCOL \
        IPPCP_DATASPACE IPPCP_DATASPACE_DIR IPPCP_DATASPACE_FILE IPPCP_FLOW IPPCP_FLOW_VERSION IPPCP_FLOW_DIR
      ;;
    1)
      printf '%s\n' \
        SUFFIX VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID ASSET_ID CD_ID \
        IPPCP_DATASPACE IPPCP_DATASPACE_DIR IPPCP_DATASPACE_FILE IPPCP_FLOW IPPCP_FLOW_VERSION IPPCP_FLOW_DIR \
        IPPCP_PHASE1_REUSE_EXISTING PHASE1_ASSET_ORIGIN PHASE1_REUSE_IDS_VERIFIED \
        PHASE1_REUSE_SUFFIX PHASE1_REUSE_ASSET_ID \
        ASSET_ID_CUSTOM ASSET_CONFIG ASSET_SLUG ASSET_NAME ASSET_DESCRIPTION \
        ASSET_BASE_URL ASSET_CONTENT_KIND ASSET_EXTENSION ASSET_MEDIA_TYPE \
        ASSET_HTTP_METHOD ASSET_PROXY_BODY ASSET_PROVIDER_ID \
        ASSET_KEYWORDS_JSON ASSET_DATA_ADDRESS_NAME STORAGE_MODE
      ;;
    1b)
      printf '%s\n' \
        SUFFIX VOCAB_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID ASSET_ID CD_ID \
        IPPCP_DATASPACE IPPCP_DATASPACE_DIR IPPCP_DATASPACE_FILE IPPCP_FLOW IPPCP_FLOW_VERSION IPPCP_FLOW_DIR \
        ASSET_ID_CUSTOM ASSET_UPLOAD_CONFIG ASSET_SLUG ASSET_NAME ASSET_DESCRIPTION \
        ASSET_CONTENT_KIND ASSET_EXTENSION ASSET_MEDIA_TYPE ASSET_KEYWORDS_JSON \
        STORAGE_MODE LOCAL_FILE STORE_FOLDER UPLOAD_FILE_NAME FINALIZE_FILE_NAME
      ;;
    2)
      printf '%s\n' \
        SUFFIX ASSET_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID CD_ID \
        PROVIDER_PARTICIPANT_ID OFFER_POLICY_ID CATALOG_ASSET_ID NEG_ID AGREEMENT_ID \
        IPPCP_DATASPACE IPPCP_DATASPACE_DIR IPPCP_DATASPACE_FILE IPPCP_FLOW IPPCP_FLOW_VERSION IPPCP_FLOW_DIR \
        IPPCP_PHASE1_REUSE_EXISTING PHASE1_ASSET_ORIGIN PHASE1_REUSE_IDS_VERIFIED \
        PHASE1_REUSE_SUFFIX PHASE1_REUSE_ASSET_ID \
        ASSET_ID_CUSTOM ASSET_CONFIG ASSET_SLUG ASSET_NAME ASSET_DESCRIPTION \
        ASSET_BASE_URL ASSET_CONTENT_KIND ASSET_EXTENSION ASSET_MEDIA_TYPE \
        ASSET_HTTP_METHOD ASSET_PROXY_BODY ASSET_PROVIDER_ID \
        ASSET_KEYWORDS_JSON ASSET_DATA_ADDRESS_NAME STORAGE_MODE
      ;;
    3)
      printf '%s\n' \
        SUFFIX ASSET_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID CD_ID NEG_ID AGREEMENT_ID TRANSFER_ID EDR_URL \
        IPPCP_DATASPACE IPPCP_DATASPACE_DIR IPPCP_DATASPACE_FILE IPPCP_FLOW IPPCP_FLOW_VERSION IPPCP_FLOW_DIR \
        IPPCP_PHASE1_REUSE_EXISTING PHASE1_ASSET_ORIGIN PHASE1_REUSE_IDS_VERIFIED \
        PHASE1_REUSE_SUFFIX PHASE1_REUSE_ASSET_ID \
        ASSET_ID_CUSTOM ASSET_CONFIG ASSET_SLUG ASSET_NAME ASSET_DESCRIPTION \
        ASSET_BASE_URL ASSET_CONTENT_KIND ASSET_EXTENSION ASSET_MEDIA_TYPE \
        ASSET_HTTP_METHOD ASSET_PROXY_BODY ASSET_PROVIDER_ID \
        ASSET_KEYWORDS_JSON ASSET_DATA_ADDRESS_NAME STORAGE_MODE
      ;;
    3b)
      printf '%s\n' \
        SUFFIX ASSET_ID ACCESS_POLICY_ID CONTRACT_POLICY_ID CD_ID NEG_ID AGREEMENT_ID TRANSFER_ID \
        IPPCP_DATASPACE IPPCP_DATASPACE_DIR IPPCP_DATASPACE_FILE IPPCP_FLOW IPPCP_FLOW_VERSION IPPCP_FLOW_DIR \
        TRANSFER_TYPE STORAGE_MODE ASSET_CONTENT_KIND ASSET_EXTENSION ASSET_MEDIA_TYPE \
        ASSET_UPLOAD_CONFIG LOCAL_FILE STORE_FOLDER UPLOAD_FILE_NAME FINALIZE_FILE_NAME \
        CONSUMER_TRANSFER_STATE
      ;;
    *)
      return 1
      ;;
  esac
}

lib_export_phase_env() {
  local phase="$1"
  local -a vars=()
  local phase_label run_dest latest_dest name

  lib_require_vars SUFFIX
  if [[ -z "${RUN_DIR:-}" ]]; then
    lib_init_run_dirs
  fi

  case "${phase}" in
    1|1b)
      lib_derive_phase1_ids
      ;;
    0|2|3|3b)
      ;;
    *)
      lib_die "lib_export_phase_env: fase inválida '${phase}' (esperado 0-3, 1b, 3b)"
      ;;
  esac

  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    vars+=("${name}")
  done < <(_lib_phase_env_var_names "${phase}")

  lib_init_env_dirs

  phase_label="phase${phase}_env.sh"
  run_dest="${RUN_DIR}/${phase_label}"
  latest_dest="$(lib_phase_env_path "${phase}")"

  _lib_write_env_file "${run_dest}" "${vars[@]}"
  lib_log INFO "Escrito ${run_dest}"

  _lib_backup_env_file_if_needed "${latest_dest}" "${SUFFIX}"
  _lib_write_env_file "${latest_dest}" "${vars[@]}"
  lib_log INFO "Escrito ${latest_dest}"
}
