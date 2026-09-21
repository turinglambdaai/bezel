# Commercial release guide

Bezel itself is MIT licensed. Public prebuilt native runtimes also redistribute Qt libraries/plugins and therefore carry separate Qt/LGPL and Qt third-party obligations. Bezel's release engineering is designed to make those obligations visible, reproducible, and fail-closed rather than relying on a README promise.

This is an engineering compliance guide, not legal advice. The final product, installer, device, store/channel, contractual terms, signing/DRM model, and any libraries added by the product must still be reviewed for their own distribution requirements.

## Public binary licensing model

Bezel's **public GitHub Release workflow is LGPLv3-only** for Qt and deliberately uses a narrow, pinned configuration:

- QtBase public-source baseline: **6.8.4**.
- Linkage: **dynamic**.
- Exact base-source archive: `qtbase-everywhere-opensource-src-6.8.4.tar.xz`.
- Exact base-source SHA-256: `532dfbf3fa3cbc68fa37441ea9e81c5009da044eaecda78ffaeafd8bd125532f`.
- Security patch level: official Qt 6.8 patches reviewed through **2026-09-17**; all three public targets are rebuilt from the same verified source-and-patch set.
- Public commercial-Qt publication: **prohibited by policy**.
- Linux host/system libraries: **not copied into the Bezel public runtime**.
- Microsoft Visual C++ runtime: **not copied into the Bezel public Windows runtime**.

The policy is machine-readable in `release/qt-runtime-policy.json` and checked by `scripts/check-license-policy.py` on every CI/release run.

A commercial Qt license remains a valid choice for a proprietary product. However, that build must use a **separate private release pipeline** that uses the Qt distribution covered by the commercial agreement and can establish its provenance/entitlement. The public workflow must never convert public/open-source Qt artifacts into a build merely labelled "commercial".

## What every public runtime contains

The native runtime root contains a `LICENSES/` directory with at least:

- `NOTICE.md` — redistribution summary;
- `BEZEL-MIT.txt` — Bezel's license;
- `RELINKING.md` — practical Qt replacement/relinking instructions;
- `COMPLIANCE.json` — machine-readable compliance summary;
- `QT-RUNTIME-POLICY.json` — copied release policy;
- `Qt/LICENSES/` — license texts from the exact pinned QtBase source archive;
- `Qt/QT-SOURCE.txt` — exact source/version/hash record;
- `Qt/QTBASE-THIRD-PARTY-NOTICES.md` — generated attribution inventory;
- copied Qt `qt_attribution.json` metadata and referenced/nearby third-party license files.

A runtime missing this material is rejected by `scripts/verify-release-layout.rkt` before the self-contained Racket package can be created.

## Corresponding source

`scripts/prepare-qt-compliance.py` downloads the exact QtBase source archive and every applied official Qt 6.8 security patch from `download.qt.io`, verifies every pinned SHA-256, and generates the licensing bundle from that verified source tree. It does not trust whatever Qt installation happened to exist on the CI machine for license text, attribution generation, or release binaries.

For a tagged public release, the same verified QtBase base archive, patch bundle, and `QT-SOURCE-MANIFEST.json` are published as GitHub Release assets beside the binaries. The release also includes `SHA256SUMS`, covering the native archives, self-contained Racket packages, base source, patch bundle, and source manifest.

Publishing the source with the release is intentionally stronger and easier to audit than relying only on an upstream URL. A downstream redistributor still needs to make the corresponding source available under **its own** control and satisfy its own obligations to recipients.

## Relinking and replacement

The public runtime uses shared Qt libraries/frameworks. Its layout is deliberately replaceable; detailed platform instructions are in `LGPL_RELINKING.md`.

The product must not add terms or technical restrictions that take away LGPL rights. In particular, evaluate whether a store, DRM system, locked device, code-signing policy, or installer prevents the recipient from replacing/relinking Qt and running the modified result where the license requires that ability.

## Supported release targets

| Runtime key | Build target | Clean smoke coverage | Raw runtime | Self-contained Racket package |
| --- | --- | --- | --- | --- |
| `linux-x86_64` | Ubuntu 22.04 x86_64 runner + pinned QtBase | Ubuntu 22.04 + Ubuntu 24.04, Racket only | `bezel-native-linux-x86_64.tar.gz` | `bezel-lib-linux-x86_64.zip` |
| `windows-x86_64` | current GitHub Windows x64 + source-built patched QtBase | fresh Windows runner, Racket only | `bezel-native-windows-x86_64.zip` | `bezel-lib-windows-x86_64.zip` |
| `macosx-aarch64` | GitHub macOS 15 Apple Silicon + source-built patched QtBase | fresh Apple Silicon macOS runner, Racket only | `bezel-native-macosx-aarch64.tar.gz` | `bezel-lib-macosx-aarch64.zip` |

