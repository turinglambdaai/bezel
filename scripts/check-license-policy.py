#!/usr/bin/env python3
"""Fail closed when public release policy drifts from auditable LGPL packaging."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import sys
import urllib.request

REQUIRED_QT_VERSION = "6.8.4"
REQUIRED_QTBASE_SHA256 = "532dfbf3fa3cbc68fa37441ea9e81c5009da044eaecda78ffaeafd8bd125532f"
REQUIRED_BUILD_PROFILE = "source-shared-no-icu-official-security-patches"
REQUIRED_LINUX_PROFILE = (
    "source-shared-no-icu-host-deps-external-official-security-patches"
)
REQUIRED_APPLIED_PATCHES = {
    "CVE-2026-19248-qtbase-6.8.diff": "86c063884e0a274075f29d1aa452001cef7d7dfcee21b21eb9a7165679b4052a",
    "CVE-2026-76151-qtbase-6.8.diff": "19683125f596b5278ff38461951ab778b1cc24a59065cc0721ff1a52e625f0c8",
    "CVE-2026-78253-qtbase-6.8.diff": "8a4f44fa40d4b46d0d2582652d84598f2ac55fcd4a53ecebc23ae5e381a3252a",
}


def fail(message: str) -> None:
    print(f"license-policy: ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    repo = Path(__file__).resolve().parent.parent
    policy_path = repo / "release" / "qt-runtime-policy.json"
    policy = json.loads(policy_path.read_text(encoding="utf-8"))

    if policy.get("schema_version") != 3:
        fail("unexpected redistribution policy schema version")
    if policy.get("qt_version") != REQUIRED_QT_VERSION:
        fail(f"Qt version must be pinned to {REQUIRED_QT_VERSION}")
    if policy.get("source_sha256", "").lower() != REQUIRED_QTBASE_SHA256:
        fail("QtBase source SHA-256 does not match the reviewed release source")
    expected_archive = (
        f"qtbase-everywhere-opensource-src-{REQUIRED_QT_VERSION}.tar.xz"
    )
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
    if policy.get("public_qt_build_profile") != REQUIRED_BUILD_PROFILE:
        fail(f"all public runtimes must use build profile {REQUIRED_BUILD_PROFILE}")
    if policy.get("linux_qt_build_profile") != REQUIRED_LINUX_PROFILE:
        fail(f"Linux Qt build profile must remain {REQUIRED_LINUX_PROFILE}")
    if policy.get("linux_qt_icu_enabled") is not False:
        fail("public Linux Qt build must keep ICU disabled")
    if policy.get("linux_non_qt_shared_libraries_are_host_prerequisites") is not True:
        fail("Linux non-Qt shared libraries must remain external host prerequisites")
    if policy.get("bundle_linux_system_libraries") is not False:
        fail("public Linux package may not recursively redistribute host system libraries")
    if policy.get("bundle_windows_msvc_runtime") is not False:
        fail("public Windows package may not redistribute the MSVC runtime")

    inventory = policy.get("security_patch_inventory")
    if not isinstance(inventory, list) or not inventory:
        fail("Qt security patch inventory is missing")
    inventory_by_file = {entry.get("file"): entry for entry in inventory}
    if len(inventory_by_file) != len(inventory):
        fail("Qt security patch inventory contains duplicate or missing filenames")
    applied = {
        name: str(entry.get("sha256", "")).lower()
        for name, entry in inventory_by_file.items()
        if entry.get("status") == "applied"
    }
    if applied != REQUIRED_APPLIED_PATCHES:
        fail("applied Qt security patch set/hash does not match the reviewed baseline")
    for name, entry in inventory_by_file.items():
        if entry.get("status") not in {"included-in-6.8.4", "applied"}:
            fail(f"unreviewed Qt security patch status for {name}")
        if entry.get("status") == "applied":
            expected_url = f"https://download.qt.io/official_releases/qt/6.8/{name}"
            if entry.get("url") != expected_url:
                fail(f"Qt security patch must use its exact official URL: {name}")

    index_url = policy.get("security_patch_index_url")
    if index_url != "https://download.qt.io/official_releases/qt/6.8/":
        fail("unexpected Qt 6.8 security patch index URL")
    request = urllib.request.Request(
        index_url, headers={"User-Agent": "Bezel-license-policy/1"}
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            official_index = response.read().decode("utf-8", errors="replace")
    except Exception as exc:
        fail(f"could not audit the official Qt 6.8 security patch index: {exc}")
    official_qtbase_patches = set(
        re.findall(r"CVE-[0-9-]+-qtbase-6\.8\.(?:diff|patch)", official_index)
    )
    recorded_qtbase_patches = set(inventory_by_file)
    if official_qtbase_patches != recorded_qtbase_patches:
        missing = sorted(official_qtbase_patches - recorded_qtbase_patches)
        stale = sorted(recorded_qtbase_patches - official_qtbase_patches)
        fail(
            "Qt 6.8 security patch inventory drift; "
            f"unreviewed={missing}, no-longer-listed={stale}"
        )

    for workflow_name in ("ci.yml", "release.yml"):
        workflow = (repo / ".github" / "workflows" / workflow_name).read_text(
            encoding="utf-8"
        )
        if f"BEZEL_QT_VERSION: '{REQUIRED_QT_VERSION}'" not in workflow:
            fail(f"{workflow_name} does not pin BEZEL_QT_VERSION to {REQUIRED_QT_VERSION}")
        if re.search(r"version:\s*['\"]?6\.[0-9]+\.\*", workflow):
            fail(f"{workflow_name} contains a wildcard Qt version")
        if "build-pinned-qt-windows.ps1" not in workflow:
            fail(f"{workflow_name} does not source-build the Windows Qt runtime")
        if "build-pinned-qt-macos.sh" not in workflow:
            fail(f"{workflow_name} does not source-build the macOS Qt runtime")

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
    for token in ("-shared", "-no-icu"):
        if token not in linux_builder:
            fail(f"Linux Qt builder is missing required configure option: {token}")
    if "-force-bundled-libs" in linux_builder:
        fail("Linux Qt builder contains unsupported -force-bundled-libs option")

    linux_packager = (repo / "scripts" / "package-native-linux.sh").read_text(
        encoding="utf-8"
    )
    for token in ("SYSTEM-DEPENDENCIES.txt", "unexpected non-Qt shared library"):
        if token not in linux_packager:
            fail(f"Linux packager is missing host-dependency boundary control: {token}")

    for required_path in (
        repo / "docs" / "LGPL_RELINKING.md",
        repo / "scripts" / "prepare-qt-compliance.py",
        repo / "scripts" / "build-pinned-qt-linux.sh",
        repo / "scripts" / "build-pinned-qt-windows.ps1",
        repo / "scripts" / "build-pinned-qt-macos.sh",
        repo / "scripts" / "prepare-pinned-qt-source.py",
    ):
        if not required_path.is_file():
            fail(f"required compliance file is missing: {required_path.relative_to(repo)}")

    # Print a stable policy fingerprint for release logs/audits.
    canonical = json.dumps(policy, sort_keys=True, separators=(",", ":")).encode()
    print(f"license-policy: OK; policy-sha256={hashlib.sha256(canonical).hexdigest()}")


if __name__ == "__main__":
    main()
