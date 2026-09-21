#!/usr/bin/env python3
"""Prepare license/source material shipped with Bezel native runtimes.

The generator starts from the exact QtBase source archive recorded in
release/qt-runtime-policy.json and verifies its SHA-256 before extracting any
license or attribution material. It also downloads and verifies every official
Qt 6.8 security patch applied by the public build. Tagged releases publish the
base archive plus the patch bundle beside the binaries so corresponding source
is controlled by the distributor rather than represented only by upstream links.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(
        url, headers={"User-Agent": "Bezel-release-compliance/1"}
    )
    with urllib.request.urlopen(request, timeout=120) as response, destination.open(
        "wb"
    ) as out:
        shutil.copyfileobj(response, out)


def safe_extract(archive: Path, destination: Path) -> None:
    destination_real = destination.resolve()
    with tarfile.open(archive, "r:xz") as tf:
        for member in tf.getmembers():
            target = (destination / member.name).resolve()
            if target != destination_real and destination_real not in target.parents:
                raise RuntimeError(f"unsafe path in Qt source archive: {member.name}")
        tf.extractall(destination)


def copy_if_file(source: Path, destination: Path) -> None:
    if source.is_file():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def normalize_entries(value: object, source_file: Path) -> list[dict]:
    if isinstance(value, dict):
        return [value]
    if isinstance(value, list) and all(isinstance(item, dict) for item in value):
        return value
    raise RuntimeError(f"unexpected qt_attribution.json shape: {source_file}")


def render_value(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return ", ".join(str(item) for item in value)
    return str(value)


def generate_attributions(source_root: Path, qt_root: Path) -> tuple[int, int]:
    attribution_root = qt_root / "attributions"
    license_file_root = qt_root / "third-party-license-files"
    attribution_root.mkdir(parents=True, exist_ok=True)
    license_file_root.mkdir(parents=True, exist_ok=True)

    entries: list[tuple[str, Path, dict]] = []
    attribution_files = 0

    for source_file in sorted(source_root.rglob("qt_attribution.json")):
        attribution_files += 1
        relative = source_file.relative_to(source_root)
        destination = attribution_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_file, destination)

        # Qt's attribution files are consumed by Qt's own scanner and a few of
        # them contain literal control characters inside long text fields. The
        # Python decoder's non-strict mode accepts that Qt-authored JSON dialect
        # without changing the original file that we preserve in the bundle.
        data = json.loads(source_file.read_text(encoding="utf-8"), strict=False)
        for entry in normalize_entries(data, source_file):
            parts = entry.get("QtParts", ["libs"])
            if isinstance(parts, str):
                parts = [parts]
            # Bezel redistributes runtime libraries/plugins, not examples/tests.
            # Over-inclusion is intentional: if an entry can be library content,
            # retain its notice even if a particular platform build optimizes it out.
            if "libs" not in parts:
                continue
            entries.append((str(entry.get("QDocModule", "qtbase")), relative, entry))

            referenced: list[str] = []
            if isinstance(entry.get("LicenseFile"), str):
                referenced.append(entry["LicenseFile"])
            if isinstance(entry.get("LicenseFiles"), list):
                referenced.extend(str(item) for item in entry["LicenseFiles"])
            if isinstance(entry.get("CopyrightFile"), str):
                referenced.append(entry["CopyrightFile"])

            for reference in referenced:
                candidate = (source_file.parent / reference).resolve()
                try:
                    rel = candidate.relative_to(source_root.resolve())
                except ValueError as exc:
                    raise RuntimeError(
                        "third-party attribution references a file outside QtBase: "
                        f"{source_file}: {reference}"
                    ) from exc
                copy_if_file(candidate, license_file_root / rel)

    # Preserve conventional third-party license/notice files even when legacy
    # metadata does not explicitly name them.
    thirdparty = source_root / "src" / "3rdparty"
    if thirdparty.is_dir():
        for candidate in sorted(thirdparty.rglob("*")):
            if not candidate.is_file():
                continue
            upper = candidate.name.upper()
            if upper.startswith(("LICENSE", "COPYING", "NOTICE", "COPYRIGHT")):
                rel = candidate.relative_to(source_root)
                copy_if_file(candidate, license_file_root / rel)

    entries.sort(
        key=lambda item: (item[0].lower(), str(item[2].get("Name", "")).lower())
    )
    notice = qt_root / "QTBASE-THIRD-PARTY-NOTICES.md"
    with notice.open("w", encoding="utf-8", newline="\n") as out:
        out.write("# QtBase third-party notices\n\n")
        out.write(
            "Generated from the `qt_attribution.json` files in the exact QtBase "
            "source archive shipped with this Bezel release. Entries marked as "
            "runtime-library (`libs`) content are included. Extra notices may be "
            "present; over-inclusion is intentional.\n\n"
        )
        for module, relative, entry in entries:
            name = (
                render_value(entry.get("Name"))
                or render_value(entry.get("Id"))
                or "Unnamed component"
            )
            version = render_value(entry.get("Version"))
            out.write(f"## {name}" + (f" — {version}" if version else "") + "\n\n")
            fields = [
                ("Qt documentation module", module),
                ("License", render_value(entry.get("License"))),
                ("License identifier", render_value(entry.get("LicenseId"))),
                ("Homepage", render_value(entry.get("Homepage"))),
                ("Download location", render_value(entry.get("DownloadLocation"))),
                ("Qt usage", render_value(entry.get("QtUsage"))),
                ("Copyright", render_value(entry.get("Copyright"))),
                ("Attribution metadata", str(relative).replace(os.sep, "/")),
            ]
            for label, value in fields:
                if value:
                    out.write(f"- **{label}:** {value}\n")
            out.write("\n")

    return attribution_files, len(entries)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="dist/compliance")
    parser.add_argument("--policy", default="release/qt-runtime-policy.json")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    policy_path = (repo_root / args.policy).resolve()
    output_root = (repo_root / args.out_dir).resolve()
    policy = json.loads(policy_path.read_text(encoding="utf-8"))

    version = policy["qt_version"]
    archive_name = policy["source_archive"]
    source_url = policy["source_url"]
    expected_hash = policy["source_sha256"].lower()
    applied_patches = [
        entry
        for entry in policy["security_patch_inventory"]
        if entry["status"] == "applied"
    ]

    if policy.get("public_release_license_mode") != "lgpl":
        raise RuntimeError("public release policy must remain fail-closed on LGPL")
    if policy.get("public_release_linkage") != "dynamic":
        raise RuntimeError("public Qt redistribution must use dynamic linking")
    if policy.get("public_workflow_may_publish_commercial_qt") is not False:
        raise RuntimeError("public workflow must not claim commercial Qt rights")

    shutil.rmtree(output_root, ignore_errors=True)
    runtime_licenses = output_root / "runtime-licenses"
    qt_root = runtime_licenses / "Qt"
    source_output = output_root / "source"
    patch_output = source_output / "patches"
    runtime_licenses.mkdir(parents=True, exist_ok=True)
    patch_output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="bezel-qt-compliance-") as tmp:
        tmp_path = Path(tmp)
        downloaded = tmp_path / archive_name
        print(f"Downloading exact QtBase source: {source_url}")
        download(source_url, downloaded)
        actual_hash = sha256(downloaded)
        if actual_hash.lower() != expected_hash:
            raise RuntimeError(
                f"QtBase source SHA-256 mismatch: expected {expected_hash}, got {actual_hash}"
            )

        extracted = tmp_path / "src"
        extracted.mkdir()
        safe_extract(downloaded, extracted)
        source_root = extracted / f"qtbase-everywhere-opensource-src-{version}"
        if not source_root.is_dir():
            candidates = [path for path in extracted.iterdir() if path.is_dir()]
            if len(candidates) != 1:
                raise RuntimeError("could not identify QtBase source root after extraction")
            source_root = candidates[0]

        qt_license_dir = source_root / "LICENSES"
        if not qt_license_dir.is_dir():
            raise RuntimeError("QtBase source archive does not contain LICENSES/")
        shutil.copytree(qt_license_dir, qt_root / "LICENSES")

        for metadata_name in ("REUSE.toml", "licenseRule.json"):
            copy_if_file(source_root / metadata_name, qt_root / metadata_name)

        attribution_files, runtime_entries = generate_attributions(source_root, qt_root)
        if runtime_entries == 0:
            raise RuntimeError("no runtime third-party attribution entries were generated")

        shutil.copy2(downloaded, source_output / archive_name)

        patch_manifest = {
            "qt_version": version,
            "base_source_archive": archive_name,
            "base_source_sha256": expected_hash,
            "security_reviewed_through": policy["security_reviewed_through"],
            "patches": [],
        }
        for entry in applied_patches:
            patch = tmp_path / entry["file"]
            print(f"Downloading official Qt security patch: {entry['url']}")
            download(entry["url"], patch)
            patch_hash = sha256(patch)
            if patch_hash.lower() != entry["sha256"].lower():
                raise RuntimeError(
                    f"Qt security patch SHA-256 mismatch for {entry['file']}: "
                    f"expected {entry['sha256']}, got {patch_hash}"
                )
            shutil.copy2(patch, patch_output / entry["file"])
            patch_manifest["patches"].append(
                {
                    "cve": entry["cve"],
                    "file": entry["file"],
                    "url": entry["url"],
                    "sha256": patch_hash,
                }
            )

        manifest_path = source_output / "QT-SOURCE-MANIFEST.json"
        manifest_path.write_text(
            json.dumps(patch_manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        with tarfile.open(
            source_output / f"qtbase-{version}-security-patches.tar.gz", "w:gz"
        ) as bundle:
            bundle.add(manifest_path, arcname=manifest_path.name)
            bundle.add(patch_output, arcname="patches")

    shutil.copy2(repo_root / "LICENSE", runtime_licenses / "BEZEL-MIT.txt")
    shutil.copy2(
        repo_root / "docs" / "LGPL_RELINKING.md", runtime_licenses / "RELINKING.md"
    )
    shutil.copy2(policy_path, runtime_licenses / "QT-RUNTIME-POLICY.json")

    (qt_root / "QT-SOURCE.txt").write_text(
        "\n".join(
            [
                f"Qt version: {version}",
                f"Qt module source: {policy['qt_module']}",
                f"Source archive: {archive_name}",
                f"Source URL used by the release builder: {source_url}",
                f"SHA-256: {expected_hash}",
                "",
                f"Security reviewed through: {policy['security_reviewed_through']}",
                "",
                "Tagged Bezel LGPL releases publish this exact verified base source",
                "archive plus the verified official security-patch bundle alongside",
                "the binary runtime packages. Apply the patches in manifest order",
                "with scripts/prepare-pinned-qt-source.py from the tagged Bezel source.",
                "Downstream redistributors must satisfy their own source-availability",
                "and notice obligations under their own control.",
                "",
            ]
        ),
        encoding="utf-8",
        newline="\n",
    )

    notice_text = (
        "# Bezel native runtime licensing notice\n\n"
        "Bezel's own source and shim are MIT licensed; see `BEZEL-MIT.txt`.\n\n"
        f"This public prebuilt runtime contains dynamically linked QtBase {version} "
        "libraries/plugins and is prepared for redistribution using Qt's LGPL v3 "
        "open-source licensing path. The applicable Qt license texts are under "
        "`Qt/LICENSES/`, and generated third-party notices are in "
        "`Qt/QTBASE-THIRD-PARTY-NOTICES.md`.\n\n"
        "The Qt libraries are not statically linked into Bezel. The runtime layout "
        "is intentionally replaceable; see `RELINKING.md` for installation and "
        "replacement instructions. Bezel does not impose DRM or license terms that "
        "forbid reverse engineering for the purpose permitted by the LGPL.\n\n"
        "The exact verified QtBase base source and applied official security patches "
        "are published with each tagged Bezel LGPL release. See `Qt/QT-SOURCE.txt`.\n\n"
        "Linux operating-system libraries and the Windows Microsoft Visual C++ "
        "runtime are prerequisites, not redistributed inside Bezel's public runtime "
        "archives. This deliberately reduces unrelated third-party redistribution "
        "obligations.\n\n"
        "If you redistribute these binaries as part of another product, you are a "
        "redistributor too: preserve the required notices and user freedoms and make "
        "the corresponding source available under your control. Product-specific "
        "legal review is still appropriate.\n"
    )
    (runtime_licenses / "NOTICE.md").write_text(
        notice_text, encoding="utf-8", newline="\n"
    )

    compliance_summary = {
        "schema_version": 2,
        "qt_version": version,
        "qt_source_archive": archive_name,
        "qt_source_sha256": expected_hash,
        "security_reviewed_through": policy["security_reviewed_through"],
        "applied_security_patches": [entry["cve"] for entry in applied_patches],
        "linkage": "dynamic",
        "public_release_license_mode": "lgpl",
        "attribution_files_scanned": attribution_files,
        "runtime_attribution_entries": runtime_entries,
        "linux_system_libraries_redistributed": False,
        "windows_msvc_runtime_redistributed": False,
    }
    (runtime_licenses / "COMPLIANCE.json").write_text(
        json.dumps(compliance_summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    print(f"Prepared runtime license material: {runtime_licenses}")
    print(f"Prepared verified corresponding source: {source_output / archive_name}")


if __name__ == "__main__":
    main()
