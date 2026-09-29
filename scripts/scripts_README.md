# scripts/ — Automatización API IPPCP

> For current execution, start with [`docs/workshop.md`](../docs/workshop.md).
> Este fichero no es el golden path.
>
> **Referencia avanzada y de compatibilidad**
>
> `v2` es el camino vigente. `v1` y los procedimientos B2/CSV se conservan para
> reproducibilidad histórica; las secciones legacy de este documento no constituyen
> el quick start recomendado.

Librería compartida y scripts de fase para operar por API el EdD de IPPCP. La configuración operativa actual está en `flujos/ippcp/v2/`. `flujos/ippcp/v1/` se conserva exclusivamente como legado reproducible.

Para IPPCP, `export_dataspace.sh` se resuelve desde la raíz del dataspace:

```text
flujos/ippcp/export_dataspace.sh
```

Los exports comunes de raíz son:

```text
export_suffix.sh
endpoints.sh
```

## Requisitos

- **Bash 4.3+** (obligatorio): `endpoints.sh` usa `declare -A`; `lib_require_vars_group` usa `local -n` (nameref).
- En macOS el `/bin/bash` suele ser **3.2**. Instala uno moderno y úsalo explícitamente:

```bash
brew install bash jq curl
/opt/homebrew/bin/bash --version   # o /usr/local/bin/bash
```

En las guías operativas se usa `BASH_BIN` para no depender de una ruta concreta:

```bash
export BASH_BIN=/usr/local/bin/bash
```

- `curl`, `jq` en PATH.
- `python3` recomendado (decodificación JWT); si falta, hay fallback bash.

## Uso básico

Desde cualquier carpeta, un script de fase hará:

```bash
# El caller debe seleccionar el contexto antes de invocar la fase.
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=ingesta       # o consumo
export IPPCP_FLOW_VERSION=v2

# shellcheck source=/dev/null
source "${API_ROOT}/scripts/lib_common.sh"

api_find_root
lib_load_env          # carga dataspace + flujos/<flujo>/ + endpoints; SUFFIX solo si no existe
lib_require_cmds
lib_init_run_dirs     # evidencias/runs/${SUFFIX}/phase0..3
```

Si no se define un selector de dataspace ni puede inferirse uno desde
`IPPCP_FLOW_DIR`, `lib_load_env` termina con un error accionable. `test3` solo
se selecciona de forma explícita para reproducir pruebas históricas; nunca se
usa como fallback.

### Flujo IPPCP (`IPPCP_FLOW_VERSION`)

Para IPPCP actual se recomienda seleccionar dataspace, flujo y versión. `flujos/ippcp/export_dataspace.sh` resuelve la ruta completa del flujo:

```text
flujos/ippcp/${IPPCP_FLOW_VERSION}/${IPPCP_FLOW}/export_provider.sh
flujos/ippcp/${IPPCP_FLOW_VERSION}/${IPPCP_FLOW}/export_consumer.sh
```

Las credenciales locales (ignoradas por Git) deben existir como:

```text
flujos/ippcp/v2/ingesta/user_provider.sh
flujos/ippcp/v2/ingesta/user_consumer.sh
flujos/ippcp/v2/consumo/user_provider.sh
flujos/ippcp/v2/consumo/user_consumer.sh
```

Los ejemplos `v1` no forman parte de la preparación operativa actual; se conservan únicamente para reproducibilidad legacy.

Preparación local (ejemplo ingesta v2):

```bash
cp flujos/ippcp/v2/ingesta/user_provider.example.sh flujos/ippcp/v2/ingesta/user_provider.sh
cp flujos/ippcp/v2/ingesta/user_consumer.example.sh flujos/ippcp/v2/ingesta/user_consumer.sh
# editar ambos ficheros localmente con credenciales reales
```

Seleccionar ingesta IPPCP v2:

```bash
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=ingesta
export IPPCP_FLOW_VERSION=v2
$BASH_BIN scripts/phase0_context_smoke.sh
```

Seleccionar consumo IPPCP v2:

```bash
export IPPCP_DATASPACE=ippcp
export IPPCP_FLOW=consumo
export IPPCP_FLOW_VERSION=v2
$BASH_BIN scripts/phase0_context_smoke.sh
```

