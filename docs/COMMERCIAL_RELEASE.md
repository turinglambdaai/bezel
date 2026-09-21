# Commercial release guide

Bezel itself is MIT licensed. A product that redistributes Bezel's prebuilt native runtime also redistributes Qt libraries, plugins, and on Linux a selected runtime dependency closure, so the product owner must choose and comply with the applicable licenses for that distribution.

This document is an engineering release checklist, not legal advice. Verify the licensing model for the exact Qt version/modules and third-party libraries used by your product and obtain legal review when shipping a commercial product.

## Supported release targets

The automated release pipeline currently builds and smoke-tests these targets:

| Runtime key | Build baseline | Clean smoke coverage | Raw runtime | Self-contained Racket package |
| --- | --- | --- | --- | --- |
| `linux-x86_64` | Ubuntu 22.04 x86_64 | Ubuntu 22.04 + Ubuntu 24.04, Racket only | `bezel-native-linux-x86_64.tar.gz` | `bezel-lib-linux-x86_64.zip` |
| `windows-x86_64` | current GitHub Windows x64 | fresh Windows runner, Racket only | `bezel-native-windows-x86_64.zip` | `bezel-lib-windows-x86_64.zip` |
| `macosx-aarch64` | current GitHub Apple Silicon macOS | fresh Apple Silicon macOS runner, Racket only | `bezel-native-macosx-aarch64.tar.gz` | `bezel-lib-macosx-aarch64.zip` |

Linux release binaries are deliberately built on Ubuntu 22.04 rather than `ubuntu-latest` so their glibc/libstdc++ baseline does not drift forward whenever GitHub changes its default runner. The Linux packager bundles the non-baseline ELF dependency closure required by the selected Qt runtime and plugins (for example ICU or image-codec dependencies) while leaving glibc and the C/C++ runtime to the supported OS baseline. The package is then smoke-tested on both Ubuntu 22.04 and 24.04.

A target is not considered supported merely because the C++ shim compiles. The release pipeline must also pass a second clean-runner smoke test that installs **Racket only**, installs the self-contained archive through `raco pkg install`, runs `raco bezel doctor`, creates real Qt widgets, pumps the event loop, and cleans up successfully. Clean smoke enables `BEZEL_REQUIRE_PACKAGED_RUNTIME=1`, so a passing run proves that Bezel loaded the package-local runtime instead of accidentally reusing a source build or system `libbezel`.

## Release flow

1. Merge only after the normal CI matrix and all clean package smoke jobs pass.
2. Update the Bezel version consistently in the Racket packages, CMake project, and changelog.
3. Create an annotated or lightweight `vX.Y.Z` tag from the intended main-branch commit.
4. The `Release` workflow validates that the tag exactly matches repository version metadata.
5. It verifies the explicit Qt redistribution acknowledgement configured for the repository before tagged publication is allowed.
6. It rebuilds all native runtimes from the tag.
7. It creates a platform-specific `bezel-lib-<platform>.zip` containing the Racket bindings plus that runtime under `native/<os>-<arch>/`.
8. Every self-contained package is re-tested on a fresh runner without installing Qt, CMake, or a C++ compiler; Linux is tested on both the baseline and a newer LTS runner.
9. Only after all smoke jobs pass does the workflow create the GitHub Release.
10. The release contains the raw runtimes, self-contained Racket packages, Racket-compatible `.CHECKSUM` files, a `SHA256SUMS` manifest, and a redistribution-mode record.
11. Before promoting a release to production customers, perform product-level signing/notarization and licensing checks appropriate to the final application.

The release workflow can also be started manually. Manual runs build and test artifacts but deliberately do not create a GitHub Release because there is no immutable version tag to publish.

## End-user installation contract

On a supported target, the user should need only Racket plus the normal operating-system baseline documented above:

```text
raco pkg install --auto --name bezel-lib /path/to/bezel-lib-<platform>.zip
raco bezel doctor
```

The explicit package name keeps the installed package identity stable (`bezel-lib`) even though GitHub release asset names include the target platform.

The archive's `info.rkt` still carries the semantic Bezel version. GitHub Release tags carry the release version externally, so the asset filename itself intentionally stays stable from release to release.

## Runtime layout contract

The Racket loader searches in this order:

1. `BEZEL_LIBRARY` — an explicit shared-library file.
2. `BEZEL_NATIVE_DIR` — the root of an extracted runtime archive.
3. `bezel-lib/native/<os>-<arch>/` — package-local runtime files used by self-contained release packages.
4. A source-checkout `bezel-shim/build` directory.
5. The operating system's normal dynamic-library search paths.

Set `BEZEL_REQUIRE_PACKAGED_RUNTIME=1` to disable source-build and system fallbacks. Release smoke tests always enable this mode.

If the runtime has a bundled Qt plugin directory and `QT_PLUGIN_PATH` has not been explicitly set by the application, Bezel configures it before creating `QApplication`.

Run:

```text
raco bezel doctor
```

for platform, architecture, environment, candidate-path, selected-shim, hermetic-mode, and ABI load diagnostics.

## Artifact integrity

Two checksum forms are published intentionally:

- `bezel-lib-<platform>.zip.CHECKSUM` uses the checksum format expected by Racket package distribution tooling.
- `SHA256SUMS` covers the release archives with SHA-256 for users, CI systems, mirrors, and supply-chain tooling.

A release is generated only from an immutable `v*` tag after the clean installation tests pass.

## Qt and third-party redistribution

The public CI configuration installs the open-source Qt packages available to the GitHub-hosted runners/package managers. That is suitable for open-source CI validation, but it does not by itself decide the license under which a commercial product should redistribute Qt or the third-party libraries included in a runtime dependency closure.

For a commercial product, make that choice explicitly:

- If using a Qt commercial license, build release runtimes from the Qt distribution and terms applicable to that license.
- If redistributing under an open-source Qt license, satisfy all obligations that apply to the exact modules and version being shipped, including required notices/license text, source/relinking requirements where applicable, and other distribution conditions.
- Review licenses for non-Qt libraries copied into the Linux runtime closure and include required notices/source offers where applicable.

Tagged publication fails closed unless the repository explicitly acknowledges the Qt redistribution mode. See [QT_REDISTRIBUTION_GATE.md](QT_REDISTRIBUTION_GATE.md).

Do not treat Bezel's MIT license as replacing Qt's or bundled third-party components' license terms.

Official references:

- Qt licensing: https://www.qt.io/licensing/
- Qt open-source obligations: https://www.qt.io/licensing/open-source-lgpl-obligations
- Qt deployment overview: https://doc.qt.io/qt-6/deployment.html

## Product signing

The repository-level packages are SDK/runtime inputs. The final desktop product should own platform trust decisions:

- Windows: Authenticode-sign the executable/installer and any binaries required by the product's signing policy.
- macOS: sign the final application bundle and perform notarization when distributing outside the Mac App Store.
- Linux: publish package/repository signatures or another verifiable software-supply-chain mechanism appropriate to the distribution channel.

Signing identities and notarization credentials are intentionally not stored in this public repository.

## Release blockers

Do not publish a production release when any of these are true:

- ABI version in Racket and the shim disagree.
- A native packaging job fails.
- A clean self-contained package smoke job fails.
- Generated bindings are dirty after regeneration.
- The changelog/version/tag do not agree.
- A required runtime dependency or Qt platform plugin is absent from the package.
- Required Qt/third-party licensing material for the chosen distribution model has not been prepared.
- The final commercial application has not completed the signing/notarization process required by its distribution channel.
