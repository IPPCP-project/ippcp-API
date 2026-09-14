# Project and Use-Case Rationale

## Purpose

This document provides a public-safe technical and functional rationale for the IPPCP use case. It describes the problem, participating actor categories, supported exchanges, demonstrated value, and current implementation status.

It is based on the validated repository implementation and the project context available for the use case. It is not a formal contractual project memory, an official deliverable justification, or evidence of contractual or KPI compliance.

## Project context

Organizations involved in urban sustainability need to exchange data across institutional boundaries. Data may originate in company submissions, municipal systems, geospatial services, or semantic data services. The receiving organization needs to know what was offered, under which conditions it was accessed, and whether the delivered result can be traced to the corresponding exchange.

IPPCP applies data-space mechanisms to this problem. The current implementation demonstrates how a provider publishes a data offer and how a consumer discovers, negotiates, transfers, consumes through the Data Plane, and verifies the technical result through INESData-compatible connector infrastructure.

## Problem being addressed

A direct application-to-application call can move data, but it does not by itself provide a common mechanism for:

- publishing a discoverable data offer;
- associating access and contract policies with that offer;
- separating provider and consumer responsibilities;
- negotiating access before delivery;
- keeping upstream credentials outside the consumer boundary;
- correlating publication, agreement, transfer, phase 4 result, and evidence;
- validating materialized representations or POST control metadata as applicable;

IPPCP addresses these needs through controlled data exchange. The current automation focuses on a reproducible technical path while the final integrated municipal and company backends remain planned.

## Participating actor categories

The use case involves these functional categories:

- **External companies and data providers:** organizations that supply or expose data for controlled use.
- **City Council stakeholders:** municipal users and services that govern, process, or consume the available resources.
- **Public-company consumers:** intended downstream users represented by business Phase C.
- **Platform and application operators:** personnel responsible for preparing the environment and running the current technical workflow.
- **Provider-side connector role:** the City Council connector, represented in the diagram as `CONN-CITYCOUNCIL`.
- **Consumer-side connector role:** the company connector, represented as `CONN-COMPANY`.

The connector roles are technical data-space roles. They do not replace the business roles of the people and organizations using the municipal platform.

## Why controlled exchange is needed

Controlled exchange gives the provider a defined publication boundary and gives the consumer a contract-based access path. It also separates three security concerns:

1. technical users authenticate to connector Management APIs through EdD Keycloak;
2. the consumer uses an Endpoint Data Reference (EDR) credential to access the Data Plane;
3. provider-side upstream credentials, when required, are used by the Data Plane and remain invisible to the consumer.

For the protected Ingestion API flow, `X-Api-Key` and `X-Provider-Id` belong to the provider data address. The consumer and its future backend do not receive the API key.

## Stakeholder value

### Value for companies

The intended business journey gives companies a clear route to make data available through a governed municipal context. Data-space publication can expose an agreed resource without requiring the company-facing application to distribute connector credentials or provider upstream secrets to consumers.

For current demonstrations, the repository validates connector and transfer mechanics including **PROD POST** (Industrias Ebro) and **PRE GET** intake paths. Final company-facing forms, integrated backends, and automated account lifecycle management are planned components.

### Value for the City Council

The City Council can:

- publish controlled resources through its provider connector;
- discover and negotiate offers through the consumer role where required by the scenario;
- use repeatable WFS, SPARQL, and Ingestion API exchanges;
- retain run-level evidence for publication, negotiation, transfer, and phase 4 results;
- verify materialized downloads or POST metadata-only outcomes as applicable;
- distinguish validated technical behavior from future application integration.

### Role of the IPPCP data space

The IPPCP data space supplies the contract and transfer context between the provider and consumer roles. Connector Management APIs support publication, discovery, negotiation, and transfer initiation. The Data Plane performs material delivery after authorization.

The control plane does not carry the business payload. The consumer obtains an EDR, uses it to reach the Data Plane, and receives the resource through the authorized transfer path.

### Relationship with INESData

The implementation is developed in the context of the IPPCP project and its INESData data-space integration. The current automation validates IPPCP exchanges against the configured EdD connector environment while preserving project-specific business roles, resources, and evidence.

## Current supported flows

All current recommended flows use `IPPCP_FLOW_VERSION=v2` and `HttpData-PULL`:

- **Ingestion API PRE GET:** protected JSON resource; materialized phase 4 download.
- **Ingestion API PROD POST:** upstream POST with `proxyBody=true`; metadata-only phase 4 (Industrias Ebro and CIRCE validated phases 0–4).
- **WFS:** GeoJSON resources exposed by the selected WFS layer.
- **SPARQL:** SPARQL Results JSON requested explicitly by the canonical configuration.

Detailed setup, execution, and semantic validation are maintained in the [Ingestion API](../flows/ingestion-api.md), [WFS](../flows/wfs.md), and [SPARQL](../flows/sparql.md) guides.

## Project building blocks

The high-level use case combines:

- the municipal platform and its application-facing identity boundary;
- the dedicated municipal application Keycloak used by the City Council platform and external users;
- EdD Keycloak for provider and consumer connector authentication;
- the City Council provider connector and company consumer connector;
- connector catalog, negotiation, agreement, and transfer capabilities;
- the Data Plane and EDR-based consumption path;
- Ingestion API, WFS, and SPARQL upstream resources;
- the current Bash `phase0` through `phase4` automation;
- run-level summaries, evidence, manifests (materialized flows), POST control metadata (PROD POST), byte counts, and SHA-256 verification where applicable;
- planned provider and consumer backend integrations.

