# Qt redistribution gate

Bezel's public CI can build portable runtime bundles containing Qt shared libraries and plugins. A technically valid bundle is not automatically a legally distributable bundle, so public tagged releases fail closed unless the exact redistribution policy is acknowledged.

## Public release policy

The public GitHub Actions release path is intentionally narrow and auditable:

- Qt is pinned to the public **QtBase 6.8.4** source plus reviewed official Qt 6.8 security patches through **2026-09-22**.
- Bezel and Qt are dynamically linked.
- Public prebuilt binaries use the **LGPLv3** path only.
- Every target is rebuilt from the same exact public source-and-patch set; public online Qt binaries are not release inputs.
- The exact QtBase base source and applied patches are downloaded from `download.qt.io`, verified against reviewed SHA-256 values in `release/qt-runtime-policy.json`, and published as release assets beside the binaries.
- License texts, Bezel's MIT license, third-party attribution metadata/notices, source metadata, and relinking instructions are embedded in every native runtime package.
- Linux host/system libraries are not recursively copied into the public Bezel bundle.
- The Microsoft Visual C++ runtime is not copied into the public Windows bundle; it remains a target-machine prerequisite.

The public workflow **does not publish a commercial-Qt build**. A commercial Qt license is a valid product strategy, but a public CI job using public Qt artifacts cannot prove private commercial entitlement or that a binary came from the licensed commercial distribution. A commercial-Qt product release therefore belongs in a separate private pipeline whose Qt provenance and entitlements are controlled by the license holder.

## Repository variables for tagged public releases

Before creating a production tag, configure:

- `BEZEL_QT_LICENSE_MODE=lgpl`
- `BEZEL_QT_REDISTRIBUTION_ACK=approved-lgpl-v3`

No external source-offer URL is accepted as a substitute for the tagged release's source assets. The release itself publishes `qtbase-everywhere-opensource-src-6.8.4.tar.xz`, the applied-patch bundle, and `QT-SOURCE-MANIFEST.json`.

Manual workflow-dispatch runs may build and smoke-test artifacts but do not publish a GitHub Release.

## Automated blockers

The repository contains `release/qt-runtime-policy.json` and `scripts/check-license-policy.py`. CI fails when the public workflow drifts from the pinned source/patch hashes, switches away from dynamic LGPL distribution, uses prebuilt Qt for a release runtime, re-enables public commercial-Qt publication, reintroduces wildcard Qt versions, or re-enables bundled Linux system/MSVC runtime libraries. The checker also compares the reviewed inventory with Qt's live official 6.8 `qtbase` patch index and fails on any new, removed, or unreviewed patch.

The native packagers also reject unexpected non-Qt runtime libraries in the public package and `scripts/verify-release-layout.rkt` rejects packages missing mandatory licensing/relinking material.

## LGPL obligations remain product-level obligations

The automation is designed to make compliance evidence reproducible, but downstream products still have obligations of their own. In particular, preserve applicable Qt/LGPL notices and license texts, make corresponding Qt source available under the distributor's control, and preserve the user's ability to replace/relink the LGPL libraries and run the modified result where required. See `LGPL_RELINKING.md`.

Application stores, DRM/signing designs, locked devices, contractual terms, or other distribution constraints can conflict with LGPL rights. Evaluate the final application and distribution channel separately. When the product cannot satisfy those conditions, use an appropriate Qt commercial licensing arrangement and a private commercial release pipeline instead of this public LGPL binary path.

## Release record

A tagged public release includes:

- `QT-REDISTRIBUTION.txt` recording Qt version, LGPL mode, dynamic linkage, source/patch assets, and the security review date;
- the exact QtBase base source, applied-patch bundle, and source manifest;
- `SHA256SUMS` covering native runtimes, self-contained packages, base source, patch bundle, and source manifest;
- embedded `LICENSES/` material inside every runtime archive/package.

This is an engineering compliance control and audit trail, not a substitute for product-specific legal review.