`IPPCP_FLOW_VERSION` admite `v1` o `v2`. `v2` es la versión actual y predeterminada; `v1` se conserva únicamente como legado reproducible.

`IPPCP_FLOW_DIR` sigue disponible como override avanzado/troubleshooting. Si ya viene definido desde el entorno, no se sobreescribe.

### Dataspace (`IPPCP_DATASPACE_DIR`)

El dataspace se carga desde un `export_dataspace.sh` configurable. Para IPPCP actual:

```bash
export IPPCP_DATASPACE=ippcp
```

También puede indicarse explícitamente el directorio de dataspace:

```bash
IPPCP_DATASPACE_DIR=flujos/ippcp /usr/local/bin/bash scripts/phase0_context_smoke.sh
```

Override de fichero completo: `IPPCP_DATASPACE_FILE=flujos/ippcp/export_dataspace.sh`.

**Nueva ejecución:** `lib_load_env` ejecutará `export_suffix.sh` y generará un `SUFFIX` nuevo.

**Continuar ejecución** (terminal nueva, mismo taller):

```bash
source runtime/env/latest/phase1_env.sh    # o phase2_env.sh — fija SUFFIX e IDs
source ./scripts/lib_common.sh
api_find_root
lib_load_env              # no regenera SUFFIX
lib_init_run_dirs
```

## Evidencias

Las evidencias **legacy** en `evidencias/00_*` no se mueven ni borran.

Cada ejecución nueva usa:

```
evidencias/runs/${SUFFIX}/
├── phase0/
├── phase1/          # HttpData (A/B1)
├── phase1b/         # InesDataStore upload (B2)
├── phase2/
├── phase3/          # HttpData-PULL + EDR (A/B1)
├── phase3b/         # AmazonS3-PUSH (B2)
├── phase4/
├── phase4b/         # descarga MinIO consumer (B2)
├── runtime/env/latest/phase0_env.sh … phase3_env.sh, phase3b_env.sh
└── summary.json
```

Artefactos HTTP: `{step}.json` (body) + `{step}.http` (código). Nunca mezclar el status HTTP dentro del JSON.

### Entrega posterior de evidencias

Tras ejecutar las fases funcionales, la entrega Excel/ZIP se genera desde `tools/` sin cambiar las evidencias originales ni la lógica de los scripts de fase.

En B1, `transfer_state=STARTED` puede convivir con `phase3.edr_obtained=ok`. La descarga material queda verificada solo cuando `phase4.save_download=ok` incluye `bytes` y `sha256`.

En B2, `transfer_state=STARTED` puede convivir con `phase4b.storage_fetch=ok`. Si hay `bytes` y `sha256`, la descarga desde consumer MinIO está verificada.

Esta situación se refleja en el Excel como `PASS_WITH_NOTE`.

## Seguridad en evidencias

No se guardan en disco:

- Contraseñas (`PROVIDER_PASSWORD`, `CONSUMER_PASSWORD`)
- JWTs completos
- Prefijos ni fragmentos de JWT en JSON

Los claims JWT (`lib_jwt_claims_to_json`) solo persisten: `role`, `iat`, `exp`, `now`, `token_length`. En consola sí se puede imprimir longitud y prefijo (`lib_jwt_check_console`).

## Funciones principales

| Función | Descripción |
|---------|-------------|
| `lib_renew_jwt [provider\|consumer\|both]` | Token Keycloak (mismo curl que Notion) |
| `lib_jwt_claims_to_json role file` | Claims seguros en JSON |
| `lib_curl_json base [--allow-empty-body] curl_args…` | Body `.json`, status `.http`, valida JSON |
| `lib_write_summary phase step status [metadata_json]` | Merge atómico en `summary.json` |
| `lib_export_phase_env 0\|1\|2\|3\|1b\|3b` | Escribe env en run dir y `runtime/env/latest/phaseN_env.sh` |
| `lib_derive_phase1_ids` | `vocab-${SUFFIX}`, `asset-${SUFFIX}` (legacy), o preserva `ASSET_ID` si `ASSET_ID_CUSTOM=1` |

### Backup al exportar `phaseN_env.sh`

Si `runtime/env/latest/phaseN_env.sh` ya existe y contiene un `SUFFIX` distinto al actual, se crea un backup en `runtime/env/backups/phaseN_env.sh.bak.<SUFFIX>` antes de sobrescribir.

