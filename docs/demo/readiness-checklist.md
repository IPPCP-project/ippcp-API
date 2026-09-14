# Demo Readiness Checklist

## Purpose

Use this checklist before approving an IPPCP demonstration. A checked item means the responsible reviewer has verified the condition for the selected demo environment and variant.

The checklist does not establish formal KPI or assessment compliance. It verifies observable readiness for the public-safe technical demonstration described in the [Final demo guide](final-demo.md).

## Functional readiness

- [ ] The use case and business stage are confirmed.
- [ ] Functional and technical stakeholders are identified by role.
- [ ] Provider, consumer, presenter/operator, and functional-speaker responsibilities are confirmed.
- [ ] One primary validated demo variant is selected: Ingestion API PROD POST (Industrias Ebro), Ingestion API PRE GET, WFS, or SPARQL JSON.
- [ ] The selected variant matches the intended audience, demo objective, available environment, and desired business narrative.
- [ ] The expected business result is agreed and can be explained without sensitive payloads.
- [ ] The distinction between business Phase A–C and technical `phase0`–`phase4` is ready to explain.
- [ ] Planned and out-of-scope capabilities are ready to explain accurately.
- [ ] Phase C is not presented as technically validated.

## Environment readiness

- [ ] The intended dataspace profile is explicitly selected.
- [ ] Provider and consumer connector base configuration is correct for that profile.
- [ ] `IPPCP_FLOW_VERSION=v2` is selected.
- [ ] The required flow is selected: `ingesta` for Ingestion API or `consumo` for WFS/SPARQL.
- [ ] Provider EdD credentials are available securely through the expected ignored local file.
- [ ] Consumer EdD credentials are available securely through the expected ignored local file.
- [ ] Flow-specific secrets are available securely only when required.
- [ ] For Ingestion API PRE GET, the PRE API key and provider identifier can be loaded immediately before phase1 and removed afterward.
- [ ] For Ingestion API PROD POST, the PROD API key file, the selected company config, and a matching local request body file (`INGESTA_API_REQUEST_BODY_FILE`) are ready; use `centerId` for Industrias Ebro and `districtCode` for CIRCE.
- [ ] The target environment (PRE and/or PROD as selected) is reachable.
- [ ] Required local tools and a supported Bash version are available as described in the [workshop](../workshop.md) and [Getting Started](../getting-started.md).

## Flow readiness

- [ ] The phase0 smoke test succeeds for provider and consumer connector roles.
- [ ] The selected `ASSET_CONFIG` matches the intended variant.
- [ ] The selected asset identifier is unique for the planned run.
- [ ] Phase1 publishes the asset and contract definition successfully.
- [ ] Phase2 obtains a valid agreement; a display state alone is not accepted without the agreement identifier.
- [ ] Phase3 creates or resumes the intended transfer and resolves an EDR.
- [ ] Phase4 completes with the expected result mode for the selected variant:
  - materialized-response: non-empty download through the Data Plane;
  - PROD POST: HTTP 2xx POST metadata-only (`post_result.json` / `post_manifest.json`); no GET-style download required.
- [ ] The complete run uses one consistent `run_id`/`SUFFIX`.
- [ ] PRE GET Ingestion API semantic validation confirms non-empty valid JSON.
- [ ] WFS semantic validation confirms valid GeoJSON with the expected `FeatureCollection` structure.
- [ ] SPARQL semantic validation confirms SPARQL Results JSON with `head` and `results.bindings`.
- [ ] Only the semantic check for the selected primary variant is presented as the live result.

## Evidence readiness

- [ ] `summary.json` records the expected phase statuses.
- [ ] Run-specific artifacts exist under one correlated execution.
- [ ] Provider asset and contract-definition identifiers are present internally.
- [ ] Consumer negotiation, agreement, and transfer identifiers are present internally.
- [ ] The phase4 traceability artifact matches the selected mode (download manifest or POST control metadata).
- [ ] For materialized-response flows: recorded byte count is non-zero and SHA-256 verification succeeds.
- [ ] For PROD POST: HTTP 2xx and `manifest_kind=post_metadata_only`; no response SHA-256 required.
- [ ] Any screenshot intended for display is redacted and approved.
- [ ] Any prepared output is sanitized and approved.
- [ ] No raw password, API key, JWT, EDR authorization, or credential file is included.
- [ ] No raw `phase*_env.sh` file is displayed or published.
- [ ] T1–T4 are described as presentation slots, not asset types.
- [ ] The asset in each slot is classified from the run.
- [ ] CSV/B2 is described as a preserved historical baseline, not the current workshop path.
- [ ] Ingestion API PRE GET, PROD POST (Industrias Ebro), WFS city, WFS juntas, and SPARQL are the current workshop profiles.
- [ ] `--tests SLOT=SUFFIX` is used for current packaging; `--only-tests T4` is not the Ingestion API Golden Path.
- [ ] A COMPLETE example may assign any current asset to any slot.
- [ ] A SINGLE example may place Ingestion API in a non-T4 slot to demonstrate slot independence.
- [ ] `publication_ready` is true only when every included slot is `publication_safe`.
- [ ] A package that includes WFS or SPARQL (`standard`) is classified as internal if intended for external sharing.
- [ ] Runtime suffixes are used only to locate evidence and do not appear in publication-safe outputs.
- [ ] The [synthetic evidence example](../../examples/evidence/t4-ingestion-api/README.md) is identified as structural documentation, not raw validation evidence.

