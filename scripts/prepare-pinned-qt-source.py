#!/usr/bin/env python3
"""Verify, extract, and patch the exact public QtBase release source."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_extract(archive: Path, destination: Path) -> None:
    destination_real = destination.resolve()
    with tarfile.open(archive, "r:xz") as source:
        for member in source.getmembers():
            target = (destination / member.name).resolve()
            if target != destination_real and destination_real not in target.parents:
                raise RuntimeError(f"unsafe path in Qt source archive: {member.name}")
        source.extractall(destination)


def run(command: list[str], cwd: Path) -> None:
    subprocess.run(command, cwd=cwd, check=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_archive")
    parser.add_argument("patch_dir")
    parser.add_argument("output_dir")
    parser.add_argument("--policy", default="release/qt-runtime-policy.json")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parent.parent
    policy = json.loads((repo / args.policy).read_text(encoding="utf-8"))
    archive = Path(args.source_archive).resolve()
    patch_dir = Path(args.patch_dir).resolve()
    output = Path(args.output_dir).resolve()

    expected_archive = policy["source_archive"]
    if archive.name != expected_archive:
        raise RuntimeError(f"expected source archive {expected_archive}, got {archive.name}")
    actual = sha256(archive)
    expected = policy["source_sha256"].lower()
    if actual != expected:
        raise RuntimeError(
            f"QtBase source SHA-256 mismatch: expected {expected}, got {actual}"
        )

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    safe_extract(archive, output)
    roots = [path for path in output.iterdir() if path.is_dir()]
    if len(roots) != 1:
        raise RuntimeError("could not identify the single QtBase source root")
    source_root = roots[0]

    applied: list[dict[str, str]] = []
    for entry in policy["security_patch_inventory"]:
        if entry["status"] != "applied":
            continue
        patch = patch_dir / entry["file"]
        if not patch.is_file():
            raise RuntimeError(f"required Qt security patch is missing: {patch}")
        patch_hash = sha256(patch)
        if patch_hash != entry["sha256"].lower():
            raise RuntimeError(
                f"security patch SHA-256 mismatch for {patch.name}: "
                f"expected {entry['sha256']}, got {patch_hash}"
            )
        run(["git", "apply", "--check", str(patch)], source_root)
        run(["git", "apply", str(patch)], source_root)
        applied.append(
            {"cve": entry["cve"], "file": patch.name, "sha256": patch_hash}
        )

    record = {
        "qt_version": policy["qt_version"],
        "source_archive": archive.name,
        "source_sha256": actual,
        "security_reviewed_through": policy["security_reviewed_through"],
        "applied_patches": applied,
    }
    (source_root / "BEZEL-QT-SOURCE.json").write_text(
        json.dumps(record, indent=2) + "\n", encoding="utf-8"
    )
    print(source_root)


if __name__ == "__main__":
    main()