Variables opcionales: `IPPCP_ENV_DIR`, `IPPCP_ENV_BACKUP_DIR` (ver `docs/getting-started.md` y `docs/evidence-and-traceability.md`).

### `lib_curl_json` y respuestas vacías

Por defecto exige JSON válido en respuestas 2xx. Para endpoints futuros con **204** o body vacío:

```bash
lib_curl_json "${artifact}" --allow-empty-body \
  -X DELETE "${PROVIDER_BASE}/management/v3/assets/${ASSET_ID}" \
  -H "Authorization: Bearer ${PROVIDER_JWT}"
```

## Scripts de fase

- `phase0_context_smoke.sh` — contextualización y smoke test inicial (JWT + assets/request)
- `phase1_provider_publish.sh` — publicación provider (vocab, policies, asset HttpData configurable, contract definition, catálogo). Rechaza configs B2 (`storage_mode=inesdatastore`).
- `phase1b_provider_upload_file.sh` — Fase B2: upload local → InesDataStore (S3 chunk + finalize), policies, CD; escribe `phase1_env.sh` (compat phase2) y `phase1b_env.sh`
- `phase2_consumer_negotiate.sh` — consumer: catálogo remoto, negociación y `AGREEMENT_ID`
- `phase3_transfer_edr.sh` — consumer: transfer HttpData-PULL y obtención de EDR. No consume datos por defecto.
- `phase3b_inesdata_transfer.sh` — Fase B2: transfer `AmazonS3-PUSH` → `InesDataStore` (sin EDR)
- `phase4_save_download.sh` — consume el EDR, guarda `phase4/40_data_response.<extension>` y copia a `downloads/assets/` con manifest en `downloads/manifests/` (solo A/B1 HttpData)
- `phase4b_consumer_storage_fetch.sh` — Fase B2: descarga real desde MinIO consumer con `mc` (config temporal)

## ASSET_CONFIG

Configuración externa opcional para publicar assets HttpData. Sin `ASSET_CONFIG`, Fase 1 usa el asset legacy de taller (`asset-${SUFFIX}`) con JSONPlaceholder.

### Fase A — HTTP JSON

```bash
ASSET_CONFIG=asset_configs/demo/http/http_jsonplaceholder_todos.json \
$BASH_BIN scripts/phase1_provider_publish.sh
```

Salida esperada:

```text
downloads/assets/<ASSET_ID>/latest.json
downloads/manifests/<ASSET_ID>/latest.manifest.json
```

### Fase B1 — HTTP text/binary

Permite consumir por EdD recursos HTTP que **ya están publicados** en una URL accesible por el provider/dataplane. **No incluye subida a storage** (eso es Fase B2 — ver más abajo).

Ejemplo Excel (copiar plantilla y editar URL real):

```bash
cp asset_configs/examples/ingesta_excel.example.json asset_configs/ingesta_excel_empresa_demo.json
# editar base_url

ASSET_CONFIG=asset_configs/ingesta_excel_empresa_demo.json \
$BASH_BIN scripts/phase1_provider_publish.sh
```

Salida esperada:

```text
downloads/assets/<ASSET_ID>/latest.xlsx
downloads/manifests/<ASSET_ID>/latest.manifest.json
```

Otros ejemplos en `asset_configs/examples/`:

- `emisiones_csv.example.json` — `text` / `csv`
- `emisiones_wfs_gml.example.json` — `text` / `gml`

Recomendación: probar primero con un CSV o TXT pequeño antes de Excel/ZIP.

### Schema (`asset_configs/*.json`)

