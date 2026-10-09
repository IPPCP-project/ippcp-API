#!/usr/bin/env python3
"""Asset registry, run classification, and semantic validators for evidence tooling.

Slots (T1..T4) are positions. Assets are detected from the run, never from the slot id.
"""

from __future__ import annotations

import csv
import fnmatch
import io
import json
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from evidence_common import (
    MINIMAL_PUBLICATION_PROFILE,
    NOT_FOUND,
    EvidenceRunLoader,
    SummaryParser,
    TestSpec,
    _find_first_value,
    _load_json_object,
    collect_safe_run_facts,
)


STANDARD_PUBLICATION_PROFILE = "standard"
CLASSIFICATION_STRONG_SCORE = 80
PRE_SLUG = "ippcp_ingesta_api_pull_pre_api_key"
CIRCE_SLUG = "ippcp_ingesta_pull_circe_prod"
CIRCE_ASSET_ID = "ippcp-ingesta-pull-circe-prod"
EBRO_SLUG = "ippcp_ingesta_pull_industrias_ebro_prod"
EBRO_STABLE_ASSET_ID = "ippcp-ingesta-pull-industrias-ebro-prod"

CSV_B2_PHASES = ["phase0", "phase1b", "phase2", "phase3b", "phase4b"]
HTTP_PULL_PHASES = ["phase0", "phase1", "phase2", "phase3", "phase4"]


class ClassificationError(RuntimeError):
    def __init__(self, slot: str, suffix: str, detected: str, detail: str = "") -> None:
        self.slot = slot
        self.suffix = suffix
        self.detected = detected
        message = (
            "Unable to classify evidence run.\n"
            f"slot={slot}\n"
            f"suffix={suffix}\n"
            f"detected={detected}"
        )
        if detail:
            message = f"{message}\n{detail}"
        super().__init__(message)


@dataclass(frozen=True)
class AssetDefinition:
    key: str
    family: str
    variant: str
    display_name: str
    sheet_slug: str
    transport: str
    critical: bool
    publication_profile: str
    publication_safe: bool
    workflow: str
    asset_type: str
    expected_phases: List[str]
    expected_workflow_kind: str = ""
    expected_content_kind: str = ""
    expected_extension: str = ""
    expected_media_type: str = ""
    expected_transfer_type: str = ""
    evidence_role: str = ""
    provider_connector: str = NOT_FOUND
    consumer_connector: str = NOT_FOUND
    technical_provider_connector: str = NOT_FOUND
    technical_consumer_connector: str = NOT_FOUND
    asset_config: str = NOT_FOUND
    asset_slugs: Tuple[str, ...] = ()
    asset_slug_patterns: Tuple[str, ...] = ()
    asset_config_suffixes: Tuple[str, ...] = ()
    asset_id_prefixes: Tuple[str, ...] = ()
    asset_id_patterns: Tuple[str, ...] = ()
    validator: str = ""
    identity: str = ""


@dataclass
class RunSignals:
    suffix: str
    asset_id: str = ""
    asset_slug: str = ""
    asset_config: str = ""
    content_kind: str = ""
    extension: str = ""
    media_type: str = ""
    transfer_type: str = ""
    workflow_kind: str = NOT_FOUND
    phases: Tuple[str, ...] = ()
    requires_api_key_header: Optional[bool] = None
    storage_mode: str = ""
    sources: Dict[str, str] = field(default_factory=dict)
    asset_origin: str = ""
    http_method: str = ""
    provider_id: str = ""
    created_asset: bool = False
    post_metadata_only: bool = False
    contradiction: str = ""


@dataclass(frozen=True)
class ValidationResult:
    status: str
    source: str
    findings: Tuple[str, ...] = ()

    @property
    def ok(self) -> bool:
        return self.status in {"passed", "ok"} and not self.findings


