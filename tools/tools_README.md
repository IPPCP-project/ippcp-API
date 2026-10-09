# IPPCP evidence delivery tools

Copy-and-paste end-to-end Golden Path: [`docs/workshop.md`](../docs/workshop.md).

Slot architecture notes: [`evidence_tooling.md`](evidence_tooling.md).

Security exclusions and the publication review boundary: [`../docs/evidence-publication.md`](../docs/evidence-publication.md).

Read-only tools that turn local run evidence into reviewed delivery artifacts:

```text
original evidencias/runs -> Excel summary -> sanitized ZIP -> secret/publication audit
```

They never modify `evidencias/runs/`, `downloads/`, phase environments, or the Bash phase scripts.

## Requirements

Python 3.10 or newer. From the repository root:

```bash
python3 -m pip install -r tools/requirements-evidence-export.txt
```

Declared dependencies: `openpyxl`, `PyYAML`. Conda is optional and is not required.

## Slots are not asset types

`T1`, `T2`, `T3`, and `T4` are presentation slots. `SUFFIX` is the run. The asset occupying a slot is classified from that run (`summary.json`, `asset_slug`, `asset_config`, phases, `transfer_type`, `media_type`). The classified asset then supplies publication policy.

Slot ids never select:

- asset family or variant;
- criticality;
- publication profile;
- sanitization;
- renderer.

Do not treat T1 as CSV, T2 as WFS, T3 as SPARQL, or T4 as Ingestion API.

`tools/evidence_export.tests.yaml` holds the asset registry, connector aliases, workflow-role expectations, and named presets. It does not assign an asset type to a slot.

## Slot selection

`--tests` is an exact slot set. No other slots are added from YAML defaults.

| Command | Selected slots |
| --- | --- |
| `--tests "T1=<suffix>"` | T1 only |
| `--tests "T1=<suffix>,T3=<suffix>"` | T1 and T3 only |
| `--tests "T1=<s1>,T2=<s2>,T3=<s3>,T4=<s4>"` | four-slot complete |

Without `--tests` or `--preset`, no slots are selected (`ERROR: no slots selected`). There is no implicit T1–T3 or T4 selection.

`--preset NAME` selects a named historical or canonical slot map from the config. It does not bind asset types to slots. Current presets:

- `legacy_assessment`: delivered T1–T3 assessment runs;
- `legacy_test3`: test3-era historical suffixes.

`--only-tests` filters an already selected set (`--tests` or `--preset`). It never invents slots and is not required for Golden Path SINGLE: `--tests "T3=<suffix>"` is already exact.

If both `--tests` and `--preset` are passed, `--tests` wins and `--preset` is ignored.

`--profile` selects sanitization defaults only. It does not assign assets to slots.

`--sanitize-connectors` and `--redact-local-paths` remain available as overrides. They are not part of the Golden Path commands.

Do not place runtime suffixes in commits, public examples, or filenames intended for publication. Pass them as local variables.

## Publication status

Each classified asset has `publication_profile` and `publication_safe`.

- Current Ingestion API profiles (PRE, CIRCE, stable Ebro, parallel Ebro): `minimal_publication`. PRE and the PROD POST profiles can be `publication_safe=true` when the allowlisted record passes the scanner.
- Current WFS and SPARQL: `minimal_publication` with `publication_safe=false` (`minimal_publication_internal`).
- CSV-B2 remains `standard` / `standard_internal`.

Package status is derived from the included slots, not from “the package contains a critical asset”:

```text
package.publication_ready = all included slots are publication_safe
package.publication_blockers = slot T2 uses minimal_publication_internal
```

- `publication_ready=true`: the package policy permits publication. It is not authorization to distribute the package. Manual review is still required.
- `publication_ready=false`: internal artifact. Do not share it externally.

A current COMPLETE package that includes WFS or SPARQL is normally `publication_ready=false`. A current SINGLE ingestion-only package may be `publication_ready=true`. That status is independent of the process exit code: a correct minimal-publication ZIP is generated with `--strict` and without `--excel`, and that command exits 0 even when WFS or SPARQL keep the package internal.

ZIP members live under `ippcp_evidence_package/`. Inspect status with:

```bash
unzip -p "$SINGLE_ZIP" \
  ippcp_evidence_package/package_status.json \
  | jq '{publication_ready, publication_blockers}'

unzip -p "$SINGLE_ZIP" \
  ippcp_evidence_package/slot_inventory.json \
  | jq .
```

Automated sanitization is a safeguard. Manual review remains mandatory before any public release.

## Golden Path

Set local run ids. The slot is a position; the asset is whatever the run classifies as. Slot order is arbitrary. One COMPLETE example is:

- T1 = Ingestion API
- T2 = WFS juntas
- T3 = WFS city
- T4 = SPARQL

COMPLETE and SINGLE use independent timestamps and export directories.

```bash
export INGESTION_SUFFIX=<suffix>
export WFS_JUNTAS_SUFFIX=<suffix>
export WFS_CITY_SUFFIX=<suffix>
export SPARQL_SUFFIX=<suffix>
```