| Campo | Obligatorio | Descripción |
|-------|-------------|-------------|
| `asset_slug` | sí | Identificador seguro; se sanitiza a `[A-Za-z0-9._-]` |
| `name` | sí | Nombre del asset |
| `description` | sí | Descripción corta |
| `type` | sí | Solo `HttpData` |
| `base_url` | sí | URL `http://` o `https://` del endpoint GET |
| `content_kind` | sí | `json`, `text` o `binary` |
| `extension` | sí | Allowlist: `json`, `xml`, `gml`, `csv`, `txt`, `ttl`, `rdf`, `xlsx`, `zip` |
| `media_type` | no | Default según extensión (ver tabla abajo) |
| `keywords` | no | Array de strings; default `[]` |
| `asset_id` | no | Si omitido: `${asset_slug}-${SUFFIX}`; si explícito: `^[A-Za-z0-9._-]+$` |
| `http_method` | no | Si omitido: sin propiedad `method` en el `dataAddress` (GET implícito). Permitidos: `GET`, `POST` |
| `proxy_body` | no | Booleano. Si `true`, emite `proxyBody:"true"` (string) en el `dataAddress` |
| `provider_id` | no | Numérico no secreto. Si está presente con `requires_provider_id_header=true`, se usa como `X-Provider-Id` y no hace falta `INGESTA_API_PROVIDER_ID` |
| `requires_provider_id_header` | no | Booleano. Si `true`, Fase 1 añade `X-Provider-Id` (desde `provider_id` o `INGESTA_API_PROVIDER_ID`) |
| `requires_api_key_header` | no | Booleano. Si `true`, Fase 1 requiere `INGESTA_API_KEY` y añade `X-Api-Key` al `dataAddress`; la evidencia persiste solo `<redacted>` |

Pares `content_kind` / `extension` válidos:

| `content_kind` | `extension` permitidas |
|----------------|------------------------|
| `json` | `json` |
| `text` | `xml`, `gml`, `csv`, `txt`, `ttl`, `rdf` |
| `binary` | `xlsx`, `zip` |

Defaults de `media_type` por extensión:

| Extensión | Default |
|-----------|---------|
| `json` | `application/json` |
| `csv` | `text/csv` |
| `txt` | `text/plain` |
| `xml` | `application/xml` |
| `gml` | `application/gml+xml` |
| `xlsx` | `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` |
| `zip` | `application/zip` |
| `ttl` | `text/turtle` |
| `rdf` | `application/rdf+xml` |

La allowlist de extensiones se valida en Fases 1, 3 y 4.

Variable opcional `ALLOW_EMPTY_DOWNLOAD=1` (Fases 3 y 4) para permitir descargas vacías.

Con config, el `ASSET_ID` y metadata (`ASSET_CONTENT_KIND`, `ASSET_EXTENSION`, `ASSET_MEDIA_TYPE`) se propagan a Fases 2–4 vía `phaseN_env.sh` (`ASSET_ID_CUSTOM=1`).

Ejemplo WFS JSON (Fase A):

```bash
cp asset_configs/examples/emisiones_wfs.example.json asset_configs/emisiones_wfs.json
# editar base_url

ASSET_CONFIG=asset_configs/emisiones_wfs.json \
$BASH_BIN scripts/phase1_provider_publish.sh
```

Ejemplo SPARQL JSON:

```bash
cp asset_configs/examples/emisiones_sparql.example.json asset_configs/emisiones_sparql.json
# editar base_url

ASSET_CONFIG=asset_configs/emisiones_sparql.json \
$BASH_BIN scripts/phase1_provider_publish.sh
```

### Verificar metadata en `summary.json`

Tras Fase 1 OK con `ASSET_CONFIG`, comprueba que el paso `create_asset` incluye metadata no sensible del asset:

```bash
source runtime/env/latest/phase1_env.sh

jq '.phases.phase1.steps[] | select(.id=="create_asset")' \
  "evidencias/runs/${SUFFIX}/summary.json"
```

El resultado debe incluir, entre otros, `asset_id`, `asset_base_url`, `content_kind`, `extension`, `media_type` y `asset_config` (cuando se usó config). Ejemplo con config demo:

```json
{
  "id": "create_asset",
  "status": "ok",
  "asset_id": "jsonplaceholder_todos-<SUFFIX>",
  "asset_slug": "jsonplaceholder_todos",
  "asset_base_url": "https://jsonplaceholder.typicode.com/todos",
  "content_kind": "json",
  "extension": "json",
  "media_type": "application/json",
  "asset_config": "asset_configs/demo/http/http_jsonplaceholder_todos.json"
}
```

Logs de diagnóstico de Fase 1 (p. ej. `extra_meta_json` en `_phase1_create_and_summary`) solo con `PHASE1_DEBUG=1`:

```bash
PHASE1_DEBUG=1 ASSET_CONFIG=asset_configs/demo/http/http_jsonplaceholder_todos.json \
$BASH_BIN scripts/phase1_provider_publish.sh
```

## Fase B2 — InesDataStore (legado reproducible T1)

Flujo paralelo a A/B1. **No mezclar** con `phase3_transfer_edr.sh` ni `phase4_save_download.sh`.

| Fase | Script | Qué hace |
|------|--------|----------|
| 1b | `phase1b_provider_upload_file.sh` | Upload chunk + finalize → InesDataStore, policies, CD |
| 2 | `phase2_consumer_negotiate.sh` | Igual que HttpData (lee `phase1_env.sh`) |
| 3b | `phase3b_inesdata_transfer.sh` | `POST .../inesdatatransferprocesses` con `AmazonS3-PUSH` |
| 4b | `phase4b_consumer_storage_fetch.sh` | Descarga MinIO consumer con `mc` + manifest B2 |

**Éxito B2:** phase1b + phase2 + phase3b OK (transfer `STARTED`/`COMPLETED`) + phase4b OK (descarga local verificada).

**Requisito adicional:** cliente MinIO `mc`:

```bash
brew install minio/stable/mc
```

`phase4b` usa `--config-dir` temporal; **no** persiste credenciales en `~/.mc/config.json`. Si creaste un alias global durante pruebas manuales:

```bash
mc alias remove consumer-b2
```

### Seguridad credenciales S3 (phase3b)

Tras el transfer, phase3b guarda:

| Artefacto | Contenido |
|-----------|-----------|
| `20_transfer_state_*.json` | Redacted (evidencias seguras) |
| `21_transfer_final_state.json` | Redacted |
| `21_transfer_final_state.sensitive.json` | Raw; `chmod 600`; gitignored; solo lo lee phase4b |

Summary, manifests y logs **nunca** incluyen `accessKeyId`, `secretAccessKey` ni JWTs.

### Config B2 (`ASSET_UPLOAD_CONFIG`)

Configs en `asset_configs/demo/upload/` (separadas de `ASSET_CONFIG` HttpData). Schema:

| Campo | Obligatorio | Descripción |
|-------|-------------|-------------|
| `storage_mode` | sí | Debe ser `inesdatastore` |
| `type` | sí | `InesDataStore` |
| `asset_slug` | sí | Identificador seguro |
| `name` | sí | Nombre del asset |
| `description` | sí | Descripción corta |
| `local_file` | sí | Ruta al fichero local (p. ej. `data/ingesta_demo.csv`) |
| `store_folder` | sí | Carpeta destino en storage |
| `upload_file_name` | sí | Nombre del objeto subido |
| `content_kind` | sí | `text` o `binary` |
| `extension` | sí | Allowlist: `csv`, `txt`, `xml`, `gml`, `ttl`, `rdf`, `xlsx`, `zip` |
| `media_type` | no | Default según extensión |
| `keywords` | no | Array de strings; default `[]` |
| `asset_id` | no | Si omitido: `${asset_slug}-${SUFFIX}` |
| `finalize_file_name` | no | Default: `${store_folder}/${upload_file_name}` |

Plantilla: `asset_configs/examples/ingesta_csv_upload.example.json`

Prueba demo incluida:

```bash
ASSET_UPLOAD_CONFIG=asset_configs/demo/upload/ingesta_csv_empresa_demo.json \
$BASH_BIN scripts/phase1b_provider_upload_file.sh
```

Tras phase1b OK:

```bash
source runtime/env/latest/phase1_env.sh
$BASH_BIN scripts/phase2_consumer_negotiate.sh
source runtime/env/latest/phase2_env.sh
$BASH_BIN scripts/phase3b_inesdata_transfer.sh
source runtime/env/latest/phase3b_env.sh
$BASH_BIN scripts/phase4b_consumer_storage_fetch.sh
```

Verificar descarga:

```bash
diff -u data/ingesta_demo.csv "downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION}"
jq . "downloads/manifests/${ASSET_ID}/latest.manifest.json"
```

**Notas:**