def load_asset_registry(config: Dict[str, Any]) -> Dict[str, AssetDefinition]:
    raw_assets = config.get("assets")
    if not isinstance(raw_assets, dict) or not raw_assets:
        raise ValueError("Config field 'assets' must be a non-empty mapping")
    registry: Dict[str, AssetDefinition] = {}
    for key, raw in raw_assets.items():
        if not isinstance(raw, dict):
            raise ValueError(f"Asset '{key}' must be a mapping")
        match = raw.get("match") or {}
        registry[key] = AssetDefinition(
            key=key,
            family=str(raw.get("family") or ""),
            variant=str(raw.get("variant") or key),
            display_name=str(raw.get("display_name") or key),
            sheet_slug=str(raw.get("sheet_slug") or key),
            transport=str(raw.get("transport") or NOT_FOUND),
            critical=bool(raw.get("critical")),
            publication_profile=str(
                raw.get("publication_profile") or STANDARD_PUBLICATION_PROFILE
            ),
            publication_safe=bool(
                raw["publication_safe"]
                if "publication_safe" in raw
                else raw.get("publication_profile") == MINIMAL_PUBLICATION_PROFILE
            ),
            workflow=str(raw.get("workflow") or NOT_FOUND),
            asset_type=str(raw.get("asset_type") or NOT_FOUND),
            expected_phases=list(raw.get("expected_phases") or []),
            expected_workflow_kind=str(raw.get("expected_workflow_kind") or ""),
            expected_content_kind=str(raw.get("expected_content_kind") or ""),
            expected_extension=str(raw.get("expected_extension") or ""),
            expected_media_type=str(raw.get("expected_media_type") or ""),
            expected_transfer_type=str(raw.get("expected_transfer_type") or ""),
            evidence_role=str(raw.get("evidence_role") or ""),
            provider_connector=str(raw.get("provider_connector") or NOT_FOUND),
            consumer_connector=str(raw.get("consumer_connector") or NOT_FOUND),
            technical_provider_connector=str(
                raw.get("technical_provider_connector") or NOT_FOUND
            ),
            technical_consumer_connector=str(
                raw.get("technical_consumer_connector") or NOT_FOUND
            ),
            asset_config=str(raw.get("asset_config") or NOT_FOUND),
            asset_slugs=tuple(str(item) for item in (match.get("asset_slugs") or ())),
            asset_slug_patterns=tuple(
                str(item) for item in (match.get("asset_slug_patterns") or ())
            ),
            asset_config_suffixes=tuple(
                str(item) for item in (match.get("asset_config_suffixes") or ())
            ),
            asset_id_prefixes=tuple(
                str(item) for item in (match.get("asset_id_prefixes") or ())
            ),
            asset_id_patterns=tuple(
                str(item) for item in (match.get("asset_id_patterns") or ())
            ),
            validator=str(raw.get("validator") or key),
            identity=str(match.get("identity") or ""),
        )
    return registry


def _clean(value: Any) -> str:
    if value in (None, "", NOT_FOUND):
        return ""
    return str(value)


def _first_non_empty(*values: Any) -> str:
    for value in values:
        cleaned = _clean(value)
        if cleaned:
            return cleaned
    return ""


