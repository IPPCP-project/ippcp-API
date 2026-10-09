#!/usr/bin/env python3
"""Classification, traceability and publication-safety regressions. Fixtures only."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))
sys.path.insert(0, str(TOOLS_DIR / "tests"))

from evidence_assets import (  # noqa: E402
    ClassificationError,
    classify_loader,
    load_asset_registry,
)
from evidence_common import (  # noqa: E402
    EvidenceRunLoader,
    PublicationScanner,
    TestSpec,
    extract_minimal_publication_model,
    load_test_config,
)
from evidence_fixtures import (  # noqa: E402
    ASSET_FIXTURES,
    create_asset_run,
    create_ingestion_post_metadata_run,
    create_unknown_run,
    write_json,
)
from package_evidence_bundle import unsafe_publication_member  # noqa: E402

PYTHON = sys.executable
CONFIG_PATH = TOOLS_DIR / "evidence_export.tests.yaml"
PACKAGE_SCRIPT = TOOLS_DIR / "package_evidence_bundle.py"
EBRO_SLUG = "ippcp_ingesta_pull_industrias_ebro_prod"
CIRCE_ASSET_ID = "ippcp-ingesta-pull-circe-prod"
STABLE_EBRO_ASSET_ID = "ippcp-ingesta-pull-industrias-ebro-prod"


def _loader(root: Path, suffix: str) -> EvidenceRunLoader:
    spec = TestSpec(test_id="T1", suffix=suffix, sheet_name="T1")
    return EvidenceRunLoader(
        root, root / "evidencias" / "runs", root / "downloads", spec
    ).load(include_env=False)


class ProfileTraceabilityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = load_test_config(CONFIG_PATH)
        cls.registry = load_asset_registry(cls.config)

    def classify(self, root: Path, suffix: str):
        loader = _loader(root, suffix)
        loader, _spec, asset = classify_loader(loader, self.registry)
        return loader, asset

    def test_pre_wfs_and_sparql_stay_distinct(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            expected = {
                "ingestion_api_v2": "pre_get",
                "wfs_ciudad": "ciudad",
                "wfs_juntas": "juntas",
                "sparql": "results_json",
            }
            for key, variant in expected.items():
                create_asset_run(root, key)
                _loader_obj, asset = self.classify(root, ASSET_FIXTURES[key]["suffix"])
                self.assertEqual(asset.key, key)
                self.assertEqual(asset.variant, variant)
                if key == "ingestion_api_v2":
                    self.assertTrue(asset.publication_safe)
                    self.assertEqual(asset.publication_profile, "minimal_publication")
                else:
                    self.assertFalse(asset.publication_safe)
                    self.assertEqual(asset.publication_profile, "minimal_publication")

    def test_circe_reuse_does_not_require_create_asset(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suffix = "synthetic-circe-reuse"
            run = create_ingestion_post_metadata_run(root, suffix=suffix)
            summary = json.loads((run / "summary.json").read_text(encoding="utf-8"))
            summary["started_at"] = "2026-10-09T15:57:33Z"
            summary["phases"]["phase1"]["steps"] = [
                {
                    "id": "verify_existing_asset",
                    "status": "ok",
                    "asset_origin": "verified_existing",
                    "asset_id": CIRCE_ASSET_ID,
                }
            ]
            summary["phases"]["phase2"]["steps"] = [
                {"id": "negotiation_finalized", "status": "ok", "final_state": "VERIFIED"},
                {"id": "get_contract_agreement", "status": "ok", "http": 200},
            ]
            summary["phases"]["phase3"]["steps"] = [
                {"id": "transfer_type_valid", "status": "ok", "transfer_type": "HttpData-PULL"},
                {"id": "transfer_final_state", "status": "ok", "final_state": "STARTED"},
                {"id": "edr_obtained", "status": "ok", "http": 200, "edr_url": "https://edr-canary.invalid/dataplane"},
            ]
            write_json(run / "summary.json", summary)
            manifest = json.loads((run / "phase4" / "post_manifest.json").read_text(encoding="utf-8"))
            manifest["asset_id"] = CIRCE_ASSET_ID
            manifest["request_body_bytes"] = 315
            manifest["response_bytes"] = 68
            manifest["business_post_count"] = 1
            manifest["auth_candidate_label"] = "authorization_raw"
            manifest["edr_url"] = "https://edr-canary.invalid/dataplane"
            write_json(run / "phase4" / "post_manifest.json", manifest)
            result = json.loads((run / "phase4" / "post_result.json").read_text(encoding="utf-8"))
            result["request_body_bytes"] = 315
            result["response_bytes"] = 68
            result["business_post_count"] = 1
            result["auth_candidate_label"] = "authorization_raw"
            write_json(run / "phase4" / "post_result.json", result)
            (run / "phase1_env.sh").write_text(
                "export PHASE1_ASSET_ORIGIN=verified_existing\n"
                "export ASSET_ID=ippcp-ingesta-pull-circe-prod\n"
                "export ASSET_PROVIDER_ID=2\n"
                "export IPPCP_PHASE1_REUSE_EXISTING=1\n"
                "export INGESTA_API_KEY=CANARY-API-KEY\n"
                "export EDR_URL=https://edr-canary.invalid/dataplane\n",
                encoding="utf-8",
            )
            loader, asset = self.classify(root, suffix)
            self.assertEqual(asset.key, "ingestion_api_circe_prod")
            self.assertNotIn("pre_api_key", asset.asset_config)
            model = extract_minimal_publication_model(loader, loader.spec)
            tech = model.technical_evidence
            self.assertEqual(tech["asset_provenance"], "verified_existing")
            self.assertEqual(tech["asset_id"], CIRCE_ASSET_ID)
            self.assertEqual(tech["run_id"], suffix)
            self.assertEqual(tech["provider_id"], "2")
            self.assertEqual(tech["company_or_subtype"], "circe")
            self.assertEqual(tech["request_body_bytes"], "315")
            self.assertEqual(tech["response_body_bytes"], "68")
            self.assertEqual(tech["business_post_count"], "1")
            self.assertEqual(tech["negotiation_state"], "VERIFIED")
            self.assertEqual(tech["agreement_http_status"], "200")
            self.assertEqual(tech["transfer_state"], "STARTED")
            self.assertEqual(tech["evidence_type"], "post_metadata_only")
            self.assertEqual(tech["execution_date"], "2026-10-09")
            self.assertEqual(model.sha256_value, "not_applicable")
            self.assertFalse(model.sha256_verified)
            blob = json.dumps(tech)
            self.assertNotIn("CANARY-API-KEY", blob)
            self.assertNotIn("edr-canary", blob)
            self.assertNotIn("/Users/", blob)
            self.assertEqual(PublicationScanner.findings(blob), [])

    def test_parallel_ebro_is_distinct_from_pre_and_stable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suffix = "synthetic-ebro-parallel"
            asset_id = f"{EBRO_SLUG}-{suffix}"
            run = create_ingestion_post_metadata_run(root, suffix=suffix)
            summary = json.loads((run / "summary.json").read_text(encoding="utf-8"))
            summary["phases"]["phase1"]["steps"][0].update(
                {
                    "asset_id": asset_id,
                    "asset_slug": EBRO_SLUG,
                    "asset_config": "/Users/example/private/parallel.json",
                    "http_method": "POST",
                    "asset_origin": "published_this_run",
                }
            )
            summary["phases"]["phase2"]["steps"] = [
                {"id": "negotiation_finalized", "status": "ok", "final_state": "AGREED"},
            ]
            write_json(run / "summary.json", summary)
            manifest = json.loads((run / "phase4" / "post_manifest.json").read_text(encoding="utf-8"))
            manifest.update(
                {
                    "asset_id": asset_id,
                    "request_body_bytes": 308,
                    "response_bytes": 68,
                    "business_post_count": 1,
                    "auth_candidate_label": "authorization_raw",
                    "response_media_type": "application/json",
                }
            )
            write_json(run / "phase4" / "post_manifest.json", manifest)
            result = json.loads((run / "phase4" / "post_result.json").read_text(encoding="utf-8"))
            result["request_body_bytes"] = 308
            result["response_bytes"] = 68
            result["business_post_count"] = 1
            write_json(run / "phase4" / "post_result.json", result)
            (run / "phase1_env.sh").write_text(
                "export PHASE1_ASSET_ORIGIN=published_this_run\n"
                f"export ASSET_ID={asset_id}\n"
                "export ASSET_PROVIDER_ID=1\n"
                "export IPPCP_PHASE1_REUSE_EXISTING=0\n"
                "export INGESTA_API_KEY=CANARY-API-KEY\n",
                encoding="utf-8",
            )
            loader, asset = self.classify(root, suffix)
            self.assertEqual(asset.key, "ingestion_api_ebro_parallel")
            self.assertNotIn("pre_api_key", asset.asset_config)
            self.assertFalse(asset.asset_config.startswith("/"))
            model = extract_minimal_publication_model(loader, loader.spec)
            tech = model.technical_evidence
            self.assertEqual(tech["asset_provenance"], "published_this_run")
            self.assertEqual(tech["asset_id"], asset_id)
            self.assertEqual(tech["request_body_bytes"], "308")
            self.assertEqual(tech["response_body_bytes"], "68")
            self.assertEqual(tech["negotiation_state"], "AGREED")
            self.assertNotIn("sha256", json.dumps({k: v for k, v in tech.items() if k != "sha256" and v not in {"not_applicable", "not_recorded"}}))
            self.assertEqual(tech["sha256"], "not_applicable")
            self.assertNotIn("/Users/example", json.dumps(tech))
            self.assertEqual(PublicationScanner.findings(json.dumps(tech)), [])

    def test_stable_ebro_historical_metadata_remains_supported(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            create_ingestion_post_metadata_run(root)
            _loader_obj, asset = self.classify(root, "synthetic-ingestion-post")
            self.assertEqual(asset.key, "ingestion_api_ebro_prod")
            self.assertEqual(asset.asset_config, "asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json")

    def test_conflicting_identifiers_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suffix = "synthetic-conflict"
            run = create_ingestion_post_metadata_run(root, suffix=suffix)
            (run / "phase1_env.sh").write_text(
                "export ASSET_ID=ippcp-ingesta-pull-circe-prod\n"
                "export PHASE1_ASSET_ORIGIN=verified_existing\n",
                encoding="utf-8",
            )
            with self.assertRaises(ClassificationError) as caught:
                self.classify(root, suffix)
            self.assertIn("contradictory", str(caught.exception))
            self.assertNotIn("CANARY", str(caught.exception))

    def test_ebro_substring_alone_is_not_enough(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suffix = "synthetic-not-ebro"
            run = create_ingestion_post_metadata_run(root, suffix=suffix)
            summary = json.loads((run / "summary.json").read_text(encoding="utf-8"))
            summary["phases"]["phase1"]["steps"][0].update(
                {
                    "asset_id": f"ippcp_ingesta_pull_other_ebro_prod-{suffix}",
                    "asset_slug": "ippcp_ingesta_pull_other_ebro_prod",
                    "asset_origin": "published_this_run",
                }
            )
            write_json(run / "summary.json", summary)
            manifest = json.loads((run / "phase4" / "post_manifest.json").read_text(encoding="utf-8"))
            manifest["asset_id"] = f"ippcp_ingesta_pull_other_ebro_prod-{suffix}"
            write_json(run / "phase4" / "post_manifest.json", manifest)
            with self.assertRaises(ClassificationError) as caught:
                self.classify(root, suffix)
            self.assertIn("unknown", str(caught.exception))

    def test_parallel_reuse_provenance_is_contradictory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suffix = "synthetic-parallel-reuse"
            asset_id = f"{EBRO_SLUG}-{suffix}"
            run = create_ingestion_post_metadata_run(root, suffix=suffix)
            summary = json.loads((run / "summary.json").read_text(encoding="utf-8"))
            summary["phases"]["phase1"]["steps"][0].update(
                {"asset_id": asset_id, "asset_slug": EBRO_SLUG, "http_method": "POST"}
            )
            write_json(run / "summary.json", summary)
            manifest = json.loads((run / "phase4" / "post_manifest.json").read_text(encoding="utf-8"))
            manifest["asset_id"] = asset_id
            write_json(run / "phase4" / "post_manifest.json", manifest)
            (run / "phase1_env.sh").write_text(
                "export PHASE1_ASSET_ORIGIN=verified_existing\n"
                f"export ASSET_ID={asset_id}\n"
                "export IPPCP_PHASE1_REUSE_EXISTING=1\n",
                encoding="utf-8",
            )
            with self.assertRaises(ClassificationError):
                self.classify(root, suffix)

    def test_get_sha_and_negotiation_state_are_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run = create_asset_run(root, "sparql")
            summary = json.loads((run / "summary.json").read_text(encoding="utf-8"))
            summary["phases"]["phase2"]["steps"] = [
                {"id": "negotiation_finalized", "status": "ok", "final_state": "VERIFYING"},
                {"id": "get_contract_agreement", "status": "ok", "http": 200},
            ]
            summary["phases"]["phase3"]["steps"].append(
                {"id": "edr_obtained", "status": "ok", "http": 200}
            )
            write_json(run / "summary.json", summary)
            (run / "phase4" / "40_data_response.http").write_text("200\n", encoding="utf-8")
            loader, asset = self.classify(root, ASSET_FIXTURES["sparql"]["suffix"])
            self.assertEqual(asset.key, "sparql")
            model = extract_minimal_publication_model(loader, loader.spec)
            self.assertEqual(model.technical_evidence["negotiation_state"], "VERIFYING")
            self.assertEqual(model.technical_evidence["sha256"], "b" * 64)
            self.assertEqual(model.sha256_value, "b" * 64)
            self.assertTrue(model.sha256_verified)
            self.assertEqual(model.byte_count, 32)
            self.assertEqual(model.technical_evidence["data_plane_http_status"], "200")
            self.assertEqual(model.technical_evidence["edr_http_status"], "200")

    def test_identifiers_and_digests_are_not_false_secrets(self) -> None:
        sample = "\n".join(
            [
                "synthetic-run",
                "1791565384",
                CIRCE_ASSET_ID,
                f"{EBRO_SLUG}-1791565384",
                "a" * 64,
                STABLE_EBRO_ASSET_ID,
            ]
        )
        self.assertEqual(PublicationScanner.findings(sample), [])
        self.assertIn("concrete_url", PublicationScanner.findings("https://edr-canary.invalid/dataplane"))
        self.assertIn("jwt_like_token", PublicationScanner.findings("eyJcanaryprefixvalue0123456789"))

    def test_unknown_field_and_unsafe_member_policy(self) -> None:
        self.assertTrue(unsafe_publication_member("ippcp_evidence_package/T1/summary.json"))
        self.assertTrue(unsafe_publication_member("ippcp_evidence_package/T1/jwt_claims_provider.json"))
        self.assertTrue(unsafe_publication_member("ippcp_evidence_package/T1/00_context.txt"))
        self.assertTrue(unsafe_publication_member("ippcp_evidence_package/T1/30_edr_dataaddress_redacted.json"))
        self.assertTrue(unsafe_publication_member("ippcp_evidence_package/T1/phase3_env.sh"))
        self.assertFalse(unsafe_publication_member("ippcp_evidence_package/T1/sanitized_summary.json"))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            create_asset_run(root, "csv_b2_legacy")
            output = root / "internal.zip"
            result = subprocess.run(
                [
                    PYTHON,
                    str(PACKAGE_SCRIPT),
                    "--repo-root",
                    str(root),
                    "--config",
                    str(CONFIG_PATH),
                    "--tests",
                    f"T1={ASSET_FIXTURES['csv_b2_legacy']['suffix']}",
                    "--output",
                    str(output),
                    "--strict",
                ],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                status = json.loads(archive.read("ippcp_evidence_package/package_status.json"))
            self.assertTrue(any(name.endswith("/summary.json") for name in names))
            self.assertFalse(status["publication_ready"])
            self.assertTrue(any("standard_internal" in item for item in status["publication_blockers"]))
            self.assertTrue(any("unsafe raw member" in item for item in status["publication_blockers"]))

    def test_unknown_run_still_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            create_unknown_run(root)
            with self.assertRaises(ClassificationError):
                self.classify(root, "synthetic-unknown")


if __name__ == "__main__":
    unittest.main()