- Si pasas una config B2 a `phase1_provider_publish.sh`, falla con mensaje para usar `phase1b`.
- Fase 3b inspecciona el catálogo Fase 2: si aparece `AmazonS3-PUSH` se registra; si no, **no falla** — intenta el transfer igualmente.
- `phase3b_env.sh` es independiente de `phase3_env.sh` (no hay `EDR_URL`).
- `phase4_save_download.sh` **no aplica** a B2 (requiere artefacto EDR HttpData).
- Ejecuciones phase3b anteriores sin `.sensitive.json`: phase4b puede leer `21_transfer_final_state.json` legacy con WARN; conviene re-ejecutar phase3b o migrar manualmente.
- `PHASE4B_ALLOW_SKIP=1` restaura comportamiento skipped si faltan credenciales (solo escape hatch).
- `DOWNLOAD_FORCE=1` y `ALLOW_EMPTY_DOWNLOAD=1` se comportan como en Fase 4.

## Assets reales IPPCP validados

Configs en `asset_configs/real/consumo/` y `asset_configs/real/ingesta/`. Las guías canónicas están en `docs/flows/ingestion-api.md`, `docs/flows/wfs.md` y `docs/flows/sparql.md`.

Los scripts curl de `data/real/consumo/wfs/` y `data/real/consumo/sparql/` incluyen header `Accept` explícito. La automatización B1 (`phase4_save_download.sh`) **no** inyecta `Accept` al endpoint final; si SPARQL devuelve HTML/XML, habrá que extender el schema de `ASSET_CONFIG` con headers HTTP.

**No ejecutar** configs `*_pending*` ni `*.pending.json` hasta confirmación municipal.

### WFS ciudad (B1 validado)

```bash
ASSET_CONFIG=asset_configs/real/consumo/wfs/emisiones_wfs_ciudad_geojson.json \
$BASH_BIN scripts/phase1_provider_publish.sh
```

Validado de punta a punta. El identificador concreto de la ejecución permanece interno.

### WFS juntas (B1 validado)

```bash
ASSET_CONFIG=asset_configs/real/consumo/wfs/emisiones_wfs_juntas_geojson.json \
$BASH_BIN scripts/phase1_provider_publish.sh
```

### SPARQL operativo (B1)

```bash
ASSET_CONFIG=asset_configs/real/consumo/sparql/emisiones_sparql_limit10_format_json.json \
$BASH_BIN scripts/phase1_provider_publish.sh
```

Validado de punta a punta. El identificador concreto de la ejecución permanece interno.

### Ingesta API Pull PRE (B1 validado)

```bash
source data/real/ingesta/auth/ingesta_api_key.env
ASSET_CONFIG=asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json \
$BASH_BIN scripts/phase1_provider_publish.sh
unset INGESTA_API_KEY INGESTA_API_PROVIDER_ID
```

Usar PRE para pruebas iniciales. El flujo validado cubre `phase1 -> phase2 -> phase3 -> phase4`.

`asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json` declara `requires_provider_id_header=true` y `requires_api_key_header=true`. Fase 1 exige ambas variables y añade `header:X-Provider-Id` y `header:X-Api-Key` al payload real.

La API key se carga desde un fichero local ignorado, no se imprime ni se exporta a `phase1_env.sh`, y aparece como `<redacted>` en evidencias persistidas. El asset no utiliza JWT upstream.

Prueba directa PRE autorizada:

```bash
data/real/ingesta/pre/curl_ingesta_api_pull_pre_base.sh
```

Las variantes de consulta no confirmadas y las configuraciones GET PRO preparatorias están excluidas de la guía pública actual.

### Ingesta API Pull PROD (HTTP POST sobre HttpData-PULL)

Transfer = `HttpData-PULL`; `dataAddress.type=HttpData`; HTTP method = `POST`; `proxyBody=true`. `POST` no es `HttpData-PUSH`.

Upstream PROD:

```text
https://idezar-sig.zaragoza.es/servicios/ippcp-ingesta/api/intake
```

| Empresa | `ASSET_CONFIG` | `provider_id` |
| --- | --- | --- |
| Industrias Ebro | `asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json` | `1` |
| CIRCE | `asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json` | `2` |

Plantilla de entorno (ignorada; no versionar secretos):

```text
data/real/ingesta/auth/ingesta_api_key_prod.env.example
→ data/real/ingesta/auth/ingesta_api_key_prod.env
```