def extract_run_signals(loader: EvidenceRunLoader) -> RunSignals:
    parser = loader.parser or SummaryParser(loader.summary)
    summary = loader.summary
    create_asset = parser.get_step("phase1", "create_asset") or {}
    get_asset = parser.get_step("phase1b", "get_asset") or {}
    load_config = parser.get_step("phase1", "load_asset_config") or {}
    upload_config = parser.get_step("phase1b", "load_asset_config") or {}
    save_download = parser.get_step("phase4", "save_download") or {}
    storage_fetch = parser.get_step("phase4b", "storage_fetch") or {}
    transfer_valid = parser.get_step("phase3", "transfer_type_valid") or {}
    transfer_started = (
        parser.get_step("phase3", "transfer_started")
        or parser.get_step("phase3b", "transfer_started")
        or {}
    )
    phase4_manifest = _load_json_object(loader.run_dir / "phase4" / "download_manifest.json")
    phase4b_manifest = _load_json_object(loader.run_dir / "phase4b" / "download_manifest.json")
    manifest = phase4_manifest or phase4b_manifest

    suffix = _first_non_empty(summary.get("suffix"), loader.spec.suffix)
    asset_id = _first_non_empty(
        create_asset.get("asset_id"),
        get_asset.get("asset_id"),
        summary.get("asset_id"),
        manifest.get("asset_id"),
    )
    asset_slug = _first_non_empty(
        create_asset.get("asset_slug"),
        load_config.get("asset_slug"),
        upload_config.get("asset_slug"),
        summary.get("asset_slug"),
        manifest.get("asset_slug"),
    )
    if not asset_slug and asset_id and suffix and asset_id.endswith(f"-{suffix}"):
        asset_slug = asset_id[: -(len(suffix) + 1)]
    asset_config = _first_non_empty(
        create_asset.get("asset_config"),
        load_config.get("asset_config"),
        upload_config.get("asset_config"),
        upload_config.get("asset_upload_config"),
        summary.get("asset_config"),
        manifest.get("asset_config"),
    )
    content_kind = _first_non_empty(
        create_asset.get("content_kind"),
        save_download.get("content_kind"),
        storage_fetch.get("content_kind"),
        manifest.get("content_kind"),
        summary.get("content_kind"),
    )
    extension = _first_non_empty(
        create_asset.get("extension"),
        save_download.get("extension"),
        storage_fetch.get("extension"),
        manifest.get("extension"),
    )
    media_type = _first_non_empty(
        create_asset.get("media_type"),
        save_download.get("media_type"),
        storage_fetch.get("media_type"),
        manifest.get("media_type"),
    )
    transfer_type = _first_non_empty(
        transfer_valid.get("transfer_type"),
        transfer_started.get("transfer_type"),
        manifest.get("transfer_type"),
        save_download.get("transfer_type"),
        storage_fetch.get("transfer_type"),
    )
    storage_mode = _first_non_empty(
        summary.get("storage_mode"),
        create_asset.get("storage_mode"),
        load_config.get("storage_mode"),
        upload_config.get("storage_mode"),
        manifest.get("storage_mode"),
    )
    requires_api_key = create_asset.get("requires_api_key_header")
    if requires_api_key not in (None, ""):
        requires_flag: Optional[bool] = bool(requires_api_key)
    else:
        requires_flag = None

    sources = {
        "asset_id": "summary.create_asset|get_asset|manifest" if asset_id else "",
        "asset_slug": "structured-metadata" if asset_slug else "",
        "asset_config": "structured-metadata" if asset_config else "",
        "content_kind": "structured-metadata" if content_kind else "",
        "media_type": "structured-metadata" if media_type else "",
        "transfer_type": "structured-metadata" if transfer_type else "",
    }
    facts = collect_safe_run_facts(loader)
    contradiction = str(facts.get("contradiction") or "")
    if facts.get("asset_id"):
        if asset_id and asset_id != facts["asset_id"]:
            contradiction = contradiction or "asset_id"
        else:
            asset_id = str(facts["asset_id"])
    if facts.get("asset_slug") and not asset_slug:
        asset_slug = str(facts["asset_slug"])
    if facts.get("asset_config_private"):
        asset_config = ""
    elif facts.get("asset_config") and not asset_config:
        asset_config = str(facts["asset_config"])
    if (
        facts.get("asset_origin") == "verified_existing"
        and suffix
        and asset_id.endswith(f"-{suffix}")
        and asset_id not in {CIRCE_ASSET_ID, EBRO_STABLE_ASSET_ID}
    ):
        contradiction = contradiction or "provenance"
    if asset_id == CIRCE_ASSET_ID and facts.get("provider_id") not in {"", "2"}:
        contradiction = contradiction or "provider_id"
    if asset_id in {EBRO_STABLE_ASSET_ID} or (
        asset_slug == EBRO_SLUG and asset_id.endswith(f"-{suffix}") if suffix else False
    ):
        if facts.get("provider_id") not in {"", "1"}:
            contradiction = contradiction or "provider_id"
    if facts.get("reuse_existing") == "1" and facts.get("asset_origin") == "published_this_run":
        contradiction = contradiction or "provenance"
    if facts.get("reuse_existing") == "0" and facts.get("asset_origin") == "verified_existing":
        contradiction = contradiction or "provenance"
    return RunSignals(
        suffix=suffix,
        asset_id=asset_id,
        asset_slug=asset_slug,
        asset_config=asset_config,
        content_kind=content_kind,
        extension=extension,
        media_type=media_type,
        transfer_type=transfer_type,
        workflow_kind=parser.detect_workflow_kind(),
        phases=tuple(parser.phases.keys()),
        requires_api_key_header=requires_flag,
        storage_mode=storage_mode,
        sources=sources,
        asset_origin=str(facts.get("asset_origin") or ""),
        http_method=str(facts.get("http_method") or ""),
        provider_id=str(facts.get("provider_id") or ""),
        created_asset=bool(facts.get("created_asset")),
        post_metadata_only=bool(facts.get("post_metadata_only")),
        contradiction=contradiction,
    )