The two Keycloak scopes are separate. Municipal application authentication does not authenticate connector Management API operations, and EdD technical-user credentials are not end-user application credentials.

## Functional stages

[![IPPCP high-level functional and infrastructure architecture](../diagrams/ippcp-architecture.svg)](../diagrams/ippcp-architecture.svg)

The diagram is a high-level functional and infrastructure view, not an exhaustive low-level EDC sequence.

### Phase A: Intake

Phase A represents the intended company-facing intake journey through the municipal platform. The current technical package validates the Ingestion API data-space exchange through **PRE GET** (phases 0–4, materialized response) and **PROD POST (Industrias Ebro)** (phases 0–4, POST metadata-only) as first-class validated intake paths. **PROD POST (Industrias Ebro)** is the recommended primary demo narrative when the environment supports it. The final integrated form and backend journey remains planned.

### Phase B: Consume

Phase B represents municipal consumption of available resources. The current package validates WFS and SPARQL JSON exchanges through the provider and consumer connectors.

### Phase C: Consume by public companies

Phase C represents the intended business-level journey for public-company consumption. Its final application and backend realization is planned and must not be presented as a validated technical workflow.

### Business stages and script phases

Business `PHASE A` through `PHASE C` describe use-case stages. They are distinct from the implemented technical pipeline:

```text
phase0 -> phase1 -> phase2 -> phase3 -> phase4
```

The script phases resolve context and authentication, publish the offer, negotiate an agreement, initiate transfer and retrieve an EDR, then complete authorized Data Plane consumption and technical result verification. See [Execution phases](../execution-phases.md).

## Capability and evidence status

Technical status and evidence role are separate. A delivered evidence baseline does not make its technical path the recommended integration.

| Flow or capability | Technical status | Evidence role |
| --- | --- | --- |
| Ingestion API PROD POST (Industrias Ebro) | Validated (phases 0–4, metadata-only phase 4) | Classified from run; slot assignment is arbitrary (`--tests SLOT=SUFFIX`) |
| Ingestion API PRE GET | Validated | Classified from run; slot assignment is arbitrary |
| Ingestion API PROD POST (CIRCE) | Validated end-to-end (phases 0–4 with CIRCE-specific body) | Phase 4 POST metadata-only; request and response bodies are not persisted |
| WFS exchange | Validated | Classified from run |
| SPARQL Results JSON exchange | Validated | Classified from run |
| CSV/B2/InesDataStore path | Legacy-supported | Historical delivered baseline (`--preset legacy_assessment`); not recommended for new integrations |
| v1 project path | Legacy-supported | Compatibility material; not the current recommended path |
| Final integrated provider and consumer backends | Planned | No completed backend evidence |
| Automated onboarding and offboarding | Planned | No completed lifecycle-automation evidence |
| Phase C technical realization | Planned | Business-stage intent only |
| SPARQL graph configuration | Out of current scope | The validated SPARQL representation is SPARQL Results JSON |

T1–T4 are presentation slots, not asset types. The tool classifies each run and applies that asset's `publication_profile`. CSV/B2 remains a preserved historical baseline; it is not the current workshop path.

## Security and traceability principles

The current implementation follows these principles:

- provider and consumer connector credentials remain in their owning environment;
- short-lived EdD JWTs are not persisted as cross-phase state;
- EDR authorization is retrieved at runtime and excluded from public evidence;
- the Ingestion API key remains provider-side and is not disclosed to the consumer;
- `run_id`, currently represented by `SUFFIX`, correlates the technical execution;
- connector and contract identifiers support continuation and audit;
- phase summaries record observable status without publishing secrets;
- the phase 4 manifest records the materialized file, byte count, and SHA-256 where applicable;
- PROD POST phase 4 records HTTP/control metadata only — not request/response bodies;
- public evidence must be explicitly sanitized and approved.

See [Authentication](../authentication.md) and [Evidence and traceability](../evidence-and-traceability.md) for the canonical rules.

## Validated capabilities

The current package supports:

- provider and consumer EdD authentication for the configured connectors;
- provider publication of policies, assets, data addresses, and contract definitions;
- consumer catalog discovery and contract negotiation;
- transfer initiation and EDR retrieval;
- authorized Data Plane consumption;
- flow-specific semantic validation for materialized-response flows;
- POST metadata-only validation for PROD Ingestion API;
- run-level summary, manifest or POST control metadata, byte-count, and SHA-256 generation where applicable;
- end-to-end validated Ingestion API PROD POST variants for Industrias Ebro and CIRCE, PRE GET, WFS, and SPARQL JSON.

Validation means the technical path completed with a successful phase 4 result — materialized download with verified manifest (materialized response) or POST metadata-only with HTTP 2xx. It does not imply completion of every planned application, lifecycle, or production deployment capability.

## Limitations and planned components

The repository currently operates through Bash phase scripts. It does not present a final backend API as implemented.

The following remain planned or outside the current validated package:

- final provider and consumer backend services;
- persistent database-backed orchestration replacing shell environment hand-offs;
- final backend API contracts and callbacks;
- automated onboarding, offboarding, revocation, and credential rotation;
- automated API-key rotation for immutable assets;
- a validated Phase C technical workflow;
- CIRCE PROD phase 4 with a request body that does not match the CIRCE-specific schema;
- SPARQL graph consumption.

Future implementations must preserve the current security boundaries and state sequence described in [Backend integration](../backend-integration.md).