## Presentation readiness

- [ ] The canonical architecture diagram is available and legible.
- [ ] The diagram is described as a high-level functional and infrastructure view, not an exhaustive EDC sequence.
- [ ] `CONN-CITYCOUNCIL` is identified as the provider connector and `CONN-COMPANY` as the consumer connector.
- [ ] Municipal application Keycloak and EdD Keycloak are explained as separate boundaries.
- [ ] The [Project and use-case rationale](project-justification.md) has been reviewed.
- [ ] The [End-user journey](end-user-journey.md) has been reviewed.
- [ ] The presenter sequence has been rehearsed using the selected flow guide.
- [ ] The target duration has been agreed.
- [ ] Technical and functional speakers are assigned by role.
- [ ] Expected technical, security, business-value, and limitation questions have been reviewed.
- [ ] Backup screenshots are available when produced and approved.
- [ ] A backup recording is available only when produced and approved.

## Contingency readiness

- [ ] A previously validated fallback run exists for the selected primary variant.
- [ ] At least one alternative validated flow is identified when its environment can be prepared safely.
- [ ] Offline sanitized evidence is available when it has been reviewed and approved.
- [ ] The presenter can distinguish a live failure from a previously validated result.
- [ ] The stop condition for avoiding secret exposure is understood.
- [ ] `PHASE2_FORCE=1` is used only when a new negotiation is intentionally required.
- [ ] `PHASE3_RESUME=1` is used only to resume EDR retrieval for the existing transfer.
- [ ] `PHASE3_FORCE=1` is used only when a new transfer is intentionally required.
- [ ] `PHASE3_RESUME=1` and `PHASE3_FORCE=1` are never combined.
- [ ] `DOWNLOAD_FORCE=1` is used only after checking run identity and the existing download.
- [ ] Any rollback or reset explanation is limited to controls actually implemented in [Troubleshooting](../troubleshooting.md).
- [ ] No automated provider cleanup or complete distributed rollback is claimed.

## Publication readiness

- [ ] No credentials or secret values are present.
- [ ] No internal or concrete connector hosts are present.
- [ ] No personal data is present.
- [ ] No raw evidence is present.
- [ ] No real run identifier, UUID, or hash is presented as public example data.
- [ ] No business-sensitive payload is present.
- [ ] No phase environment, raw request, raw response, preview, data-address content, or source path is present.
- [ ] Any cryptographic hash value has explicit publication approval; otherwise the value is withheld.
- [ ] The [Evidence Publication Policy](../evidence-publication.md) has been applied and manually reviewed.
- [ ] Any T4-only workbook has passed its automated OOXML audit and a separate manual workbook review.
- [ ] A mixed T1–T4 workbook is not presented as a public-safe artifact.
- [ ] All local links and referenced repository paths resolve.
- [ ] All public-candidate text is in English.
- [ ] Licensing and acknowledgements have been checked against the repository [LICENSE](../../LICENSE).
- [ ] Public, internal, legacy-supported, and historical classifications have been reviewed.
- [ ] No `docs/internal` or `docs/archive` material is exposed by the demo navigation.
- [ ] Every displayed or packaged artifact has explicit publication approval.

## Final go/no-go

### Go criteria

- [ ] Every blocking item above is complete for the selected primary variant.
- [ ] The primary variant has passed a recent readiness run.
- [ ] The live sequence and contingency transition have been rehearsed.
- [ ] Public-safety review has passed.
- [ ] Functional and technical presenters agree on the claims and limitations.

### No-go criteria

Mark **No-Go** if any of these conditions applies:

- [ ] No primary validated variant has been selected.
- [ ] Required credentials or environment access cannot be prepared securely.
- [ ] Phase0 readiness fails and no approved validated fallback is available.
- [ ] Semantic validation or evidence integrity fails.
- [ ] The material to be shown has not passed publication review.
- [ ] The presentation would require claiming a planned or out-of-scope capability as validated.

### Decision

- [ ] **Go**
- [ ] **No-Go**

Record the decision, selected variant, responsible roles, and review time in the private operational record, not in the public documentation package.