def _config_path_matches(actual: str, expected_suffix: str) -> bool:
    if not actual or not expected_suffix:
        return False
    normalized_actual = actual.replace("\\", "/")
    normalized_expected = expected_suffix.replace("\\", "/")
    return (
        normalized_actual == normalized_expected
        or normalized_actual.endswith("/" + normalized_expected)
        or normalized_actual.endswith(normalized_expected)
    )


def _matches_any_pattern(value: str, patterns: Tuple[str, ...]) -> bool:
    return bool(value) and any(fnmatch.fnmatchcase(value, pattern) for pattern in patterns)


def _identity_matches(identity: str, signals: RunSignals) -> bool:
    """Require several consistent signals. A name fragment is not enough."""
    if identity == "pre_get":
        slug_ok = signals.asset_slug == PRE_SLUG or signals.asset_id.startswith(f"{PRE_SLUG}-")
        return bool(
            slug_ok
            and signals.asset_origin != "verified_existing"
            and not signals.post_metadata_only
        )
    if identity == "circe_stable":
        return bool(
            signals.asset_id == CIRCE_ASSET_ID
            and signals.asset_origin == "verified_existing"
            and not signals.created_asset
            and signals.provider_id in {"", "2"}
        )
    if identity == "ebro_stable":
        return bool(
            signals.asset_id == EBRO_STABLE_ASSET_ID
            and signals.http_method in {"", "POST"}
            and signals.provider_id in {"", "1"}
            and signals.asset_origin != "verified_existing"
        )
    if identity == "ebro_parallel":
        return bool(
            signals.asset_slug == EBRO_SLUG
            and signals.suffix
            and signals.asset_id == f"{EBRO_SLUG}-{signals.suffix}"
            and signals.http_method == "POST"
            and signals.asset_origin == "published_this_run"
            and signals.post_metadata_only
            and signals.provider_id in {"", "1"}
            and signals.asset_id != EBRO_STABLE_ASSET_ID
        )
    return False


def score_asset(asset: AssetDefinition, signals: RunSignals) -> int:
    if asset.identity and not _identity_matches(asset.identity, signals):
        return 0
    score = 0
    if signals.asset_slug:
        if signals.asset_slug in asset.asset_slugs or _matches_any_pattern(
            signals.asset_slug, asset.asset_slug_patterns
        ):
            score += 100
    if signals.asset_config and any(
        _config_path_matches(signals.asset_config, suffix)
        for suffix in asset.asset_config_suffixes
    ):
        score += 100
    if signals.asset_id:
        id_matched = False
        for prefix in asset.asset_id_prefixes:
            if signals.asset_id == prefix.rstrip("-") or signals.asset_id.startswith(prefix):
                score += 80
                id_matched = True
                break
        if not id_matched and _matches_any_pattern(signals.asset_id, asset.asset_id_patterns):
            score += 80
            id_matched = True
        if not id_matched:
            for slug in asset.asset_slugs:
                if signals.asset_id == slug or signals.asset_id.startswith(f"{slug}-"):
                    score += 80
                    break
            else:
                # Hyphenated PROD ids may still match underscore slug patterns via normalization.
                normalized = signals.asset_id.replace("-", "_")
                if _matches_any_pattern(normalized, asset.asset_slug_patterns):
                    score += 80
    if asset.expected_workflow_kind and signals.workflow_kind == asset.expected_workflow_kind:
        score += 5
    if asset.expected_content_kind and signals.content_kind == asset.expected_content_kind:
        score += 8
    if asset.expected_extension and signals.extension == asset.expected_extension:
        score += 8
    if asset.expected_media_type and signals.media_type == asset.expected_media_type:
        score += 12
    if asset.expected_transfer_type and signals.transfer_type == asset.expected_transfer_type:
        score += 10
    if asset.critical and signals.requires_api_key_header is True:
        score += 8
    if asset.family == "ingestion" and asset.variant == "csv_b2" and signals.storage_mode == "inesdatastore":
        score += 8
    return score


