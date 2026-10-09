# Evidence tooling (operational reference)

T1, T2, T3, and T4 are presentation slots. The asset in each slot is classified from the run.

Executable workshop commands: [docs/workshop.md](../docs/workshop.md) (section 16).

## What the tools do

```text
evidencias/runs -> Excel summary -> sanitized ZIP -> secret/publication audit
```

The tools are read-only over source evidence. They must not modify `evidencias/runs/`, `downloads/`, phase env files, or phase scripts.

## Requirements

Python 3.10+. Inspection commands in the workshop also use `jq`, `unzip`, and `rg`.

```bash
python3 --version
command -v jq
command -v unzip
command -v rg
python3 -m pip install -r tools/requirements-evidence-export.txt
```

Optional venv:

```bash
python3 -m venv .venv-evidence
source .venv-evidence/bin/activate
python -m pip install --upgrade pip
python -m pip install -r tools/requirements-evidence-export.txt
```

## Slot selection

`--tests` is an exact slot set. No YAML suffixes are merged in.

```text
--tests "T1=<suffix>"
--tests "T1=<suffix>,T3=<suffix>"
--tests "T1=<s1>,T2=<s2>,T3=<s3>,T4=<s4>"
```

Without `--tests` or `--preset`, there is no implicit selection.

`--only-tests` filters an already selected set; it does not invent slots.

Historical presets:

```text
--preset legacy_assessment
--preset legacy_test3
```

`--profile` selects sanitization defaults only. It does not assign assets to slots.

## Recommended suffix variables

```bash
export INGESTION_SUFFIX="<suffix>"
export WFS_JUNTAS_SUFFIX="<suffix>"
export WFS_CITY_SUFFIX="<suffix>"
export SPARQL_SUFFIX="<suffix>"
```

Validate:

```bash
: "${INGESTION_SUFFIX:?Set INGESTION_SUFFIX}"
: "${WFS_JUNTAS_SUFFIX:?Set WFS_JUNTAS_SUFFIX}"
: "${WFS_CITY_SUFFIX:?Set WFS_CITY_SUFFIX}"
: "${SPARQL_SUFFIX:?Set SPARQL_SUFFIX}"
```

## COMPLETE (four slots)

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
  --timestamp "$COMPLETE_TS" \
  --export-dir "$COMPLETE_EXPORT_DIR" \
  --strict
```

Every slot in this selection is `minimal_publication`. The workbook is generated separately for internal review. The ZIP excludes Excel, so the packager is invoked without `--excel` and with `--strict`. A correct ZIP exits 0. `publication_ready=false` is still expected because WFS and SPARQL are internal (`minimal_publication_internal`). That status is independent of the exit code. `publication_ready=true` is not authorization to distribute the package.

Do not recompute `COMPLETE_TS` between the workbook and the ZIP. The workbook remains beside the ZIP.

Inspect:

```bash
unzip -p "$COMPLETE_ZIP" ippcp_evidence_package/package_status.json | jq '{publication_ready, publication_blockers}'
unzip -p "$COMPLETE_ZIP" ippcp_evidence_package/slot_inventory.json | jq .
```

## SINGLE (one slot)

Example with Ingestion API in T3. Generate the workbook separately for internal review. The slot is `minimal_publication`, so the packager is invoked without `--excel` and with `--strict`. A correct ZIP exits 0. `publication_ready` follows the classified asset. A true value is not authorization for external distribution.

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

## Two slots (arbitrary order)

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

Both selected assets are `minimal_publication`. A packager invocation for this set omits `--excel` and keeps `--strict`.

## Preset export and packaging (`legacy_assessment`)

Export and package with the **same timestamp** (do not recompute between workbook and ZIP). This preset includes CSV B2, which is `standard`, so the package is not minimal-only and `--excel` remains appropriate:

```bash
TS=$(date +%Y%m%d_%H%M%S)
EXPORT_DIR="reports/exports/legacy_assessment_$TS"
WORKBOOK="$EXPORT_DIR/ippcp_evidence_summary_${TS}.xlsx"
ZIP="$EXPORT_DIR/ippcp_evidence_package_${TS}.zip"

python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --preset legacy_assessment \
  --timestamp "$TS" \
  --export-dir "$EXPORT_DIR" \
  --strict

python3 tools/package_evidence_bundle.py \
  --config tools/evidence_export.tests.yaml \
  --preset legacy_assessment \
  --excel "$WORKBOOK" \
  --timestamp "$TS" \
  --export-dir "$EXPORT_DIR" \
  --strict
```

Subset of a preset selection:

```bash
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --preset legacy_assessment \
  --only-tests T1 \
  --timestamp "$TS" \
  --export-dir "$EXPORT_DIR" \
  --strict
```

`legacy_test3`:

```bash
TS=$(date +%Y%m%d_%H%M%S)
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --preset legacy_test3 \
  --timestamp "$TS" \
  --export-dir "reports/exports/legacy_test3_$TS" \
  --strict
