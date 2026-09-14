# Final Demo Guide

## Demo purpose

### Objective

Demonstrate a controlled IPPCP data exchange from provider publication through consumer Data Plane consumption and technical result verification. The demonstration must make the business result, connector responsibilities, security boundaries, and resulting traceability understandable without exposing operational secrets or sensitive payloads.

### Intended audience

The guide supports:

- functional stakeholders evaluating the use case;
- technical stakeholders evaluating data-space behavior;
- provider and consumer representatives;
- project and demonstration teams;
- operators preparing and presenting a validated flow.

### Expected outcome

At the end of the demonstration, the audience should be able to explain:

- what resource the provider made available;
- how the consumer discovered and negotiated access;
- how transfer and Data Plane delivery differ from direct credential sharing;
- what result was obtained and verified (materialized download or POST metadata-only control artifacts);
- how the run summary, manifest or POST control metadata, byte counts, and SHA-256 (where applicable) provide traceability;
- which capabilities are validated and which remain planned.

## Demo roles

### Presenter or operator

Selects the validated variant, prepares the secure local environment, executes the current phase scripts, explains observable states, and prevents sensitive values from appearing on screen.

### Provider-side actor

Explains the data offer and provider responsibility. In the current v2 flows, the City Council connector is the provider and owns the asset data address and any provider-side upstream credential.

### Consumer-side actor

Explains discovery, negotiation, transfer, and authorized use. In the current v2 flows, the company connector is the consumer. It receives the EDR-based consumption path but does not receive the Ingestion API key.

### Functional stakeholder

Explains why the exchange matters to the use case, what business result is expected, and how the selected variant relates to business Phase A, Phase B, or the intended Phase C.

The demo must not publish usernames, passwords, tokens, API keys, or other credential material.

## Demo scope

### Validated demo variants

The demo supports these validated variants:

- **Ingestion API PRE GET:** validated end-to-end intake path with materialized JSON download; maps to business Phase A.
- **Ingestion API PROD POST (Industrias Ebro):** validated production intake path; `HttpData-PULL` with upstream POST and POST metadata-only phase 4; maps to business Phase A.
- **WFS:** GeoJSON resource using `HttpData-PULL`; supports the resource-consumption narrative in business Phase B.
- **SPARQL JSON:** SPARQL Results JSON using `HttpData-PULL`; supports the semantic-resource narrative in business Phase B.

**CIRCE PROD** is validated end-to-end through phase 4 using a CIRCE-specific request body. CIRCE uses `districtCode`; do not reuse the Industrias Ebro payload.

The primary variant is selected during readiness review according to audience, objective, environment, and business narrative. **PROD POST / Industrias Ebro** is the recommended primary technical narrative when the environment supports it. The other validated variants remain alternatives and contingencies.

### Delivered baseline evidence

T1–T4 are presentation slots, not asset types. Historical delivered assessment evidence may occupy slots via `--preset legacy_assessment`. CSV/B2 remains a preserved baseline and is not the current workshop path.

### Planned or non-demonstrated capabilities

Unless separately implemented and validated before the readiness decision, the live demo does not claim:

- final provider or consumer backend APIs;
- automated onboarding, offboarding, revocation, or credential rotation;
- a validated Phase C technical workflow;
- automated API-key rotation;
- CIRCE PROD phase 4 with a request body that does not match the CIRCE-specific schema;
- SPARQL graph consumption;
- formal KPI or assessment compliance.

## Functional narrative

### Business Phase A: Intake

An external company or data provider interacts with the intended municipal intake context. The current technical demonstration validates the Ingestion API v2 exchange — **PRE GET** (phases 0–4, materialized response) and **PROD POST / Industrias Ebro** (phases 0–4, POST metadata-only) — while the final integrated company-facing form and backend remain planned.

### Business Phase B: Consume

A City Council stakeholder needs an available resource for municipal processing. WFS and SPARQL JSON provide validated selectable variants for this consumption narrative.

### Business Phase C: Consume by public companies

Phase C represents the intended downstream public-company journey. It is presented as a business objective, not as a validated technical flow.

### Technical phase0 through phase4

Business Phase A–C and the technical script phases are different views. The selected validated variant uses the same technical sequence:

1. `phase0` resolves context, authenticates the provider and consumer technical roles through EdD Keycloak, and performs smoke checks.
2. `phase1` publishes the provider policies, asset, data address, and contract definition.
3. `phase2` discovers the offer, negotiates access, and obtains an agreement.
4. `phase3` starts the transfer and retrieves an EDR.
5. `phase4` retrieves a current EDR and completes Data Plane consumption. **Materialized-response** flows (PRE GET, WFS, SPARQL) persist a download with manifest and SHA-256. **PROD POST** persists HTTP/control metadata only (`post_result.json` / `post_manifest.json`); request and response bodies are not stored. The selected flow guide's operator block then applies the applicable validation checks.

The municipal application Keycloak shown in the architecture diagram is separate from EdD Keycloak. The former supports the municipal application and its external users; the latter authenticates technical users to connector Management APIs.

## Live demonstration sequence

### 1. Explain the scenario and architecture

Show the [canonical architecture](../architecture.md) and explain that it is a high-level functional and infrastructure view, not a complete low-level EDC sequence. Identify `CONN-CITYCOUNCIL` as provider and `CONN-COMPANY` as consumer.

### 2. Select the dataspace, flow, and v2

State the selected dataspace profile, the chosen flow, and `IPPCP_FLOW_VERSION=v2`. Do not display concrete connector hosts or credential-file contents.

### 3. Verify environment readiness

Confirm the prerequisites in the [workshop](../workshop.md) and [Getting Started](../getting-started.md) and complete the [Readiness checklist](readiness-checklist.md). Verify that provider, consumer, and any flow-specific secrets are available through ignored local files.