def classify_run(
    loader: EvidenceRunLoader,
    registry: Dict[str, AssetDefinition],
    *,
    slot: Optional[str] = None,
) -> AssetDefinition:
    signals = extract_run_signals(loader)
    slot_id = slot or loader.spec.test_id
    suffix = signals.suffix or loader.spec.suffix
    if signals.contradiction:
        raise ClassificationError(slot_id, suffix, "contradictory", detail=signals.contradiction)
    scored = [(score_asset(asset, signals), asset) for asset in registry.values()]
    strong = [(score, asset) for score, asset in scored if score >= CLASSIFICATION_STRONG_SCORE]
    if not strong:
        raise ClassificationError(slot_id, suffix, "unknown")
    strong.sort(key=lambda item: item[0], reverse=True)
    best_score = strong[0][0]
    winners = [asset for score, asset in strong if score == best_score]
    if len(winners) != 1:
        raise ClassificationError(
            slot_id,
            suffix,
            "ambiguous",
            detail="candidates=" + ",".join(asset.key for asset in winners),
        )
    return winners[0]


def bind_spec_to_asset(spec: TestSpec, asset: AssetDefinition) -> TestSpec:
    sheet_name = f"{spec.test_id}_{asset.sheet_slug}"[:31]
    return replace(
        spec,
        sheet_name=sheet_name,
        workflow=asset.workflow,
        asset_type=asset.asset_type,
        provider_connector=asset.provider_connector,
        consumer_connector=asset.consumer_connector,
        technical_provider_connector=asset.technical_provider_connector,
        technical_consumer_connector=asset.technical_consumer_connector,
        asset_config=asset.asset_config,
        expected_phases=list(asset.expected_phases),
        publication_profile=asset.publication_profile,
        evidence_role=asset.evidence_role,
        asset_key=asset.key,
        family=asset.family,
        variant=asset.variant,
        transport=asset.transport,
        critical=asset.critical,
        display_name=asset.display_name,
        publication_safe=asset.publication_safe,
        expected_content_kind=asset.expected_content_kind,
        expected_extension=asset.expected_extension,
        expected_media_type=asset.expected_media_type,
        expected_transfer_type=asset.expected_transfer_type,
        validator=asset.validator,
    )


def classify_loader(
    loader: EvidenceRunLoader,
    registry: Dict[str, AssetDefinition],
) -> Tuple[EvidenceRunLoader, TestSpec, AssetDefinition]:
    asset = classify_run(loader, registry)
    spec = bind_spec_to_asset(loader.spec, asset)
    loader.spec = spec
    return loader, spec, asset


def _json_from_path(path: Optional[Path]) -> Any:
    if not path or not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _candidate_payload_paths(loader: EvidenceRunLoader) -> List[Path]:
    paths: List[Path] = []
    parser = loader.parser or SummaryParser(loader.summary)
    for phase, filename in (
        ("phase4", "40_data_response.json"),
        ("phase4", "semantic_payload.json"),
        ("phase4b", "storage_object.json"),
        ("phase4b", "semantic_payload.json"),
        ("phase4b", "downloaded.csv"),
        ("phase4", "downloaded.json"),
        ("phase4", "downloaded.csv"),
    ):
        path = loader.run_dir / phase / filename
        if path.exists():
            paths.append(path)
    for step_id in ("save_download", "storage_fetch"):
        found = parser.find_step(step_id)
        if not found:
            continue
        _, step = found
        for key in ("latest_file", "download_file", "artifact"):
            raw = step.get(key)
            if isinstance(raw, str) and raw:
                candidate = Path(raw)
                if not candidate.is_absolute():
                    candidate = loader.run_dir / raw
                if candidate.exists():
                    paths.append(candidate)
    asset_path = loader.latest_asset_path()
    if asset_path:
        paths.append(asset_path)
    unique: List[Path] = []
    seen = set()
    for path in paths:
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        unique.append(path)
    return unique


