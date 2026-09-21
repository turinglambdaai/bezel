#!/usr/bin/env python3
"""Fail closed when public release policy drifts from auditable LGPL packaging."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import sys

REQUIRED_QT_VERSION = "6.8.3"
REQUIRED_QTBASE_SHA256 = "56001b905601bb9023d399f3ba780d7fa940f3e4861e496a7c490331f49e0b80"
REQUIRED_LINUX_PROFILE = "source-shared-no-icu-force-bundled-libs"


def fail(message: str) -> None:
    print(f"license-policy: ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    repo = Path(__file__).resolve().parent.parent
    policy_path = repo / "release" / "qt-runtime-policy.json"
    policy = json.loads(policy_path.read_text(encoding="utf-8"))

    if policy.get("schema_version") != 2:
        fail("unexpected redistribution policy schema version")
    if policy.get("qt_version") != REQUIRED_QT_VERSION:
        fail(f"Qt version must be pinned to {REQUIRED_QT_VERSION}")
    if policy.get("source_sha256", "").lower() != REQUIRED_QTBASE_SHA256:
        fail("QtBase source SHA-256 does not match the reviewed release source")
    expected_archive = f"qtbase-everywhere-src-{REQUIRED_QT_VERSION}.tar.xz"
    if policy.get("source_archive") != expected_archive:
        fail(f"unexpected QtBase source archive: {policy.get('source_archive')!r}")
    source_url = str(policy.get("source_url", ""))
    if not source_url.startswith("https://download.qt.io/") or not source_url.endswith(
        "/" + expected_archive
    ):
        fail("QtBase source must come from download.qt.io and match the pinned archive")
    if policy.get("public_release_license_mode") != "lgpl":
        fail("public binary release mode must be LGPL")
    if policy.get("public_release_linkage") != "dynamic":
        fail("public Qt release must remain dynamically linked")
    if policy.get("public_workflow_may_publish_commercial_qt") is not False:
        fail("public workflow may not claim commercial Qt redistribution rights")
    if policy.get("linux_qt_build_profile") != REQUIRED_LINUX_PROFILE:
        fail(f"Linux Qt build profile must remain {REQUIRED_LINUX_PROFILE}")
    if policy.get("linux_qt_icu_enabled") is not False:
        fail("public Linux Qt build must keep ICU disabled")
    if policy.get("linux_qt_bundled_third_party") is not True:
        fail("public Linux Qt build must use reviewed QtBase bundled third-party copies")
    if policy.get("bundle_linux_system_libraries") is not False:
        fail("public Linux package may not recursively redistribute host system libraries")
    if policy.get("bundle_windows_msvc_runtime") is not False:
        fail("public Windows package may not redistribute the MSVC runtime")

    for workflow_name in ("ci.yml", "release.yml"):
        workflow = (repo / ".github" / "workflows" / workflow_name).read_text(
            encoding="utf-8"
        )
        if f"BEZEL_QT_VERSION: '{REQUIRED_QT_VERSION}'" not in workflow:
            fail(f"{workflow_name} does not pin BEZEL_QT_VERSION to {REQUIRED_QT_VERSION}")
        if re.search(r"version:\s*['\"]?6\.[0-9]+\.\*", workflow):
            fail(f"{workflow_name} contains a wildcard Qt version")

    release = (repo / ".github" / "workflows" / "release.yml").read_text(
        encoding="utf-8"
    )
    forbidden_release_tokens = (
        "BEZEL_QT_SOURCE_OFFER_URL",
        "LICENSE_MODE=commercial",
        "Qt redistribution mode: commercial",
    )
    for token in forbidden_release_tokens:
        if token in release:
            fail(f"public release workflow contains forbidden commercial/legacy token: {token}")

    linux_builder = (repo / "scripts" / "build-pinned-qt-linux.sh").read_text(
        encoding="utf-8"
    )
    for token in ("-shared", "-no-icu", "-force-bundled-libs"):
        if token not in linux_builder:
            fail(f"Linux Qt builder is missing required configure option: {token}")

    for required_path in (
        repo / "docs" / "LGPL_RELINKING.md",
        repo / "scripts" / "prepare-qt-compliance.py",
        repo / "scripts" / "build-pinned-qt-linux.sh",
    ):
        if not required_path.is_file():
            fail(f"required compliance file is missing: {required_path.relative_to(repo)}")

    # Print a stable policy fingerprint for release logs/audits.
    canonical = json.dumps(policy, sort_keys=True, separators=(",", ":")).encode()
    print(f"license-policy: OK; policy-sha256={hashlib.sha256(canonical).hexdigest()}")


if __name__ == "__main__":
    main()