```

## Profile and sanitization overrides

Explicit profile:

```bash
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "T1=$INGESTION_SUFFIX" \
  --profile <profile> \
  --export-dir reports/exports/profile_example \
  --strict \
  --verbose
```

Enable connector sanitization (default in many paths):

```bash
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "T1=$INGESTION_SUFFIX" \
  --sanitize-connectors \
  --export-dir reports/exports/sanitize_on \
  --strict
```

Disable connector sanitization (controlled internal review only):

```bash
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "T1=$INGESTION_SUFFIX" \
  --no-sanitize-connectors \
  --export-dir reports/exports/sanitize_off \
  --verbose
```

Enable local-path redaction:

```bash
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "T1=$INGESTION_SUFFIX" \
  --redact-local-paths \
  --export-dir reports/exports/redact_on \
  --strict
```

Disable local-path redaction (controlled internal review only):

```bash
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "T1=$INGESTION_SUFFIX" \
  --no-redact-local-paths \
  --export-dir reports/exports/redact_off \
  --verbose
```

Timestamp suffix on explicit output name:

```bash
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "T1=$INGESTION_SUFFIX" \
  --output reports/exports/manual_ingestion.xlsx \
  --timestamp-suffix \
  --strict
```

Explicit packager ZIP output:

```bash
python3 tools/package_evidence_bundle.py \
  --config tools/evidence_export.tests.yaml \
  --tests "T1=$INGESTION_SUFFIX" \
  --output reports/exports/manual_ingestion.zip \
  --strict
```

## Dry-run

```bash
python3 tools/package_evidence_bundle.py \
  --config tools/evidence_export.tests.yaml \
  --tests "$COMPLETE_TESTS" \
  --dry-run \
  --verbose
```

The COMPLETE selection is minimal-publication only, so this dry-run also omits `--excel`.

## CLI flags

### `export_evidence_to_excel.py`

```text
--config --tests --preset --only-tests --repo-root --evidence-dir --downloads-dir
--output --export-dir --timestamp --timestamp-suffix --strict --profile
--sanitize-connectors / --no-sanitize-connectors
--redact-local-paths / --no-redact-local-paths --verbose --help
```

### `package_evidence_bundle.py`

```text
--config --tests --preset --only-tests --excel --output --export-dir --timestamp
--timestamp-suffix --repo-root --profile --include-downloaded-assets
--sanitize-connectors / --no-sanitize-connectors
--redact-local-paths / --no-redact-local-paths --strict --dry-run --verbose --help
```

Example overrides:

```bash
python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "T1=$INGESTION_SUFFIX" \
  --repo-root "$(pwd)" \
  --evidence-dir evidencias/runs \
  --downloads-dir downloads \
  --output reports/exports/manual.xlsx \
  --strict
```

## `--include-downloaded-assets`

Exists on the packager only. Use for controlled internal review after checking asset classification and publication profile. Do not share externally merely because the command succeeds.

```bash
python3 tools/package_evidence_bundle.py \
  --config tools/evidence_export.tests.yaml \
  --tests "$TESTS" \
  --include-downloaded-assets \
  --dry-run \
  --verbose
```

## Publication status

```text
package.publication_ready = all included slots are publication_safe
```

- Ingestion API PRE, CIRCE, stable Ebro and parallel Ebro: `minimal_publication` with an allowlisted technical record. PRE and the PROD POST profiles can be `publication_safe=true` when that record passes the scanner.
- WFS and SPARQL use the same sanitized projection and stay `publication_safe=false` (`minimal_publication_internal`). They are not raw `standard` copies.
- CSV-B2 remains `standard` / `standard_internal`. A package that still contains raw summaries, JWT claims, context, DataAddress or request/response bodies is not externally publication-ready.
- Operational negotiation, agreement and transfer UUIDs stay withheld. Run IDs, asset IDs and GET SHA-256 digests are technical evidence, not credentials.
- PROD POST metadata-only runs must not require a response download or invent a response SHA-256. Request and response sizes stay in the allowlisted record.
- A selection that contains only `minimal_publication` slots is packaged without `--excel`, with `--strict` still enabled. A correct ZIP exits 0. `publication_ready=false` can remain the right status for internal profiles such as WFS and SPARQL. That status does not follow the exit code. `publication_ready=true` is not authorization to distribute the package. A selection that includes a `standard` slot, such as `legacy_assessment`, may still pass `--excel`.

## Tests

From repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  tools.tests.test_evidence_export \
  tools.tests.test_dataspace_resolution \
  tools.tests.test_ingesta_api_post_support \
  -v
```

Historical discover suite:

```bash
cd tools/tests && PYTHONPATH=.. python3 -m unittest discover -v
```

## Help

```bash
python3 tools/export_evidence_to_excel.py --help
python3 tools/package_evidence_bundle.py --help
```