def _load_first_json_payload(loader: EvidenceRunLoader) -> Tuple[Any, str]:
    for path in _candidate_payload_paths(loader):
        if path.suffix.lower() not in {".json", ""}:
            continue
        data = _json_from_path(path)
        if data is not None:
            return data, path.name
    return None, ""


def _load_first_text_payload(loader: EvidenceRunLoader) -> Tuple[str, str]:
    for path in _candidate_payload_paths(loader):
        if path.suffix.lower() in {".csv", ".txt"} or path.name.endswith("downloaded.csv"):
            try:
                return path.read_text(encoding="utf-8", errors="replace"), path.name
            except Exception:
                continue
    return "", ""


def _phase_findings(loader: EvidenceRunLoader, expected_phases: Sequence[str]) -> List[str]:
    parser = loader.parser or SummaryParser(loader.summary)
    findings: List[str] = []
    for phase in expected_phases:
        if phase not in parser.phases:
            findings.append(f"missing_phase:{phase}")
        elif parser.phase_status(phase) != "ok":
            findings.append(f"phase_not_ok:{phase}")
    return findings


def _transfer_findings(signals: RunSignals, expected: str) -> List[str]:
    if expected and signals.transfer_type and signals.transfer_type != expected:
        return [f"transfer_type:{signals.transfer_type}"]
    if expected and not signals.transfer_type:
        return ["transfer_type:missing"]
    return []


def load_post_metadata_artifacts(
    loader: EvidenceRunLoader,
) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
    """Return (post_result, post_manifest) objects when present."""
    result = _load_json_object(loader.run_dir / "phase4" / "post_result.json")
    manifest = _load_json_object(loader.run_dir / "phase4" / "post_manifest.json")
    return (
        result if isinstance(result, dict) else None,
        manifest if isinstance(manifest, dict) else None,
    )


def is_post_metadata_only_run(loader: EvidenceRunLoader) -> bool:
    """True only when phase4 explicitly declares post_metadata_only semantics."""
    _result, manifest = load_post_metadata_artifacts(loader)
    return bool(manifest) and manifest.get("manifest_kind") == "post_metadata_only"


def _require_equals(findings: List[str], label: str, actual: Any, expected: Any) -> None:
    if actual != expected:
        findings.append(f"{label}:{actual!r}")


def _require_truthy(findings: List[str], label: str, actual: Any) -> None:
    if actual in (None, ""):
        findings.append(f"{label}:missing")


def _require_http_success(findings: List[str], label: str, status: Any) -> None:
    try:
        code = int(status)
    except (TypeError, ValueError):
        findings.append(f"{label}:invalid")
        return
    if code < 200 or code >= 300:
        findings.append(f"{label}:{code}")


def _validate_post_metadata_flags(findings: List[str], prefix: str, payload: Dict[str, Any]) -> None:
    _require_equals(findings, f"{prefix}.operation", payload.get("operation"), "POST")
    _require_equals(findings, f"{prefix}.http_method", payload.get("http_method"), "POST")
    _require_http_success(findings, f"{prefix}.http_status", payload.get("http_status"))
    _require_equals(findings, f"{prefix}.status", payload.get("status"), "ok")
    _require_equals(
        findings, f"{prefix}.request_body_persisted", payload.get("request_body_persisted"), False
    )
    _require_equals(
        findings, f"{prefix}.response_body_persisted", payload.get("response_body_persisted"), False
    )
    _require_equals(
        findings, f"{prefix}.download_persisted", payload.get("download_persisted"), False
    )


