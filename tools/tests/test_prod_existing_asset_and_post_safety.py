#!/usr/bin/env python3
"""Offline tests for existing-asset verification and single-attempt PROD POST.

Synthetic fixtures only. These tests do not read production payloads or call
the connector.
"""

from __future__ import annotations

import json
import os
import subprocess
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PHASE1 = REPO_ROOT / "scripts/phase1_provider_publish.sh"
PHASE2 = REPO_ROOT / "scripts/phase2_consumer_negotiate.sh"
BASH_BIN = next(
    (
        candidate
        for candidate in (
            os.environ.get("BASH_BIN"),
            "/usr/local/bin/bash",
            "/opt/homebrew/bin/bash",
            "bash",
        )
        if candidate and (candidate == "bash" or Path(candidate).exists())
    ),
    "bash",
)
CIRCE_ASSET = "ippcp-ingesta-pull-circe-prod"
EBRO_ASSET = "ippcp-ingesta-pull-industrias-ebro-prod"
EBRO_PARALLEL_SLUG = "ippcp_ingesta_pull_industrias_ebro_prod"
EBRO_PARALLEL_CONFIG = (
    REPO_ROOT.parent
    / "ippcp-demo-local-backup"
    / "configs"
    / "ingesta_api_pull_industrias_ebro_prod_parallel.json"
)
EBRO_CANONICAL_CONFIG = (
    REPO_ROOT / "asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json"
)
PARALLEL_SUFFIX = "1000000001"
SELECTOR = "https://w3id.org/edc/v0.0.1/ns/id"
EBRO_BODY = '{"year":2026,"centers":[{"centerId":7,"values":[]}]}'
CIRCE_BODY = '{"year":2026,"centers":[{"districtCode":"D-TEST","values":[]}]}'


def _parallel_context(
    *,
    config: str | None = None,
    provider: str = "1",
    method: str = "POST",
    proxy: str = "1",
    suffix: str = PARALLEL_SUFFIX,
    asset_id: str | None = None,
    slug: str = EBRO_PARALLEL_SLUG,
) -> str:
    resolved = asset_id if asset_id is not None else f"{EBRO_PARALLEL_SLUG}-{suffix}"
    config_path = config if config is not None else str(EBRO_PARALLEL_CONFIG)
    return textwrap.dedent(
        f"""
        export ASSET_CONFIG={json.dumps(config_path)}
        export SUFFIX={json.dumps(suffix)}
        export ASSET_SLUG={json.dumps(slug)}
        export ASSET_ID={json.dumps(resolved)}
        export ASSET_PROVIDER_ID={json.dumps(provider)}
        export ASSET_HTTP_METHOD={json.dumps(method)}
        export ASSET_PROXY_BODY={json.dumps(proxy)}
        """
    )