### 4. Execute phase0

Run the selected flow's documented sequence. Explain the context resolution, separate provider and consumer authentication, smoke checks, and creation of the run correlation identifier.

### 5. Publish the provider offer in phase1

Explain the observable publication of policies, asset, data address, and contract definition. For the Ingestion API variant, confirm verbally that the API key is loaded only for publication and remains provider-side.

### 6. Negotiate in phase2

Show sanitized phase status indicating catalog discovery, negotiation finalization, and a valid agreement. Do not expose concrete identifiers unless they have been replaced with placeholders.

### 7. Start transfer and retrieve the EDR in phase3

Explain that transfer initiation creates the authorized consumption context. Show only redacted status or field names; never display EDR authorization.

### 8. Consume and validate in phase4

Explain that phase4 retrieves a current EDR and calls the Data Plane. For materialized-response variants, show the download and run semantic validation. For PROD POST, show sanitized POST control metadata (HTTP status, `manifest_kind=post_metadata_only`) — not a fake download, manifest, or response SHA-256.

### 9. Present summary and traceability artifacts

Show a sanitized summary structure. For materialized-response flows, show manifest field names, byte count, and the SHA-256 concept. For PROD POST, show safe POST metadata fields only.

### 10. Explain the business result and traceability

Connect the validated technical result back to the selected business narrative. State which capabilities were demonstrated live, which were previously validated, and which remain planned.

## Runnable commands

Use one complete flow guide as the operator source:

- [Ingestion API](../flows/ingestion-api.md)
- [WFS](../flows/wfs.md)
- [SPARQL](../flows/sparql.md)

Do not reconstruct or combine commands from different variants in this guide. The flow guides own asset selection, secret lifecycle, phase environment inheritance, and semantic validation.

## Success criteria

### Authentication

- Provider and consumer technical users authenticate successfully against EdD Keycloak.
- No credential value is shown or persisted in public demo material.

### Publication

- The provider asset and contract definition are created.
- The run summary records successful phase1 completion.

### Agreement

- The consumer discovers the intended offer.
- Negotiation reaches a valid final state with an agreement identifier.

### Transfer

- Transfer creation is accepted.
- An EDR can be resolved for the selected agreement without exposing authorization.

### Technical result

- **Materialized response:** phase4 persists a non-empty response through the Data Plane; manifest and SHA-256 apply.
- **PROD POST metadata-only:** phase4 records HTTP 2xx control metadata; no GET-style download or response SHA-256 is required.

### Semantic content validation (materialized-response flows)

- PRE GET Ingestion API: non-empty valid JSON.
- WFS: valid GeoJSON with the expected `FeatureCollection` structure.
- SPARQL: valid SPARQL Results JSON with `head` and `results.bindings`.

### POST metadata validation (PROD POST)

- HTTP 2xx recorded in `post_result.json` / `post_manifest.json`.
- `manifest_kind=post_metadata_only`; `download_persisted=false`; no request/response bodies in evidence.

### Evidence generation

- `summary.json` reflects the completed phase sequence.
- Run-specific phase artifacts exist.
- Materialized flows: manifest records file, byte count, and SHA-256.
- PROD POST: safe POST control metadata only.
- Publicly shown material is sanitized and contains no authorization value or business POST body.

## Evidence shown during the demo

The presentation may show only reviewed and sanitized material:

- phase status and timestamps at an appropriate level;
- placeholder asset, contract, negotiation, agreement, and transfer identifiers;
- the field structure of `summary.json`;
- manifest field names (materialized flows) or POST metadata field names (PROD POST);
- byte count where applicable;
- the SHA-256 concept for materialized-response flows only;
- redacted screenshots;
- prepared outputs that contain no business-sensitive payload.

Never display:

- API keys;
- passwords;
- JWTs;
- EDR authorization;
- raw `phase*_env.sh` files;
- internal or concrete connector hosts;
- real run identifiers or UUIDs;
- raw business-sensitive payloads.

The publication rules in [Evidence and traceability](../evidence-and-traceability.md) are authoritative.

## Contingency plan

Before the demo, prepare contingencies that are available and approved:

1. a previously validated output for the selected variant;
2. sanitized screenshots of the expected phase transitions;
3. a recording only when one has been produced and approved;
4. a sanitized evidence package only when one has been reviewed for publication;
5. one alternative validated flow whose environment is ready;
6. a short explanation that distinguishes a live environment failure from the previously validated technical result.

If the live run fails:

- stop before displaying diagnostic files that may contain sensitive material;
- identify the failed phase using sanitized status only;
- use implemented recovery controls only when their prerequisites are satisfied;
- continue with the approved prepared output or alternative flow;
- state clearly that prepared evidence demonstrates a previous validated result, not completion of the failed live run.

See [Troubleshooting](../troubleshooting.md) for implemented restart and recovery behavior.

## Known limitations

- **Validated:** Ingestion API PROD POST (Industrias Ebro and CIRCE phases 0–4), PRE GET, WFS, and SPARQL Results JSON technical exchanges.
- **Delivered baseline:** historical CSV/B2 evidence remains preserved (`--preset legacy_assessment`).
- **Legacy-supported:** v1 and the CSV/B2 technical path are not recommended for new integration.
- **Planned:** final integrated backends, automated lifecycle management, Phase C technical realization, and automated API-key rotation.
- **Pending / N/A:** SPARQL graph consumption.

## Related documentation

- [Project and use-case rationale](project-justification.md)
- [Architecture](../architecture.md)
- [Authentication](../authentication.md)
- [Execution phases](../execution-phases.md)
- [Evidence and traceability](../evidence-and-traceability.md)
- [End-user journey](end-user-journey.md)
- [Readiness checklist](readiness-checklist.md)