def validate_ingestion_api_v2_post_metadata_only(
    loader: EvidenceRunLoader, spec: TestSpec
) -> ValidationResult:
    """Validate explicit POST metadata-only phase4 evidence (no download/sha256)."""
    signals = extract_run_signals(loader)
    findings = _phase_findings(loader, spec.expected_phases or HTTP_PULL_PHASES)
    findings.extend(_transfer_findings(signals, spec.expected_transfer_type or "HttpData-PULL"))
    result, manifest = load_post_metadata_artifacts(loader)
    if result is None:
        findings.append("post_result:missing")
    else:
        _validate_post_metadata_flags(findings, "post_result", result)
    if manifest is None:
        findings.append("post_manifest:missing")
    else:
        _require_equals(
            findings, "post_manifest.manifest_kind", manifest.get("manifest_kind"), "post_metadata_only"
        )
        _validate_post_metadata_flags(findings, "post_manifest", manifest)
        _require_truthy(findings, "post_manifest.asset_id", manifest.get("asset_id"))
        _require_truthy(findings, "post_manifest.agreement_id", manifest.get("agreement_id"))
        _require_truthy(findings, "post_manifest.transfer_id", manifest.get("transfer_id"))
    status = "passed" if not findings else "failed"
    return ValidationResult(
        status=status,
        source="ingestion-api-post-metadata-validator",
        findings=tuple(findings),
    )


def validate_ingestion_api_v2(loader: EvidenceRunLoader, spec: TestSpec) -> ValidationResult:
    """Validate ingestion_api_v2 runs: GET/download or POST metadata-only."""
    if is_post_metadata_only_run(loader):
        return validate_ingestion_api_v2_post_metadata_only(loader, spec)

    signals = extract_run_signals(loader)
    findings = _phase_findings(loader, spec.expected_phases or HTTP_PULL_PHASES)
    findings.extend(_transfer_findings(signals, spec.expected_transfer_type or "HttpData-PULL"))
    payload, source = _load_first_json_payload(loader)
    if payload is None:
        findings.append("json_payload:missing")
        source = source or "missing-payload"
    elif not isinstance(payload, (dict, list)):
        findings.append("json_payload:invalid_type")
    manifest = _load_json_object(loader.run_dir / "phase4" / "download_manifest.json")
    if not manifest:
        findings.append("manifest:missing")
    status = "passed" if not findings else "failed"
    return ValidationResult(status=status, source=source or "ingestion-api-validator", findings=tuple(findings))


def validate_wfs_geojson(loader: EvidenceRunLoader, spec: TestSpec) -> ValidationResult:
    signals = extract_run_signals(loader)
    findings = _phase_findings(loader, spec.expected_phases or HTTP_PULL_PHASES)
    findings.extend(_transfer_findings(signals, spec.expected_transfer_type or "HttpData-PULL"))
    if spec.expected_media_type and signals.media_type and signals.media_type != spec.expected_media_type:
        findings.append(f"media_type:{signals.media_type}")
    payload, source = _load_first_json_payload(loader)
    if not isinstance(payload, dict):
        findings.append("geojson:missing_or_invalid")
    else:
        if payload.get("type") != "FeatureCollection":
            findings.append("geojson:type")
        features = payload.get("features")
        if not isinstance(features, list):
            findings.append("geojson:features")
    status = "passed" if not findings else "failed"
    return ValidationResult(status=status, source=source or "wfs-validator", findings=tuple(findings))


def validate_sparql_results(loader: EvidenceRunLoader, spec: TestSpec) -> ValidationResult:
    signals = extract_run_signals(loader)
    findings = _phase_findings(loader, spec.expected_phases or HTTP_PULL_PHASES)
    findings.extend(_transfer_findings(signals, spec.expected_transfer_type or "HttpData-PULL"))
    expected_media = spec.expected_media_type or "application/sparql-results+json"
    if signals.media_type and signals.media_type != expected_media:
        findings.append(f"media_type:{signals.media_type}")
    payload, source = _load_first_json_payload(loader)
    if not isinstance(payload, dict):
        findings.append("sparql:missing_or_invalid")
    else:
        if "head" not in payload:
            findings.append("sparql:head")
        results = payload.get("results")
        if not isinstance(results, dict):
            findings.append("sparql:results")
        elif "bindings" not in results:
            findings.append("sparql:bindings")
    status = "passed" if not findings else "failed"
    return ValidationResult(status=status, source=source or "sparql-validator", findings=tuple(findings))