```bash
source data/real/ingesta/auth/ingesta_api_key_prod.env
ASSET_CONFIG=asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json \
$BASH_BIN scripts/phase1_provider_publish.sh
# o: asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json
unset INGESTA_API_KEY INGESTA_API_PROVIDER_ID
```

`provider_id` viene del config por empresa (no secreto) y debe prevalecer frente a un `INGESTA_API_PROVIDER_ID` stale en el shell. `X-Api-Key` es secreto runtime/provider-side.

GET histórico (PRE y otros HttpData GET) conserva descarga en phase4 (`downloads/assets/…` + manifest + sha256).

Phase4 POST (con body específico de la empresa correcta; Industrias Ebro y CIRCE validados end-to-end en PROD):

```bash
export INGESTA_API_REQUEST_BODY_FILE=/path/file.json
$BASH_BIN scripts/phase4_save_download.sh
unset INGESTA_API_REQUEST_BODY_FILE
```

El body de request **no** se persiste. El body de response **no** se persiste. No hay descarga ni sha256 de response. Salida metadata-only:

```text
evidencias/runs/${SUFFIX}/phase4/post_result.json
evidencias/runs/${SUFFIX}/phase4/post_manifest.json
```

El payload depende de la empresa: Industrias Ebro utiliza `centerId` y CIRCE utiliza `districtCode`. No uses el payload de una empresa para la otra.

### CSV ingesta real (B2)

```bash
ASSET_UPLOAD_CONFIG=asset_configs/real/ingesta/ingesta_bbdd_residencial_2021_csv.json \
$BASH_BIN scripts/phase1b_provider_upload_file.sh
```

Este flujo conserva el baseline histórico T1 B2/CSV para reproducibilidad.

Flujo B1 actual validado: phase1 → phase2 → phase3 → phase4. Flujo B2 histórico, conservado para reproducibilidad: phase1b → phase2 → phase3b → phase4b.

## Ejecución

Requiere Bash 4.3+. Tras phase1 OK:

```bash
source runtime/env/latest/phase1_env.sh
$BASH_BIN scripts/phase2_consumer_negotiate.sh
```

Tras phase0 OK:

```bash
source runtime/env/latest/phase0_env.sh
$BASH_BIN scripts/phase1_provider_publish.sh
```

Phase0 solo:

```bash
$BASH_BIN scripts/phase0_context_smoke.sh
```

Tras phase2 OK:

```bash
source runtime/env/latest/phase2_env.sh
$BASH_BIN scripts/phase3_transfer_edr.sh
```

Fase 3 termina al obtener un EDR resoluble. No descarga datos por defecto. El comportamiento antiguo de consumo en Fase 3 queda disponible solo como compatibilidad explícita:

```bash
PHASE3_TRY_DATA_CONSUMPTION=1 $BASH_BIN scripts/phase3_transfer_edr.sh
```

Relanzar Fase 2 en la misma ejecución (si ya hay `AGREEMENT_ID` en `phase2_env.sh`):

```bash
PHASE2_FORCE=1 $BASH_BIN scripts/phase2_consumer_negotiate.sh
```

Relanzar Fase 3 en la misma ejecución (si ya hay `TRANSFER_ID` en `phase3_env.sh`):

```bash
PHASE3_FORCE=1 $BASH_BIN scripts/phase3_transfer_edr.sh
```

Continuar Fase 3 tras fallo en EDR (sin crear transfer nuevo):

```bash
PHASE3_RESUME=1 $BASH_BIN scripts/phase3_transfer_edr.sh
```

Tras phase3 OK, consumir el EDR y guardar la descarga local:

```bash
source runtime/env/latest/phase3_env.sh
$BASH_BIN scripts/phase4_save_download.sh
```

Para Ingesta API, ejecutar phase4 normal. La autenticación upstream ya está configurada en el asset mediante `header:X-Api-Key` y `header:X-Provider-Id`; no usar el modo JWT upstream histórico.

Resultado:

```text
downloads/assets/${ASSET_ID}/latest.${ASSET_EXTENSION:-json}
downloads/manifests/${ASSET_ID}/latest.manifest.json
```

Forzar sobrescritura si el fichero existe con contenido distinto:

```bash
DOWNLOAD_FORCE=1 $BASH_BIN scripts/phase4_save_download.sh
```