### COMPLETE, four slots

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

Every slot in this selection is `minimal_publication`. Generate the workbook separately for internal review. The ZIP excludes Excel, so the packager is invoked without `--excel` and with `--strict`. A correct ZIP exits 0. `publication_ready=false` is still expected, because WFS and SPARQL stay internal. That status does not depend on the exit code, and `publication_ready=true` is not authorization to distribute the package.

Use the same `COMPLETE_TS` for the workbook and the ZIP. The workbook remains beside the ZIP.

```bash
unzip -p "$COMPLETE_ZIP" \
  ippcp_evidence_package/package_status.json \
  | jq '{publication_ready, publication_blockers}'

unzip -p "$COMPLETE_ZIP" \
  ippcp_evidence_package/slot_inventory.json \
  | jq .
```

### SINGLE: Ingestion API in T3

This assignment is deliberate: it proves slot independence. Golden Path SINGLE does not need `--only-tests`.

The workbook is a separate internal-review file. This slot is `minimal_publication`, so the packager does not receive `--excel` and keeps `--strict`. A correct ZIP exits 0. `publication_ready=true` for an ingestion-only slot is a policy result, not authorization to distribute the package.

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

```bash
unzip -p "$SINGLE_ZIP" \
  ippcp_evidence_package/package_status.json \
  | jq '{publication_ready, publication_blockers}'

unzip -p "$SINGLE_ZIP" \
  ippcp_evidence_package/slot_inventory.json \
  | jq .
```

Expected classification: `ingestion_api_v2`, `critical=true`, `publication_profile=minimal_publication`, `publication_safe=true`.

### Complete, two slots in arbitrary order

```bash
TESTS="T3=$SPARQL_SUFFIX,T1=$WFS_CITY_SUFFIX"

python3 tools/export_evidence_to_excel.py \
  --config tools/evidence_export.tests.yaml \
  --tests "$TESTS" \
  --timestamp "$TS" \
  --export-dir "$EXPORT_DIR" \
  --strict
```

Only T1 and T3 are selected. T2 and T4 are not filled in. Both selected assets are `minimal_publication`, so a packager invocation for this set also omits `--excel` and keeps `--strict`.

### Historical assessment preset

These presets are historical. They are not the current Golden Path. `legacy_assessment` includes CSV B2, which is `standard`, so the package is not minimal-only and `--excel` remains appropriate.

```bash
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

Subset of a preset: `--preset legacy_assessment --only-tests T1`.

Review a package without writing a ZIP:

```bash
python3 tools/package_evidence_bundle.py \
  --config tools/evidence_export.tests.yaml \
  --tests "$COMPLETE_TESTS" \
  --dry-run \
  --verbose
```

This dry-run uses the COMPLETE selection, so it also omits `--excel`.

Expected COMPLETE files:

```text
reports/exports/complete_<TIMESTAMP>/
  ippcp_evidence_summary_<TIMESTAMP>.xlsx
  ippcp_evidence_package_<TIMESTAMP>.zip
```

## Workbook contents

The Excel workbook includes:

- `Slot Map`
- `Summary`
- one sheet per selected slot (name derived from slot plus classified asset slug)
- `Raw JSON Index`
- `Evidence Checklist`
- `Package Manifest`

Missing JSON fields are written as `not_found`.

A `minimal_publication` slot uses the allowlisted metadata projection. Runtime suffixes of those slots must not appear in the output filename.

## Package contents

Every package includes, under `ippcp_evidence_package/`:

- `package_status.json` (`publication_ready`, `publication_blockers`, per-slot inventory fields);
- `slot_inventory.json`.

`standard` slots may include sanitized copies of selected run artifacts. Those copies may retain real identifiers, local paths, global snapshots, and cross-asset references. `minimal_publication` slots include only allowlisted JSON (`sanitized_summary.json`, `sanitized_manifest.json`, `validation_status.json`) under the slot folder. Downloaded payloads are forbidden for those slots. Excel is not added to a package that contains only `minimal_publication` slots. COMPLETE and SINGLE therefore omit `--excel`. A selection that still includes a `standard` slot, such as `legacy_assessment`, may pass `--excel`.

## Security boundary

Never include in a public package:

- credential files;
- phase environments;
- `*.sensitive.json` / `*.secret.json`;
- raw request bodies;
- connector tokens;
- EDR access material;
- local filesystem paths;
- downloaded business payloads;
- Ingestion API keys or provider identifiers.

Sanitization applies to output copies only. Source evidence must remain unchanged.

Connector aliases in output copies:

- `conn-erick-test3` → `conn-company-ippcp`
- `conn-edgar-test3` → `conn-citycouncil-ippcp`

`--redact-local-paths` replaces absolute repository paths with `<repo-root>`.

## Tests

After any tooling or exporter-config change:

```bash
cd tools/tests && PYTHONPATH=.. python3 -m unittest discover -v
```