def validate_csv_b2_legacy(loader: EvidenceRunLoader, spec: TestSpec) -> ValidationResult:
    signals = extract_run_signals(loader)
    findings = _phase_findings(loader, spec.expected_phases or CSV_B2_PHASES)
    if signals.workflow_kind != "b2":
        findings.append(f"workflow_kind:{signals.workflow_kind}")
    parser = loader.parser or SummaryParser(loader.summary)
    storage = parser.get_step("phase4b", "storage_fetch") or {}
    bytes_value = _first_non_empty(storage.get("bytes"), _find_first_value(
        _load_json_object(loader.run_dir / "phase4b" / "download_manifest.json"),
        {"bytes", "size_bytes", "byte_count"},
    ))
    sha_value = _first_non_empty(storage.get("sha256"), _find_first_value(
        _load_json_object(loader.run_dir / "phase4b" / "download_manifest.json"),
        {"sha256", "sha_256"},
    ))
    if not bytes_value:
        findings.append("bytes:missing")
    if not sha_value:
        findings.append("sha256:missing")
    text, source = _load_first_text_payload(loader)
    if text:
        try:
            sample = next(csv.reader(io.StringIO(text)))
            if len(sample) < 1:
                findings.append("csv:empty_header")
        except Exception:
            findings.append("csv:parse_error")
    elif signals.extension and signals.extension != "csv":
        findings.append(f"extension:{signals.extension}")
    status = "passed" if not findings else "failed"
    return ValidationResult(status=status, source=source or "csv-b2-validator", findings=tuple(findings))


VALIDATORS = {
    "ingestion_api_v2": validate_ingestion_api_v2,
    "wfs_juntas": validate_wfs_geojson,
    "wfs_ciudad": validate_wfs_geojson,
    "sparql": validate_sparql_results,
    "csv_b2_legacy": validate_csv_b2_legacy,
}


def validate_classified_run(loader: EvidenceRunLoader, spec: TestSpec) -> ValidationResult:
    validator = VALIDATORS.get(spec.validator or spec.asset_key)
    if not validator:
        return ValidationResult(status="not_recorded", source="no-validator", findings=())
    return validator(loader, spec)


def slot_inventory_row(
    spec: TestSpec,
    *,
    suffix_value: str,
    validation: Optional[ValidationResult] = None,
) -> Dict[str, Any]:
    return {
        "slot": spec.test_id,
        "asset": spec.display_name,
        "suffix": suffix_value,
        "asset_key": spec.asset_key,
        "asset_variant": spec.asset_key,
        "display_name": spec.display_name,
        "family": spec.family,
        "variant": spec.variant,
        "transport": spec.transport,
        "critical": spec.critical,
        "publication_profile": spec.publication_profile or STANDARD_PUBLICATION_PROFILE,
        "publication_safe": spec.publication_safe,
        "validation_status": validation.status if validation else NOT_FOUND,
        "workflow": spec.workflow,
        "asset_type": spec.asset_type,
    }


def is_minimal_profile(spec: TestSpec) -> bool:
    return spec.publication_profile == MINIMAL_PUBLICATION_PROFILE


def publication_status_label(spec: TestSpec) -> str:
    profile = spec.publication_profile or STANDARD_PUBLICATION_PROFILE
    if spec.publication_safe:
        return profile
    if profile == STANDARD_PUBLICATION_PROFILE:
        return "standard_internal"
    return f"{profile}_internal"


def package_publication_status(specs: Sequence[TestSpec]) -> Dict[str, Any]:
    blockers = [
        f"slot {spec.test_id} uses {publication_status_label(spec)}"
        for spec in specs
        if not spec.publication_safe
    ]
    return {
        "publication_ready": bool(specs) and not blockers,
        "publication_blockers": blockers,
    }
