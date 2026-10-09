#!/usr/bin/env python3
"""Local tests for Ingesta API GET/POST asset support (no infrastructure calls)."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GET_CONFIG = REPO_ROOT / "asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json"
POST_EBRO = REPO_ROOT / "asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json"
POST_CIRCE = REPO_ROOT / "asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json"
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


def _run_bash(script: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
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


class IngestaAssetConfigTests(unittest.TestCase):
    def test_get_config_has_no_post_fields(self) -> None:
        cfg = json.loads(GET_CONFIG.read_text(encoding="utf-8"))
        self.assertNotIn("http_method", cfg)
        self.assertNotIn("proxy_body", cfg)
        self.assertNotIn("asset_id", cfg)
        self.assertTrue(cfg["requires_api_key_header"])
        self.assertTrue(cfg["requires_provider_id_header"])

    def test_post_configs_declare_stable_ids_and_post_fields(self) -> None:
        for path, asset_id, provider_id in (
            (POST_EBRO, "ippcp-ingesta-pull-industrias-ebro-prod", "1"),
            (POST_CIRCE, "ippcp-ingesta-pull-circe-prod", "2"),
        ):
            with self.subTest(path=str(path)):
                cfg = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(cfg["asset_id"], asset_id)
                self.assertEqual(cfg["http_method"], "POST")
                self.assertIs(cfg["proxy_body"], True)
                self.assertEqual(str(cfg["provider_id"]), provider_id)
                self.assertEqual(cfg["type"], "HttpData")
                self.assertTrue(cfg["requires_api_key_header"])
                self.assertTrue(cfg["requires_provider_id_header"])
                forbidden_keys = {"api_key", "x-api-key", "header:x-api-key", "password", "jwt", "token"}
                lowered_keys = {str(key).lower() for key in cfg.keys()}
                self.assertTrue(forbidden_keys.isdisjoint(lowered_keys))


class Phase1DataAddressTests(unittest.TestCase):
    def _build_request(self, config_rel: str, *, api_key: str, provider_id: str | None) -> dict:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "asset_request.json"
            redacted = Path(tmp) / "asset_request_redacted.json"
            env_exports = f'export INGESTA_API_KEY={json.dumps(api_key)}\n'
            if provider_id is not None:
                env_exports += f'export INGESTA_API_PROVIDER_ID={json.dumps(provider_id)}\n'
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                export SUFFIX=testsuffix
                export ASSET_CONFIG={json.dumps(config_rel)}
                {env_exports}
                source scripts/phase1_provider_publish.sh
                api_find_root
                _phase1_load_asset_config
                _phase1_write_asset_request {json.dumps(str(out))}
                _phase1_redact_json_file {json.dumps(str(out))} {json.dumps(str(redacted))}
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)
            raw = json.loads(out.read_text(encoding="utf-8"))
            sanitized = json.loads(redacted.read_text(encoding="utf-8"))
            return {"raw": raw, "redacted": sanitized}

    def test_get_config_keeps_httpdata_without_method_or_proxy(self) -> None:
        built = self._build_request(
            "asset_configs/real/ingesta/ingesta_api_pull_pre_api_key.json",
            api_key="CANARY-API-KEY-GET-TEST",
            provider_id="9",
        )
        data_address = built["raw"]["dataAddress"]
        self.assertEqual(data_address["type"], "HttpData")
        self.assertNotIn("method", data_address)
        self.assertNotIn("proxyBody", data_address)
        self.assertEqual(data_address["header:X-Api-Key"], "CANARY-API-KEY-GET-TEST")
        self.assertEqual(data_address["header:X-Provider-Id"], "9")
        self.assertTrue(built["raw"]["@id"].endswith("-testsuffix"))
        self.assertEqual(
            built["redacted"]["dataAddress"]["header:X-Api-Key"],
            "<redacted>",
        )
        self.assertNotIn("CANARY-API-KEY-GET-TEST", json.dumps(built["redacted"]))

    def test_post_ebro_emits_method_proxy_stable_id_and_redacts_key(self) -> None:
        built = self._build_request(
            "asset_configs/real/ingesta/ingesta_api_pull_industrias_ebro_prod.json",
            api_key="CANARY-API-KEY-POST-EBRO",
            provider_id=None,
        )
        data_address = built["raw"]["dataAddress"]
        self.assertEqual(built["raw"]["@id"], "ippcp-ingesta-pull-industrias-ebro-prod")
        self.assertEqual(data_address["type"], "HttpData")
        self.assertEqual(data_address["method"], "POST")
        self.assertEqual(data_address["proxyBody"], "true")
        self.assertEqual(data_address["header:X-Provider-Id"], "1")
        self.assertEqual(data_address["header:X-Api-Key"], "CANARY-API-KEY-POST-EBRO")
        self.assertEqual(
            built["redacted"]["dataAddress"]["header:X-Api-Key"],
            "<redacted>",
        )
        self.assertNotIn("CANARY-API-KEY-POST-EBRO", json.dumps(built["redacted"]))

    def test_post_circe_uses_provider_id_from_config(self) -> None:
        built = self._build_request(
            "asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json",
            api_key="CANARY-API-KEY-POST-CIRCE",
            provider_id=None,
        )
        self.assertEqual(built["raw"]["@id"], "ippcp-ingesta-pull-circe-prod")
        self.assertEqual(built["raw"]["dataAddress"]["header:X-Provider-Id"], "2")
        self.assertEqual(built["raw"]["dataAddress"]["method"], "POST")
        self.assertEqual(built["raw"]["dataAddress"]["proxyBody"], "true")

    def test_post_config_provider_id_rejects_conflicting_env(self) -> None:
        """A stale INGESTA_API_PROVIDER_ID must not override or be ignored for CIRCE."""
        script = textwrap.dedent(
            """
            set -euo pipefail
            export SUFFIX=testsuffix
            export INGESTA_API_KEY=CANARY-API-KEY-POST-CIRCE-STALE-ENV
            export INGESTA_API_PROVIDER_ID=1
            export ASSET_CONFIG=asset_configs/real/ingesta/ingesta_api_pull_circe_prod.json
            source scripts/phase1_provider_publish.sh
            api_find_root
            _phase1_load_asset_config
            """
        )
        result = _run_bash(script)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no coincide con provider_id", result.stderr)


class Phase4PostSupportTests(unittest.TestCase):
    def test_get_path_defaults_without_body_file(self) -> None:
        script = textwrap.dedent(
            """
            set -euo pipefail
            source scripts/phase4_save_download.sh
            unset ASSET_HTTP_METHOD INGESTA_API_REQUEST_BODY_FILE || true
            _phase4_resolve_http_method
            _phase4_prepare_request_body
            [[ "${PHASE4_HTTP_METHOD}" == "GET" ]]
            [[ -z "${PHASE4_REQUEST_BODY_FILE}" ]]
            """
        )
        result = _run_bash(script)
        self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def test_post_requires_body_file(self) -> None:
        script = textwrap.dedent(
            """
            set -euo pipefail
            source scripts/phase4_save_download.sh
            export ASSET_HTTP_METHOD=POST
            unset INGESTA_API_REQUEST_BODY_FILE || true
            _phase4_resolve_http_method
            if _phase4_prepare_request_body; then
              exit 10
            fi
            """
        )
        result = _run_bash(script)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual(result.returncode, 10)
        self.assertIn("INGESTA_API_REQUEST_BODY_FILE", result.stderr)

    def test_post_builds_method_content_type_and_omits_body_from_summary(self) -> None:
        canary = '{"canary_post_body_marker":"DO-NOT-PERSIST-9f3a","value":42}'
        with tempfile.TemporaryDirectory() as tmp:
            body_path = Path(tmp) / "body.json"
            evidence = Path(tmp) / "42_data_attempts_summary.json"
            body_path.write_text(canary, encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export ASSET_HTTP_METHOD=POST
                export ASSET_CONTENT_KIND=json
                export ASSET_MEDIA_TYPE=application/json
                export INGESTA_API_REQUEST_BODY_FILE={json.dumps(str(body_path))}
                api_find_root
                _phase4_resolve_http_method
                _phase4_prepare_request_body
                [[ "${{PHASE4_HTTP_METHOD}}" == "POST" ]]
                [[ -n "${{PHASE4_REQUEST_BODY_FILE}}" ]]
                bytes="$(_phase4_file_bytes "${{PHASE4_REQUEST_BODY_FILE}}")"
                jq -nc \\
                  --arg http_method "${{PHASE4_HTTP_METHOD}}" \\
                  --arg media_type "${{ASSET_MEDIA_TYPE}}" \\
                  --argjson request_body_bytes "${{bytes}}" \\
                  '{{http_method:$http_method, media_type:$media_type, request_body_bytes:$request_body_bytes}}' \\
                  > {json.dumps(str(evidence))}
                _phase4_assert_no_sensitive_control_artifact {json.dumps(str(evidence))}
                if grep -Fq 'DO-NOT-PERSIST-9f3a' {json.dumps(str(evidence))}; then
                  echo "body leaked into evidence" >&2
                  exit 11
                fi
                # Contract for curl construction (no network): method + content-type + body file.
                [[ "${{PHASE4_HTTP_METHOD}}" == "POST" ]]
                [[ "${{ASSET_MEDIA_TYPE}}" == "application/json" ]]
                [[ -f "${{PHASE4_REQUEST_BODY_FILE}}" ]]
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)
            summary = json.loads(evidence.read_text(encoding="utf-8"))
            self.assertEqual(summary["http_method"], "POST")
            self.assertEqual(summary["media_type"], "application/json")
            self.assertGreater(summary["request_body_bytes"], 0)
            self.assertNotIn("canary_post_body_marker", json.dumps(summary))

    def test_post_success_accepts_2xx_without_json_or_body(self) -> None:
        """POST must not inherit GET emptiness/JSON success rules."""
        cases = (
            ("200", '{"ok":true}', True),
            ("201", '{"created":true}', True),
            ("201", "", True),
            ("202", '{"accepted":true}', True),
            ("204", "", True),
            ("400", "", False),
            ("500", '{"error":true}', False),
        )
        for http_code, body, expect_ok in cases:
            with self.subTest(http_code=http_code, body=body, expect_ok=expect_ok):
                with tempfile.TemporaryDirectory() as tmp:
                    attempt = Path(tmp) / "attempt.json"
                    attempt.write_text(body, encoding="utf-8")
                    script = textwrap.dedent(
                        f"""
                        set -euo pipefail
                        source scripts/phase4_save_download.sh
                        export PHASE4_HTTP_METHOD=POST
                        export ASSET_CONTENT_KIND=json
                        if _phase4_attempt_is_successful {json.dumps(str(attempt))} {http_code} 0; then
                          exit 0
                        fi
                        exit 2
                        """
                    )
                    result = _run_bash(script)
                    if expect_ok:
                        self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)
                    else:
                        self.assertEqual(result.returncode, 2, msg=result.stderr + result.stdout)

    def test_post_finalize_does_not_persist_request_or_response_bodies(self) -> None:
        """POST metadata-only path: no response/request body in artifacts or downloads."""
        cases = (
            ("200", '{"response_canary":"RESP-BODY-AAA","n":1}'),
            ("201", '{"response_canary":"RESP-BODY-BBB","n":2}'),
            ("201", ""),
            ("204", ""),
        )
        for http_code, response_body in cases:
            with self.subTest(http_code=http_code, empty=response_body == ""):
                with tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    phase4_dir = root / "phase4"
                    downloads = root / "downloads"
                    phase4_dir.mkdir()
                    downloads.mkdir()
                    req = root / "request.json"
                    req.write_text(
                        '{"request_canary":"REQ-BODY-ZZZ","payload":true}',
                        encoding="utf-8",
                    )
                    # Leftover body that finalize must scrub if present.
                    leftover = phase4_dir / "40_data_response.json"
                    if response_body:
                        leftover.write_text(response_body, encoding="utf-8")
                    (phase4_dir / "40_data_response.http").write_text(
                        f"{http_code}\n", encoding="utf-8"
                    )
                    (phase4_dir / "42_data_attempts_summary.json").write_text(
                        json.dumps(
                            {
                                "http_method": "POST",
                                "response_body_persisted": False,
                                "attempts": [],
                            }
                        ),
                        encoding="utf-8",
                    )
                    script = textwrap.dedent(
                        f"""
                        set -euo pipefail
                        source scripts/phase4_save_download.sh
                        export PHASE4_DIR={json.dumps(str(phase4_dir))}
                        export DOWNLOADS_DIR={json.dumps(str(downloads))}
                        export SUFFIX=testsuffix
                        export ASSET_ID=ippcp-ingesta-pull-circe-prod
                        export AGREEMENT_ID=agr-test
                        export TRANSFER_ID=xfer-test
                        export EDR_URL=https://example.invalid/edr
                        export PHASE4_HTTP_METHOD=POST
                        export PHASE4_AUTH_CANDIDATE_LABEL=authorization_raw
                        export DATA_HTTP={http_code}
                        export PHASE4_POST_RESPONSE_BYTES={len(response_body.encode())}
                        export PHASE4_POST_RESPONSE_MEDIA_TYPE=application/json
                        export PHASE4_POST_REQUEST_BODY_BYTES=$(_phase4_file_bytes {json.dumps(str(req))})
                        export PHASE4_REQUEST_BODY_FILE={json.dumps(str(req))}
                        export ASSET_CONTENT_KIND=json
                        export ASSET_EXTENSION=json
                        export ASSET_MEDIA_TYPE=application/json
                        _phase4_finalize_post_metadata_only
                        test ! -f {json.dumps(str(leftover))}
                        test ! -f {json.dumps(str(phase4_dir / "41_data_preview.json"))}
                        test -f {json.dumps(str(phase4_dir / "post_result.json"))}
                        test -f {json.dumps(str(phase4_dir / "post_manifest.json"))}
                        # No downloads materialized for POST.
                        test -z "$(find {json.dumps(str(downloads))} -type f 2>/dev/null | head -n 1)"
                        if grep -R -F 'REQ-BODY-ZZZ' {json.dumps(str(phase4_dir))} {json.dumps(str(downloads))} 2>/dev/null; then
                          echo "request body leaked" >&2
                          exit 11
                        fi
                        if grep -R -F 'RESP-BODY-' {json.dumps(str(phase4_dir))} {json.dumps(str(downloads))} 2>/dev/null; then
                          echo "response body leaked" >&2
                          exit 12
                        fi
                        """
                    )
                    result = _run_bash(script)
                    self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)
                    result_doc = json.loads(
                        (phase4_dir / "post_result.json").read_text(encoding="utf-8")
                    )
                    manifest = json.loads(
                        (phase4_dir / "post_manifest.json").read_text(encoding="utf-8")
                    )
                    self.assertEqual(result_doc["http_method"], "POST")
                    self.assertEqual(result_doc["http_status"], int(http_code))
                    self.assertIs(result_doc["response_body_persisted"], False)
                    self.assertIs(result_doc["request_body_persisted"], False)
                    self.assertIs(result_doc["download_persisted"], False)
                    self.assertNotIn("sha256", result_doc)
                    self.assertIs(manifest["response_body_persisted"], False)
                    self.assertEqual(manifest["manifest_kind"], "post_metadata_only")
                    self.assertNotIn("sha256", manifest)
                    self.assertFalse(leftover.exists())

    def test_get_success_still_requires_non_empty_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp) / "empty.json"
            empty.write_text("", encoding="utf-8")
            bad = Path(tmp) / "bad.json"
            bad.write_text("not-json", encoding="utf-8")
            good = Path(tmp) / "good.json"
            good.write_text('{"ok":true}', encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export PHASE4_HTTP_METHOD=GET
                export ASSET_CONTENT_KIND=json
                unset ALLOW_EMPTY_DOWNLOAD || true
                _phase4_attempt_is_successful {json.dumps(str(empty))} 200 0 && exit 10
                _phase4_attempt_is_successful {json.dumps(str(bad))} 200 0 && exit 11
                _phase4_attempt_is_successful {json.dumps(str(good))} 200 0 || exit 12
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)

    def test_get_still_writes_preview_from_response_body(self) -> None:
        """GET historical preview behavior remains body-aware."""
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp) / "data.json"
            preview = Path(tmp) / "preview.json"
            data.write_text('{"get_canary":"KEEP-FOR-GET","n":1}', encoding="utf-8")
            script = textwrap.dedent(
                f"""
                set -euo pipefail
                source scripts/phase4_save_download.sh
                export PHASE4_HTTP_METHOD=GET
                export ASSET_CONTENT_KIND=json
                export ASSET_EXTENSION=json
                export ASSET_MEDIA_TYPE=application/json
                _phase4_write_data_preview {json.dumps(str(data))} {json.dumps(str(preview))}
                grep -Fq 'KEEP-FOR-GET' {json.dumps(str(preview))}
                """
            )
            result = _run_bash(script)
            self.assertEqual(result.returncode, 0, msg=result.stderr + result.stdout)


if __name__ == "__main__":
    unittest.main()