"Racket only" means the smoke job does not install a Qt SDK/compiler. Ordinary target-OS runtime prerequisites still apply. On Windows, a compatible Microsoft Visual C++ 2015-2022 runtime is an OS/application prerequisite rather than part of the Bezel public archive.

## Runtime dependency boundaries

### Linux

The public Linux packager copies a dependency only if the resolved library belongs to the selected pinned Qt installation. It rejects unexpected non-Qt shared objects at the package root. Host libraries such as the C/C++ runtime, X11/xcb stack, font/graphics libraries, and other OS dependencies remain system prerequisites instead of silently becoming Bezel redistributables. A diagnostic `SYSTEM-DEPENDENCIES.txt` records resolved host dependencies seen during packaging.

### Windows

`windeployqt` is run without compiler-runtime, software OpenGL, system D3D compiler, or system DXC redistribution. The packager rejects MSVC CRT, D3D compiler, DXC, software-OpenGL DLLs, and unexpected non-Qt top-level DLLs. A compatible VC++ runtime is documented as a prerequisite.

### macOS

The app-bundle staging area is restricted to Bezel plus Qt frameworks/plugins. The packager rejects unexpected non-Qt frameworks/dylibs, rewrites Qt paths for relocatable `dlopen` use, and ad-hoc signs the modified SDK bundle after `install_name_tool`. A final application must apply its own signing/notarization while preserving the licensing rights relevant to its chosen Qt model.

## Release flow

1. Merge only after the normal CI matrix, compliance generation, native packaging, and clean package smoke jobs pass.
2. Update Bezel version metadata/changelog consistently.
3. Create `vX.Y.Z` only from the intended `main` commit.
4. The Release workflow validates tag/version consistency and `scripts/check-license-policy.py`.
5. Tagged publication requires `BEZEL_QT_LICENSE_MODE=lgpl` and `BEZEL_QT_REDISTRIBUTION_ACK=approved-lgpl-v3`.
6. The exact QtBase base source and official security patches are downloaded, SHA-256 verified, and converted into source/licensing material.
7. Each native package is rebuilt from that same patched source and embeds the licensing material.
8. Each self-contained package is tested on a fresh runner with `BEZEL_REQUIRE_PACKAGED_RUNTIME=1` so it cannot fall back to a developer/source Qt build.
9. Only after all smoke tests pass does the workflow publish the binaries, exact QtBase base source, patch bundle/source manifest, redistribution record, and SHA-256 manifest.
10. The final customer-facing application/installer still performs its own signing, channel, dependency, and legal review.

Manual workflow-dispatch builds/test artifacts but does not create a GitHub Release.

## End-user installation contract

```text
raco pkg install --auto --name bezel-lib /path/to/bezel-lib-<platform>.zip
raco bezel doctor
```

The Racket loader searches in this order:

1. `BEZEL_LIBRARY` — explicit shared-library file.
2. `BEZEL_NATIVE_DIR` — extracted/modified runtime root.
3. `bezel-lib/native/<os>-<arch>/` — package-local runtime.
4. source-checkout build directory.
5. operating-system dynamic-library paths.

Set `BEZEL_REQUIRE_PACKAGED_RUNTIME=1` to disable source/system fallbacks during hermetic verification. This does not stop a recipient from replacing files inside the selected runtime.

## Product signing

- Windows: Authenticode-sign the final product/installer according to product policy.
- macOS: Developer ID sign/notarize the final application when appropriate. Modified local LGPL/relinking builds may need to be re-signed by the recipient; the Bezel relinking guide documents ad-hoc local signing.
- Linux: use repository/package signatures or another verifiable supply-chain mechanism appropriate to the distribution channel.

Signing must not be designed in a way that defeats rights required by the selected Qt/LGPL distribution model.

## Release blockers

Do not publish a public production release when any of these are true:

- ABI/version/tag/generated bindings disagree.
- The license policy checker fails.
- The exact QtBase base source or any required official security patch cannot be downloaded or fails SHA-256 verification.
- The live official Qt 6.8 `qtbase` patch index differs from the reviewed inventory.
- Required Qt/LGPL/third-party notice/relinking material is missing.
- The package accidentally includes a forbidden non-Qt runtime dependency.
- Bezel is no longer dynamically linked to the expected Qt libraries.
- Native packaging or a clean package smoke job fails.
- The final application/channel cannot preserve required LGPL recipient rights.
- The final product has unresolved licenses for application-specific dependencies.
- Required production signing/notarization/channel checks are incomplete.

## Official references

- Qt open-source/LGPL obligations: <https://www.qt.io/development/open-source-lgpl-obligations>
- Qt open-source usage overview: <https://www.qt.io/development/download-open-source>
- Qt deployment overview: <https://doc.qt.io/qt-6/deployment.html>
- QtBase 6.8.4 release source archive directory: <https://download.qt.io/official_releases/qt/6.8/6.8.4/submodules/>
- Official Qt 6.8 security patch index: <https://download.qt.io/official_releases/qt/6.8/>
- Microsoft Visual C++ redistribution guidance: <https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files>