def _run_bash(script: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    merged.pop("IPPCP_PHASE1_REUSE_EXISTING", None)
    merged.pop("PHASE1_ASSET_ORIGIN", None)
    merged.pop("PHASE1_REUSE_IDS_VERIFIED", None)
    merged.pop("PHASE1_REUSE_SUFFIX", None)
    merged.pop("PHASE1_REUSE_ASSET_ID", None)
    merged.pop("INGESTA_API_KEY", None)
    merged.pop("INGESTA_API_PROVIDER_ID", None)
    merged.pop("ASSET_PROVIDER_ID", None)
    merged.pop("EDR_URL", None)
    if env:
        merged.update(env)
    return subprocess.run(
        [BASH_BIN, "-c", script],
        cwd=str(REPO_ROOT),
        env=merged,
        text=True,
        capture_output=True,
        check=False,
    )


def _asset_doc(
    asset_id: str,
    *,
    method: str | None = "POST",
    proxy_body: object = "true",
    provider_id: str = "2",
    api_key: str | None = "synthetic-api-key-not-real",
    extra: dict | None = None,
) -> dict:
    data_address: dict = {"type": "HttpData"}
    if method is not None:
        data_address["method"] = method
    if proxy_body is not None:
        data_address["proxyBody"] = proxy_body
    data_address["header:X-Provider-Id"] = provider_id
    if api_key is not None:
        data_address["header:X-Api-Key"] = api_key
    if extra:
        data_address.update(extra)
    return {"@id": asset_id, "dataAddress": data_address}


def _contract(asset_id: str, cd_id: str = "cd-existing") -> dict:
    return {
        "@id": cd_id,
        "accessPolicyId": "access-existing",
        "contractPolicyId": "contract-existing",
        "assetsSelector": [
            {
                "operandLeft": SELECTOR,
                "operator": "=",
                "operandRight": asset_id,
            }
        ],
    }


class ExistingAssetModeTests(unittest.TestCase):
    def test_reuse_mode_disabled_by_default_and_publish_ids_unchanged(self) -> None:
        script = textwrap.dedent(
            """
            set -euo pipefail
            unset IPPCP_PHASE1_REUSE_EXISTING PHASE1_ASSET_ORIGIN PHASE1_REUSE_IDS_VERIFIED || true
            source scripts/phase1_provider_publish.sh
            source scripts/lib_common.sh
            [[ "$(_phase1_selected_mode)" == "publish" ]]
            export SUFFIX=getflow
            export ASSET_ID_CUSTOM=0
            export CD_ID=cd-should-not-survive
            export ACCESS_POLICY_ID=access-should-not-survive
            lib_derive_phase1_ids
            [[ "${CD_ID}" == "cd-getflow" ]]
            [[ "${ACCESS_POLICY_ID}" == "access-getflow" ]]
            [[ "${CONTRACT_POLICY_ID}" == "contract-getflow" ]]
            [[ "${VOCAB_ID}" == "vocab-getflow" ]]
            [[ "${ASSET_ID}" == "asset-getflow" ]]
            """
        )
        result = _run_bash(script)
        self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)
        phase1 = PHASE1.read_text(encoding="utf-8")
        phase2 = PHASE2.read_text(encoding="utf-8")
        self.assertIn('operandLeft": "https://w3id.org/edc/v0.0.1/ns/id"', phase1)
        self.assertIn("/management/v3/contractdefinitions/${CD_ID}", phase1)
        self.assertIn('operandLeft": "https://w3id.org/edc/v0.0.1/ns/id"', phase2)

    def test_get_profile_cannot_enable_reuse_mode(self) -> None:
        script = textwrap.dedent(
            """
            set -euo pipefail
            source scripts/phase1_provider_publish.sh
            export IPPCP_PHASE1_REUSE_EXISTING=1
            export ASSET_ID=asset-wfs-city
            export ASSET_HTTP_METHOD=GET
            export ASSET_PROXY_BODY=1
            export ASSET_REQUIRES_API_KEY_HEADER=1
            export ASSET_PROVIDER_ID=1
            if _phase1_assert_reuse_profile_allowed; then
              exit 10
            fi
            """
        )
        result = _run_bash(script)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual(result.returncode, 10)
        self.assertIn("solo admite los assets PROD POST", result.stderr)

    def test_published_asset_checks_and_contract_selection(self) -> None:
        cases = (
            ("ok", _asset_doc(CIRCE_ASSET), "access-existing", 0),
            ("missing", {**_asset_doc(CIRCE_ASSET), "@id": "other-asset"}, "", 1),
            ("method-get", _asset_doc(CIRCE_ASSET, method="GET"), "", 1),
            ("method-missing", _asset_doc(EBRO_ASSET, method=None, provider_id="1", extra={"proxyMethod": True}), "", 1),
            ("provider", _asset_doc(CIRCE_ASSET, provider_id="9"), "", 1),
            ("proxy-off", _asset_doc(CIRCE_ASSET, proxy_body=False), "", 1),
            ("proxy-absent", _asset_doc(CIRCE_ASSET, proxy_body=None), "", 1),
            ("no-key", _asset_doc(CIRCE_ASSET, api_key=None), "", 1),
        )
        for name, document, _unused, expect_fail in cases:
            with self.subTest(name=name):
                self._verify_asset(document, expect_fail=bool(expect_fail), provider="1" if name == "method-missing" else "2", asset_id=document["@id"] if name != "missing" else CIRCE_ASSET)

        with self.subTest(name="selector-mismatch"):
            self._select_contracts([_contract("other-asset")], expect_fail=True, needle="no hay una contract definition")
        with self.subTest(name="ambiguous"):
            self._select_contracts([_contract(CIRCE_ASSET, "cd-a"), _contract(CIRCE_ASSET, "cd-b")], expect_fail=True, needle="ambigua")
        with self.subTest(name="missing-contract"):
            self._select_contracts([], expect_fail=True, needle="no hay una contract definition")
        with self.subTest(name="unique-contract"):
            self._select_contracts([_contract("other-asset", "cd-other"), _contract(CIRCE_ASSET, "cd-real")], expect_fail=False)

    def _verify_asset(self, document: dict, *, expect_fail: bool, provider: str, asset_id: str) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "asset.json"
            path.write_text(json.dumps(document), encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase1_provider_publish.sh
                export ASSET_ID={json.dumps(asset_id)}
                export ASSET_PROVIDER_ID={json.dumps(provider)}
                _phase1_verify_published_asset_file {json.dumps(str(path))}
                """
            )
            result = _run_bash(script)
            if expect_fail:
                self.assertNotEqual(result.returncode, 0, msg=result.stderr + result.stdout)
            else:
                self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def _select_contracts(self, documents: list[dict], *, expect_fail: bool, needle: str = "") -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "list.json"
            dest = Path(tmp) / "selected.json"
            src.write_text(json.dumps(documents), encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase1_provider_publish.sh
                export ASSET_ID={json.dumps(CIRCE_ASSET)}
                _phase1_select_unique_contract_file {json.dumps(str(src))} {json.dumps(str(dest))}
                [[ "$(jq -r '."@id"' {json.dumps(str(dest))})" == "cd-real" ]]
                """
            )
            result = _run_bash(script)
            if expect_fail:
                self.assertNotEqual(result.returncode, 0, msg=result.stderr + result.stdout)
                if needle:
                    self.assertIn(needle, result.stderr)
            else:
                self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def test_offer_must_be_use_without_obligations(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            missing = root / "missing.json"
            invalid = root / "invalid.json"
            valid = root / "valid.json"
            offer = root / "offer.json"
            missing.write_text(json.dumps({"@id": CIRCE_ASSET, "name": "synthetic"}), encoding="utf-8")
            invalid.write_text(
                json.dumps(
                    {
                        "permission": [{"action": "USE"}],
                        "obligation": [{"action": "notify"}],
                        "prohibition": [],
                    }
                ),
                encoding="utf-8",
            )
            valid.write_text(
                json.dumps(
                    {
                        "@id": CIRCE_ASSET,
                        "hasPolicy": {
                            "permission": [{"action": "USE"}],
                            "obligation": [],
                            "prohibition": [],
                        },
                    }
                ),
                encoding="utf-8",
            )
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase1_provider_publish.sh
                export ASSET_ID={json.dumps(CIRCE_ASSET)}
                if ( _phase1_extract_offer_policy {json.dumps(str(missing))} {json.dumps(str(offer))} ); then
                  exit 10
                fi
                if ( _phase1_validate_offer_policy {json.dumps(str(invalid))} ); then
                  exit 11
                fi
                _phase1_extract_offer_policy {json.dumps(str(valid))} {json.dumps(str(offer))}
                _phase1_validate_offer_policy {json.dumps(str(offer))}
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def test_verified_ids_survive_handoff_and_stale_ids_do_not(self) -> None:
        script = textwrap.dedent(
            f"""
            set -euo pipefail
            source scripts/lib_common.sh
            export IPPCP_PHASE1_REUSE_EXISTING=1
            export SUFFIX=run-new
            export ASSET_ID_CUSTOM=1
            export ASSET_ID={json.dumps(CIRCE_ASSET)}
            export CD_ID=cd-from-old-run
            export ACCESS_POLICY_ID=access-old
            export CONTRACT_POLICY_ID=contract-old
            export PHASE1_ASSET_ORIGIN=verified_existing
            export PHASE1_REUSE_IDS_VERIFIED=1
            export PHASE1_REUSE_SUFFIX=run-old
            export PHASE1_REUSE_ASSET_ID={json.dumps(CIRCE_ASSET)}
            lib_derive_phase1_ids
            [[ -z "${{CD_ID:-}}" ]]
            [[ -z "${{ACCESS_POLICY_ID:-}}" ]]
            export CD_ID=cd-verified-circe
            export ACCESS_POLICY_ID=access-verified
            export CONTRACT_POLICY_ID=contract-verified
            export PHASE1_ASSET_ORIGIN=verified_existing
            export PHASE1_REUSE_IDS_VERIFIED=1
            export PHASE1_REUSE_SUFFIX=run-new
            export PHASE1_REUSE_ASSET_ID={json.dumps(CIRCE_ASSET)}
            lib_derive_phase1_ids
            [[ "${{CD_ID}}" == "cd-verified-circe" ]]
            [[ "${{ACCESS_POLICY_ID}}" == "access-verified" ]]
            [[ "${{CONTRACT_POLICY_ID}}" == "contract-verified" ]]
            [[ "${{ASSET_ID}}" == {json.dumps(CIRCE_ASSET)} ]]
            unset VOCAB_ID || true
            lib_require_vars_group LIB_VARS_PHASE1
            """
        )
        result = _run_bash(script)
        self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def test_reuse_verification_reads_without_publication(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            phase1_dir = Path(tmp) / "phase1"
            calls = Path(tmp) / "calls.txt"
            phase1_dir.mkdir()
            asset = _asset_doc(CIRCE_ASSET)
            asset["dataAddress"]["header:X-Api-Key"] = "<redacted>"
            contract = _contract(CIRCE_ASSET, "cd-existing-circe")
            contract["accessPolicyId"] = "access-existing-circe"
            contract["contractPolicyId"] = "contract-existing-circe"
            catalog = {
                "dcat:dataset": {
                    "@id": CIRCE_ASSET,
                    "hasPolicy": {
                        "@id": "offer-synthetic",
                        "permission": [{"action": "USE"}],
                        "obligation": [],
                        "prohibition": [],
                    },
                }
            }
            fixtures = Path(tmp) / "fixtures"
            fixtures.mkdir()
            (fixtures / "asset.json").write_text(json.dumps(asset), encoding="utf-8")
            (fixtures / "contracts.json").write_text(json.dumps([contract]), encoding="utf-8")
            (fixtures / "contract.json").write_text(json.dumps(contract), encoding="utf-8")
            (fixtures / "access.json").write_text(json.dumps({"@id": "access-existing-circe"}), encoding="utf-8")
            (fixtures / "policy.json").write_text(json.dumps({"@id": "contract-existing-circe"}), encoding="utf-8")
            (fixtures / "catalog.json").write_text(json.dumps(catalog), encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase1_provider_publish.sh
                source endpoints.sh
                export IPPCP_PHASE1_REUSE_EXISTING=1
                export PHASE1_SUPPRESS_SUMMARY=1
                export SUFFIX=reuse-suffix
                export ASSET_ID={json.dumps(CIRCE_ASSET)}
                export ASSET_ID_CUSTOM=1
                export ASSET_HTTP_METHOD=POST
                export ASSET_PROXY_BODY=1
                export ASSET_REQUIRES_API_KEY_HEADER=1
                export ASSET_PROVIDER_ID=2
                export PROVIDER_BASE=https://connector.invalid
                export PROVIDER_PROTOCOL=https://connector.invalid/protocol
                export PROVIDER=provider-synthetic
                export PROVIDER_JWT=synthetic-jwt
                export PHASE1_DIR={json.dumps(str(phase1_dir))}
                export FIXTURES={json.dumps(str(fixtures))}
                export CALLS={json.dumps(str(calls))}
                : > "${{CALLS}}"
                _phase1_curl_json_redacted() {{
                  local artifact_base="$1"
                  shift
                  local method="GET" url=""
                  while [[ $# -gt 0 ]]; do
                    case "$1" in
                      -X) method="$2"; shift 2 ;;
                      -H|-d) shift 2 ;;
                      http*|https*) url="$1"; shift ;;
                      *) shift ;;
                    esac
                  done
                  printf '%s %s\\n' "${{method}}" "${{url}}" >> "${{CALLS}}"
                  local fixture="${{FIXTURES}}/asset.json"
                  case "${{url}}" in
                    */management/v3/assets/*) fixture="${{FIXTURES}}/asset.json" ;;
                    */contractdefinitions/request) fixture="${{FIXTURES}}/contracts.json" ;;
                    */contractdefinitions/*) fixture="${{FIXTURES}}/contract.json" ;;
                    */policydefinitions/access-existing-circe) fixture="${{FIXTURES}}/access.json" ;;
                    */policydefinitions/contract-existing-circe) fixture="${{FIXTURES}}/policy.json" ;;
                    */catalog/request) fixture="${{FIXTURES}}/catalog.json" ;;
                  esac
                  cp "${{fixture}}" "${{artifact_base}}.json"
                  printf '200\\n' > "${{artifact_base}}.http"
                }}
                _phase1_run_existing_asset_verification
                [[ "${{CD_ID}}" == "cd-existing-circe" ]]
                [[ "${{ACCESS_POLICY_ID}}" == "access-existing-circe" ]]
                [[ "${{CONTRACT_POLICY_ID}}" == "contract-existing-circe" ]]
                [[ "${{PHASE1_ASSET_ORIGIN}}" == "verified_existing" ]]
                [[ "${{PHASE1_REUSE_SUFFIX}}" == "reuse-suffix" ]]
                jq -e '.create_asset == "not_executed" and .published_this_run == false' \\
                  "${{PHASE1_DIR}}/existing_asset_verification.json" >/dev/null
                if grep -E 'POST .*/management/v3/assets($|[^/])' "${{CALLS}}"; then exit 21; fi
                if grep -E 'POST .*/management/vocabularies($|[^/])' "${{CALLS}}"; then exit 22; fi
                if grep -E 'POST .*/management/v3/policydefinitions($|[^/])' "${{CALLS}}"; then exit 23; fi
                if grep -E 'POST .*/management/v3/contractdefinitions($|[^/])' "${{CALLS}}"; then exit 24; fi
                grep -q 'GET https://connector.invalid/management/v3/assets/' "${{CALLS}}"
                grep -q 'POST https://connector.invalid/management/v3/contractdefinitions/request' "${{CALLS}}"
                grep -q 'POST https://connector.invalid/management/v3/catalog/request' "${{CALLS}}"
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def test_missing_asset_stops_before_publication(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            phase1_dir = Path(tmp) / "phase1"
            calls = Path(tmp) / "calls.txt"
            phase1_dir.mkdir()
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase1_provider_publish.sh
                source endpoints.sh
                export IPPCP_PHASE1_REUSE_EXISTING=1
                export PHASE1_SUPPRESS_SUMMARY=1
                export SUFFIX=missing-asset
                export ASSET_ID={json.dumps(CIRCE_ASSET)}
                export ASSET_ID_CUSTOM=1
                export ASSET_HTTP_METHOD=POST
                export ASSET_PROXY_BODY=1
                export ASSET_REQUIRES_API_KEY_HEADER=1
                export ASSET_PROVIDER_ID=2
                export PROVIDER_BASE=https://connector.invalid
                export PROVIDER=provider-synthetic
                export PROVIDER_JWT=synthetic-jwt
                export PHASE1_DIR={json.dumps(str(phase1_dir))}
                export CALLS={json.dumps(str(calls))}
                : > "${{CALLS}}"
                _phase1_curl_json_redacted() {{
                  local artifact_base="$1"
                  shift
                  local method="GET" url=""
                  while [[ $# -gt 0 ]]; do
                    case "$1" in
                      -X) method="$2"; shift 2 ;;
                      -H|-d) shift 2 ;;
                      http*|https*) url="$1"; shift ;;
                      *) shift ;;
                    esac
                  done
                  printf '%s %s\\n' "${{method}}" "${{url}}" >> "${{CALLS}}"
                  printf '{{}}\n' > "${{artifact_base}}.json"
                  printf '404\\n' > "${{artifact_base}}.http"
                  return 1
                }}
                if _phase1_run_existing_asset_verification; then
                  exit 10
                fi
                """
            )
            result = _run_bash(script)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotEqual(result.returncode, 10)
            self.assertIn("asset existente no encontrado", result.stderr)
            calls_text = calls.read_text(encoding="utf-8")
            self.assertNotIn("POST ", calls_text)
            self.assertIn("GET ", calls_text)


class PostSafetyTests(unittest.TestCase):
    def _post_env(self, root: Path, *, http_code: str = "200", curl_exit: str = "0") -> str:
        phase4 = root / "phase4"
        phase4.mkdir()
        body = root / "body.json"
        body.write_text('{"marker":"POST-BODY-CANARY-7c2","synthetic":true}', encoding="utf-8")
        count = root / "post_count.txt"
        count.write_text("", encoding="utf-8")
        return textwrap.dedent(
            f"""
            set -euo pipefail
            source scripts/phase4_save_download.sh
            export PHASE4_DIR={json.dumps(str(phase4))}
            export SUFFIX=post-suffix
            export ASSET_ID=asset-post-safety
            export ASSET_HTTP_METHOD=POST
            export ASSET_CONTENT_KIND=json
            export ASSET_EXTENSION=json
            export ASSET_MEDIA_TYPE=application/json
            export INGESTA_API_REQUEST_BODY_FILE={json.dumps(str(body))}
            export EDR_URL=https://data-plane.invalid/dataplane
            export PHASE4_EDR_AUTH_KEY=X-Test-Key
            export PHASE4_EDR_AUTH_CODE=synthetic-code
            unset PHASE4_POST_AUTH_LABEL || true
            export PHASE4_EDR_AUTHORIZATION=
            export PHASE4_EDR_AUTH_TYPE=
            export POST_COUNT={json.dumps(str(count))}
            export MOCK_HTTP={json.dumps(http_code)}
            export MOCK_EXIT={json.dumps(curl_exit)}
            curl() {{
              local method="" out=""
              local previous="" arg
              for arg in "$@"; do
                if [[ "${{previous}}" == "-X" ]]; then method="${{arg}}"; fi
                if [[ "${{previous}}" == "-o" ]]; then out="${{arg}}"; fi
                previous="${{arg}}"
              done
              if [[ "${{method}}" == "POST" ]]; then
                printf 'x\\n' >> "${{POST_COUNT}}"
                if [[ -n "${{out}}" ]]; then
                  printf '%s' '{{"response_canary":"RESP-CANARY-7c2"}}' > "${{out}}"
                fi
                if [[ "${{MOCK_EXIT}}" != "0" ]]; then
                  return "${{MOCK_EXIT}}"
                fi
                printf '%s\\t%s' "${{MOCK_HTTP}}" "application/json"
                return 0
              fi
              printf 'unexpected GET in POST test\\n' >&2
              return 9
            }}
            """
        )

    def test_successful_post_is_single_and_rerun_is_blocked(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            first = self._post_env(root)
            script = first + textwrap.dedent(
                f"""
                _phase4_consume_data_with_auth_candidates
                [[ "$(grep -c . {json.dumps(str(root / "post_count.txt"))})" == "1" ]]
                jq -e '.business_post_count == 1 and .post_attempt_consumed == true and .outcome == "http_2xx"' \\
                  {json.dumps(str(root / "phase4" / "42_data_attempts_summary.json"))} >/dev/null
                if grep -R -F 'POST-BODY-CANARY-7c2' {json.dumps(str(root / "phase4"))}; then exit 11; fi
                if grep -R -F 'RESP-CANARY-7c2' {json.dumps(str(root / "phase4"))}; then exit 12; fi
                test -f {json.dumps(str(root / "phase4" / "post_attempt_consumed.json"))}
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

            again = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export PHASE4_DIR={json.dumps(str(root / "phase4"))}
                export SUFFIX=post-suffix
                export ASSET_ID=asset-post-safety
                export ASSET_HTTP_METHOD=POST
                export ASSET_CONTENT_KIND=json
                export ASSET_EXTENSION=json
                export ASSET_MEDIA_TYPE=application/json
                export INGESTA_API_REQUEST_BODY_FILE={json.dumps(str(root / "body.json"))}
                export EDR_URL=https://data-plane.invalid/dataplane
                export PHASE4_EDR_AUTH_KEY=X-Test-Key
                export PHASE4_EDR_AUTH_CODE=synthetic-code
                export POST_COUNT={json.dumps(str(root / "post_count.txt"))}
                curl() {{ printf 'x\\n' >> "${{POST_COUNT}}"; printf '200\\tapplication/json'; return 0; }}
                _phase4_consume_data_with_auth_candidates
                """
            )
            second_result = _run_bash(again)
            self.assertNotEqual(second_result.returncode, 0)
            self.assertIn("ya fue intentado", second_result.stderr)
            self.assertEqual((root / "post_count.txt").read_text(encoding="utf-8").count("\n"), 1)

    def test_parallel_profile_uses_single_post_path(self) -> None:
        import tempfile

        phase4_text = (REPO_ROOT / "scripts/phase4_save_download.sh").read_text(encoding="utf-8")
        once = phase4_text.split("_phase4_consume_prod_post_once()", 1)[1].split(
            "_phase4_consume_data_with_auth_candidates()", 1
        )[0]
        select_at = once.index("_phase4_select_post_auth_candidate")
        marker_at = once.index('_phase4_write_post_attempt_marker "pending"')
        curl_at = once.index("curl -sS --retry 0")
        self.assertLess(select_at, marker_at)
        self.assertLess(marker_at, curl_at)
        self.assertIn('manifest_kind: "post_metadata_only"', phase4_text)
        self.assertIn("request_body_persisted: false", phase4_text)
        self.assertIn("response_body_persisted: false", phase4_text)
        consume = phase4_text.split("_phase4_consume_data_with_auth_candidates()", 1)[1]
        post_return = consume.index('if [[ "${PHASE4_HTTP_METHOD}" == "POST" ]]; then')
        loop_guard = consume.index("POST phase4 no puede entrar en el bucle de candidatos")
        self.assertLess(post_return, loop_guard)

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            phase4 = root / "phase4"
            phase4.mkdir()
            body = root / "body.json"
            body.write_text(EBRO_BODY, encoding="utf-8")
            count = root / "post_count.txt"
            count.write_text("", encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export PHASE4_DIR={json.dumps(str(phase4))}
                export ASSET_CONTENT_KIND=json
                export ASSET_EXTENSION=json
                export ASSET_MEDIA_TYPE=application/json
                export INGESTA_API_REQUEST_BODY_FILE={json.dumps(str(body))}
                export EDR_URL=https://data-plane.invalid/dataplane
                export PHASE4_EDR_AUTH_KEY=X-Test-Key
                export PHASE4_EDR_AUTH_CODE=synthetic-code
                unset PHASE4_POST_AUTH_LABEL || true
                export PHASE4_EDR_AUTHORIZATION=
                export PHASE4_EDR_AUTH_TYPE=
                export POST_COUNT={json.dumps(str(count))}
                {_parallel_context()}
                curl() {{
                  local method="" out="" previous="" arg
                  for arg in "$@"; do
                    if [[ "${{previous}}" == "-X" ]]; then method="${{arg}}"; fi
                    if [[ "${{previous}}" == "-o" ]]; then out="${{arg}}"; fi
                    previous="${{arg}}"
                  done
                  if [[ "${{method}}" == "POST" ]]; then
                    printf 'x\\n' >> "${{POST_COUNT}}"
                    if [[ -n "${{out}}" ]]; then
                      printf '%s' '{{"response_canary":"RESP-CANARY-7c2"}}' > "${{out}}"
                    fi
                    printf '%s\\t%s' "200" "application/json"
                    return 0
                  fi
                  printf 'unexpected GET in POST test\\n' >&2
                  return 9
                }}
                _phase4_consume_data_with_auth_candidates
                [[ "$(grep -c . {json.dumps(str(count))})" == "1" ]]
                jq -e '.business_post_count == 1 and .post_attempt_consumed == true and .request_body_persisted == false and .response_body_persisted == false' \\
                  {json.dumps(str(phase4 / "42_data_attempts_summary.json"))} >/dev/null
                if grep -R -F '"centerId"' {json.dumps(str(phase4))}; then exit 11; fi
                if grep -R -F 'RESP-CANARY-7c2' {json.dumps(str(phase4))}; then exit 12; fi
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)
            again = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export PHASE4_DIR={json.dumps(str(phase4))}
                export ASSET_CONTENT_KIND=json
                export INGESTA_API_REQUEST_BODY_FILE={json.dumps(str(body))}
                export EDR_URL=https://data-plane.invalid/dataplane
                export PHASE4_EDR_AUTH_KEY=X-Test-Key
                export PHASE4_EDR_AUTH_CODE=synthetic-code
                export PHASE4_EDR_AUTHORIZATION=
                export PHASE4_EDR_AUTH_TYPE=
                {_parallel_context()}
                curl() {{ printf 'second\\n' >> {json.dumps(str(count))}; printf '200\\tapplication/json'; return 0; }}
                _phase4_consume_data_with_auth_candidates
                """
            )
            second = _run_bash(again)
            self.assertNotEqual(second.returncode, 0)
            self.assertIn("ya fue intentado", second.stderr)
            self.assertEqual(count.read_text(encoding="utf-8").count("\n"), 1)

    def test_failed_post_does_not_try_another_candidate(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = self._post_env(root, http_code="403") + textwrap.dedent(
                """
                export PHASE4_EDR_AUTHORIZATION=synthetic-token
                unset PHASE4_POST_AUTH_LABEL || true
                export PHASE4_POST_AUTH_LABEL=authkey_authcode
                _phase4_consume_data_with_auth_candidates
                """
            )
            result = _run_bash(script)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("No se prueba otro candidato", result.stderr)
            self.assertEqual((root / "post_count.txt").read_text(encoding="utf-8").count("\n"), 1)
            marker = json.loads((root / "phase4" / "post_attempt_consumed.json").read_text(encoding="utf-8"))
            self.assertEqual(marker["outcome"], "http_error")
            self.assertEqual(marker["http_status"], 403)
            self.assertEqual(marker["business_post_count"], 1)

    def test_timeout_does_not_resubmit(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = self._post_env(root, curl_exit="28") + "\n_phase4_consume_data_with_auth_candidates\n"
            result = _run_bash(script)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("timeout no demuestra", result.stderr)
            self.assertEqual((root / "post_count.txt").read_text(encoding="utf-8").count("\n"), 1)
            marker = json.loads((root / "phase4" / "post_attempt_consumed.json").read_text(encoding="utf-8"))
            self.assertEqual(marker["outcome"], "transport_or_ambiguous")

    def test_ambiguous_auth_sends_nothing(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            phase4 = root / "phase4"
            phase4.mkdir()
            body = root / "body.json"
            body.write_text('{"synthetic":true}', encoding="utf-8")
            count = root / "post_count.txt"
            count.write_text("", encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export PHASE4_DIR={json.dumps(str(phase4))}
                export SUFFIX=ambiguous
                export ASSET_ID=asset-post-safety
                export ASSET_HTTP_METHOD=POST
                export ASSET_CONTENT_KIND=json
                export ASSET_EXTENSION=json
                export ASSET_MEDIA_TYPE=application/json
                export INGESTA_API_REQUEST_BODY_FILE={json.dumps(str(body))}
                export EDR_URL=https://data-plane.invalid/dataplane
                export PHASE4_EDR_AUTHORIZATION=synthetic-token
                export PHASE4_EDR_AUTH_KEY=
                export PHASE4_EDR_AUTH_CODE=
                export PHASE4_EDR_AUTH_TYPE=
                export PHASE4_POST_AUTH_LABEL=
                export POST_COUNT={json.dumps(str(count))}
                curl() {{ printf 'x\\n' >> "${{POST_COUNT}}"; printf '200\\tapplication/json'; return 0; }}
                _phase4_consume_data_with_auth_candidates
                """
            )
            result = _run_bash(script)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("ambigua", result.stderr)
            self.assertEqual(count.read_text(encoding="utf-8"), "")
            self.assertFalse((phase4 / "post_attempt_consumed.json").exists())

    def test_get_still_tries_authentication_fallback(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            phase4 = root / "phase4"
            phase4.mkdir()
            count = root / "get_count.txt"
            count.write_text("", encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export PHASE4_DIR={json.dumps(str(phase4))}
                export SUFFIX=get-suffix
                export ASSET_ID=asset-get-safety
                unset ASSET_HTTP_METHOD INGESTA_API_REQUEST_BODY_FILE || true
                export ASSET_CONTENT_KIND=json
                export ASSET_EXTENSION=json
                export ASSET_MEDIA_TYPE=application/json
                export EDR_URL=https://data-plane.invalid/dataplane
                export PHASE4_EDR_AUTHORIZATION=synthetic-token
                export PHASE4_EDR_AUTH_KEY=
                export PHASE4_EDR_AUTH_CODE=
                export PHASE4_EDR_AUTH_TYPE=
                export GET_COUNT={json.dumps(str(count))}
                curl() {{
                  local out="" previous="" arg
                  for arg in "$@"; do
                    if [[ "${{previous}}" == "-o" ]]; then out="${{arg}}"; fi
                    previous="${{arg}}"
                  done
                  printf 'x\\n' >> "${{GET_COUNT}}"
                  local n
                  n="$(grep -c . "${{GET_COUNT}}")"
                  if [[ "${{n}}" == "1" ]]; then
                    printf '%s' '' > "${{out}}"
                    printf '401'
                    return 0
                  fi
                  printf '%s' '{{"ok":true}}' > "${{out}}"
                  printf '200'
                  return 0
                }}
                _phase4_consume_data_with_auth_candidates
                [[ "$(grep -c . "${{GET_COUNT}}")" == "2" ]]
                test -s {json.dumps(str(phase4 / "40_data_response.json"))}
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)


class PayloadValidationTests(unittest.TestCase):
    def _check(
        self,
        asset_id: str,
        document: str,
        *,
        expect_ok: bool,
        prelude: str = "",
    ) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "body.json"
            path.write_text(document, encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export ASSET_ID={json.dumps(asset_id)}
                {prelude}
                _phase4_validate_prod_company_payload {json.dumps(str(path))}
                """
            )
            result = _run_bash(script)
            if expect_ok:
                self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)
            else:
                self.assertNotEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def test_nested_company_payloads(self) -> None:
        self._check(EBRO_ASSET, EBRO_BODY, expect_ok=True)
        self._check(CIRCE_ASSET, CIRCE_BODY, expect_ok=True)
        self._check(EBRO_ASSET, CIRCE_BODY, expect_ok=False)
        self._check(CIRCE_ASSET, EBRO_BODY, expect_ok=False)
        both = '{"centers":[{"centerId":7,"districtCode":"D-TEST"}]}'
        self._check(EBRO_ASSET, both, expect_ok=False)
        self._check(CIRCE_ASSET, both, expect_ok=False)
        self._check(EBRO_ASSET, "{}", expect_ok=False)
        self._check(CIRCE_ASSET, '{"centers":[]}', expect_ok=False)
        self._check(EBRO_ASSET, '{"centers":[{"centerId":"7"}]}', expect_ok=False)
        self._check(CIRCE_ASSET, '{"centers":[{"districtCode":7}]}', expect_ok=False)
        self._check(CIRCE_ASSET, "{", expect_ok=False)

    def test_parallel_ebro_profile_and_rejections(self) -> None:
        self.assertTrue(EBRO_PARALLEL_CONFIG.is_file())
        context = _parallel_context()
        self._check("ignored-until-prelude", EBRO_BODY, expect_ok=True, prelude=context)
        self._check("ignored-until-prelude", CIRCE_BODY, expect_ok=False, prelude=context)
        self._check("asset-unrelated", CIRCE_BODY, expect_ok=True)
        self._check("workshop-ebro-demo", CIRCE_BODY, expect_ok=True)
        self._check(
            f"{EBRO_PARALLEL_SLUG}-{PARALLEL_SUFFIX}",
            EBRO_BODY,
            expect_ok=False,
            prelude=textwrap.dedent(
                f"""
                export SUFFIX={json.dumps(PARALLEL_SUFFIX)}
                unset ASSET_CONFIG || true
                """
            ),
        )
        for document in (
            "{}",
            '{"centers":[]}',
            '{"centers":[{"centerId":"7"}]}',
            '{"centers":[{"centerId":7.5}]}',
            '{"centers":[{"centerId":7,"districtCode":"D-TEST"}]}',
            '{"centers":[{"values":[]}]}',
        ):
            self._check("ignored-until-prelude", document, expect_ok=False, prelude=context)
        self._check(
            "ignored-until-prelude",
            EBRO_BODY,
            expect_ok=False,
            prelude=_parallel_context(provider="2"),
        )
        self._check(
            "ignored-until-prelude",
            EBRO_BODY,
            expect_ok=False,
            prelude=_parallel_context(method="GET"),
        )
        self._check(
            "ignored-until-prelude",
            EBRO_BODY,
            expect_ok=False,
            prelude=_parallel_context(proxy="0"),
        )

    def test_parallel_config_mutation_rejects_provider_method_and_proxy(self) -> None:
        import tempfile

        mutations = {
            '.provider_id = "2"': "provider id distinto de 1",
            '.http_method = "GET"': "method distinto de POST",
            '.proxy_body = false': "proxyBody no está activo",
        }
        for expression, message in mutations.items():
            with tempfile.TemporaryDirectory() as tmp:
                mutated = Path(tmp) / "config.json"
                body = Path(tmp) / "body.json"
                body.write_text(EBRO_BODY, encoding="utf-8")
                script = textwrap.dedent(
                    f"""
                    set -euo pipefail
                    source scripts/phase4_save_download.sh
                    mutated={json.dumps(str(mutated))}
                    jq {json.dumps(expression)} {json.dumps(str(EBRO_PARALLEL_CONFIG))} > "${{mutated}}"
                    chmod 600 "${{mutated}}"
                    {_parallel_context(config="${mutated}")}
                    _phase4_validate_prod_company_payload {json.dumps(str(body))}
                    """
                )
                result = _run_bash(script)
                self.assertNotEqual(result.returncode, 0, msg=result.stderr + result.stdout)
                self.assertIn(message, result.stderr)

    def test_get_request_does_not_require_company_payload(self) -> None:
        script = textwrap.dedent(
            """
            set -euo pipefail
            source scripts/phase4_save_download.sh
            export ASSET_ID=asset-getflow
            export ASSET_HTTP_METHOD=GET
            unset INGESTA_API_REQUEST_BODY_FILE || true
            _phase4_resolve_http_method
            _phase4_prepare_request_body
            [[ "${PHASE4_HTTP_METHOD}" == "GET" ]]
            [[ -z "${PHASE4_REQUEST_BODY_FILE}" ]]
            """
        )
        result = _run_bash(script)
        self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def test_config_identity_generation(self) -> None:
        self.assertTrue(EBRO_PARALLEL_CONFIG.is_file())
        self.assertTrue(EBRO_CANONICAL_CONFIG.is_file())
        script = textwrap.dedent(
            f"""
            set -euo pipefail
            unset IPPCP_PHASE1_REUSE_EXISTING || true
            source scripts/phase1_provider_publish.sh
            export SUFFIX={json.dumps(PARALLEL_SUFFIX)}
            export INGESTA_API_KEY=synthetic-offline-key
            export ASSET_CONFIG={json.dumps(str(EBRO_PARALLEL_CONFIG))}
            _phase1_load_asset_config
            [[ "${{ASSET_ID}}" == "{EBRO_PARALLEL_SLUG}-{PARALLEL_SUFFIX}" ]]
            [[ "${{ASSET_ID}}" != "{EBRO_ASSET}" ]]
            [[ "${{ASSET_ID}}" != "{CIRCE_ASSET}" ]]
            [[ "${{ASSET_SLUG}}" == "{EBRO_PARALLEL_SLUG}" ]]
            [[ "${{ASSET_HTTP_METHOD}}" == "POST" ]]
            [[ "${{ASSET_PROXY_BODY}}" == "1" ]]
            [[ "${{ASSET_PROVIDER_ID}}" == "1" ]]
            [[ "${{ASSET_ID_CUSTOM}}" == "1" ]]
            lib_derive_phase1_ids
            [[ "${{ASSET_ID}}" == "{EBRO_PARALLEL_SLUG}-{PARALLEL_SUFFIX}" ]]
            [[ "${{VOCAB_ID}}" == "vocab-{PARALLEL_SUFFIX}" ]]
            [[ "${{ACCESS_POLICY_ID}}" == "access-{PARALLEL_SUFFIX}" ]]
            [[ "${{CONTRACT_POLICY_ID}}" == "contract-{PARALLEL_SUFFIX}" ]]
            [[ "${{CD_ID}}" == "cd-{PARALLEL_SUFFIX}" ]]
            export ASSET_CONFIG={json.dumps(str(EBRO_CANONICAL_CONFIG))}
            _phase1_load_asset_config
            [[ "${{ASSET_ID}}" == "{EBRO_ASSET}" ]]
            [[ "${{ASSET_PROVIDER_ID}}" == "1" ]]
            [[ "${{ASSET_HTTP_METHOD}}" == "POST" ]]
            [[ "${{ASSET_PROXY_BODY}}" == "1" ]]
            jq -n --slurpfile canon {json.dumps(str(EBRO_CANONICAL_CONFIG))} --slurpfile local {json.dumps(str(EBRO_PARALLEL_CONFIG))} '
              def only_in(a; b): [a[] | select(. as $x | b | index($x) | not)];
              (only_in($canon[0] | keys; $local[0] | keys) == ["asset_id"])
              and (only_in($local[0] | keys; $canon[0] | keys) == [])
              and ([ $local[0] | keys[] as $k | select($local[0][$k] != $canon[0][$k]) ] | length == 0)
            ' >/dev/null
            """
        )
        result = _run_bash(script, env={"INGESTA_API_KEY": "synthetic-offline-key"})
        self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)


class MaintenanceCorrectionTests(unittest.TestCase):
    def test_jwt_prefix_is_not_logged_and_edr_endpoint_is_withheld(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            raw = Path(tmp) / "edr.json"
            redacted = Path(tmp) / "edr-redacted.json"
            env_file = Path(tmp) / "phase3_env.sh"
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/lib_common.sh
                source scripts/phase4_save_download.sh
                token="eyJabcdefghij"
                while (( ${{#token}} < 120 )); do token="${{token}}x"; done
                export CONSUMER_JWT="${{token}}"
                prefix="${{token:0:20}}"
                lib_jwt_check_console consumer >{json.dumps(str(Path(tmp) / "jwt.out"))} 2>{json.dumps(str(Path(tmp) / "jwt.err"))}
                ! grep -F "${{prefix}}" {json.dumps(str(Path(tmp) / "jwt.err"))}
                ! grep -F "eyJ" {json.dumps(str(Path(tmp) / "jwt.err"))}
                grep -F "JWT length:" {json.dumps(str(Path(tmp) / "jwt.err"))} >/dev/null
                export EDR_URL="https://edr-canary.invalid/dataplane"
                [[ "$(lib_diagnostic_edr_endpoint "${{EDR_URL}}")" == "<redacted-edr-endpoint>" ]]
                [[ "$(_phase4_safe_edr_url)" == "<redacted-edr-endpoint>" ]]
                [[ "$(lib_edr_endpoint_redacted_json "${{EDR_URL}}")" == "true" ]]
                printf '%s\\n' '{{"endpoint":"https://edr-canary.invalid/dataplane","authorization":"secret-token","endpointType":"DataAddress"}}' > {json.dumps(str(raw))}
                _phase4_redact_edr_file {json.dumps(str(raw))} {json.dumps(str(redacted))}
                ! grep -F "edr-canary" {json.dumps(str(redacted))}
                ! grep -F "secret-token" {json.dumps(str(redacted))}
                jq -e '.endpoint == "<redacted-edr-endpoint>" and .authorization == "***REDACTED***" and .endpointType == "DataAddress"' {json.dumps(str(redacted))} >/dev/null
                export SUFFIX=1000000001
                export ASSET_PROVIDER_ID=2
                mapfile -t names < <(_lib_phase_env_var_names 3)
                _lib_write_env_file {json.dumps(str(env_file))} "${{names[@]}}"
                grep -F 'export ASSET_PROVIDER_ID=2' {json.dumps(str(env_file))} >/dev/null
                grep -F 'https://edr-canary.invalid/dataplane' {json.dumps(str(env_file))} >/dev/null
                for phase in 1 2 3; do
                  _lib_phase_env_var_names "${{phase}}" | grep -qx ASSET_PROVIDER_ID
                done
                if _lib_phase_env_var_names 0 | grep -qx ASSET_PROVIDER_ID; then
                  exit 1
                fi
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def test_get_stops_after_valid_success_and_falls_back_on_invalid_content(self) -> None:
        import hashlib
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            phase4 = root / "phase4"
            phase4.mkdir()
            count = root / "get_count.txt"
            count.write_text("", encoding="utf-8")
            manifest = root / "manifest.json"
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export PHASE4_DIR={json.dumps(str(phase4))}
                export SUFFIX=get-stop
                export ASSET_ID=asset-get-stop
                export AGREEMENT_ID=00000000-0000-4000-8000-000000000010
                export TRANSFER_ID=00000000-0000-4000-8000-000000000011
                unset ASSET_HTTP_METHOD INGESTA_API_REQUEST_BODY_FILE || true
                export ASSET_CONTENT_KIND=json
                export ASSET_EXTENSION=json
                export ASSET_MEDIA_TYPE=application/json
                export EDR_URL=https://edr-canary.invalid/dataplane
                export PHASE4_EDR_AUTHORIZATION=synthetic-token
                export PHASE4_EDR_AUTH_KEY=
                export PHASE4_EDR_AUTH_CODE=
                export PHASE4_EDR_AUTH_TYPE=
                export GET_COUNT={json.dumps(str(count))}
                curl() {{
                  local out="" previous="" arg
                  for arg in "$@"; do
                    if [[ "${{previous}}" == "-o" ]]; then out="${{arg}}"; fi
                    previous="${{arg}}"
                  done
                  printf 'x\\n' >> "${{GET_COUNT}}"
                  printf '%s' '{{"ok":true}}' > "${{out}}"
                  printf '200'
                  return 0
                }}
                _phase4_consume_data_with_auth_candidates
                [[ "$(grep -c . "${{GET_COUNT}}")" == "1" ]]
                [[ ! -e {json.dumps(str(phase4 / "40_data_response_attempt_02.json"))} ]]
                test -s {json.dumps(str(phase4 / "40_data_response.json"))}
                export FILE_BYTES="$(_phase4_file_bytes {json.dumps(str(phase4 / "40_data_response.json"))})"
                export FILE_SHA256="$(_phase4_sha256_file {json.dumps(str(phase4 / "40_data_response.json"))})"
                export DATA_HTTP=200
                export COPY_ACTION=created
                export SAFE_ASSET_ID=asset-get-stop
                export PHASE4_HTTP_METHOD=GET
                _phase4_write_manifest {json.dumps(str(manifest))}
                jq -e --arg sha "${{FILE_SHA256}}" --argjson bytes "${{FILE_BYTES}}" '
                  .bytes == $bytes and .sha256 == $sha and .data_http == 200
                  and .edr_url == "<redacted-edr-endpoint>" and .edr_url_redacted == true
                ' {json.dumps(str(manifest))} >/dev/null
                ! grep -F "edr-canary" {json.dumps(str(manifest))}
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)
            body = (phase4 / "40_data_response.json").read_bytes()
            self.assertEqual(len(body), 11)
            self.assertEqual(hashlib.sha256(body).hexdigest(), json.loads(manifest.read_text())["sha256"])

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            phase4 = root / "phase4"
            phase4.mkdir()
            count = root / "get_count.txt"
            count.write_text("", encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export PHASE4_DIR={json.dumps(str(phase4))}
                export SUFFIX=get-invalid
                export ASSET_ID=asset-get-invalid
                unset ASSET_HTTP_METHOD INGESTA_API_REQUEST_BODY_FILE || true
                export ASSET_CONTENT_KIND=json
                export ASSET_EXTENSION=json
                export ASSET_MEDIA_TYPE=application/json
                export EDR_URL=https://edr-canary.invalid/dataplane
                export PHASE4_EDR_AUTHORIZATION=synthetic-token
                export PHASE4_EDR_AUTH_KEY=
                export PHASE4_EDR_AUTH_CODE=
                export PHASE4_EDR_AUTH_TYPE=
                export GET_COUNT={json.dumps(str(count))}
                curl() {{
                  local out="" previous="" arg
                  for arg in "$@"; do
                    if [[ "${{previous}}" == "-o" ]]; then out="${{arg}}"; fi
                    previous="${{arg}}"
                  done
                  printf 'x\\n' >> "${{GET_COUNT}}"
                  local n
                  n="$(grep -c . "${{GET_COUNT}}")"
                  if [[ "${{n}}" == "1" ]]; then
                    : > "${{out}}"
                    printf '200'
                    return 0
                  fi
                  printf '%s' '{{"ok":true}}' > "${{out}}"
                  printf '200'
                  return 0
                }}
                _phase4_consume_data_with_auth_candidates
                [[ "$(grep -c . "${{GET_COUNT}}")" == "2" ]]
                jq -e '.ok == true' {json.dumps(str(phase4 / "40_data_response.json"))} >/dev/null
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def test_provider_id_propagation_does_not_default_and_rejects_conflicts(self) -> None:
        circe = REPO_ROOT / "asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json"
        wfs = REPO_ROOT / "asset_configs/real/consumo/wfs/emisiones_wfs_ciudad_geojson.json"
        script = textwrap.dedent(
            f"""
            set -euo pipefail
            source scripts/phase1_provider_publish.sh
            export SUFFIX={json.dumps(PARALLEL_SUFFIX)}
            export INGESTA_API_KEY=synthetic-offline-key
            unset ASSET_PROVIDER_ID INGESTA_API_PROVIDER_ID || true
            export ASSET_CONFIG={json.dumps(str(EBRO_CANONICAL_CONFIG))}
            _phase1_load_asset_config
            [[ "${{ASSET_PROVIDER_ID}}" == "1" ]]
            unset ASSET_PROVIDER_ID INGESTA_API_PROVIDER_ID || true
            export ASSET_CONFIG={json.dumps(str(EBRO_PARALLEL_CONFIG))}
            _phase1_load_asset_config
            [[ "${{ASSET_PROVIDER_ID}}" == "1" ]]
            unset ASSET_PROVIDER_ID INGESTA_API_PROVIDER_ID || true
            export ASSET_CONFIG={json.dumps(str(circe))}
            _phase1_load_asset_config
            [[ "${{ASSET_PROVIDER_ID}}" == "2" ]]
            export ASSET_PROVIDER_ID=2
            export ASSET_CONFIG={json.dumps(str(EBRO_CANONICAL_CONFIG))}
            if ( _phase1_load_asset_config ); then
              echo "conflict was accepted" >&2
              exit 1
            fi
            unset ASSET_PROVIDER_ID || true
            export INGESTA_API_PROVIDER_ID=2
            export ASSET_CONFIG={json.dumps(str(EBRO_CANONICAL_CONFIG))}
            if ( _phase1_load_asset_config ); then
              echo "ingesta conflict was accepted" >&2
              exit 1
            fi
            unset INGESTA_API_PROVIDER_ID ASSET_PROVIDER_ID || true
            export ASSET_CONFIG={json.dumps(str(REPO_ROOT / "asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json"))}
            if ( _phase1_load_asset_config ); then
              echo "missing provider defaulted" >&2
              exit 1
            fi
            export ASSET_PROVIDER_ID=9
            unset INGESTA_API_PROVIDER_ID || true
            export ASSET_CONFIG={json.dumps(str(wfs))}
            _phase1_load_asset_config
            [[ -z "${{ASSET_PROVIDER_ID:-}}" ]]
            [[ "${{ASSET_HTTP_METHOD}}" != "POST" || -z "${{ASSET_HTTP_METHOD:-}}" ]]
            """
        )
        result = _run_bash(script, env={"INGESTA_API_KEY": "synthetic-offline-key"})
        self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)


if __name__ == "__main__":
    unittest.main()
