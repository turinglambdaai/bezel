# Commercial release guide

Bezel itself is MIT licensed. A product that redistributes Bezel's prebuilt native runtime also redistributes Qt libraries and plugins, so the product owner must choose and comply with an appropriate Qt license for that distribution.

This document is an engineering release checklist, not legal advice. Verify the licensing model for the exact Qt version/modules used by your product and obtain legal review when shipping a commercial product.

## Supported release runtimes

The automated release pipeline currently builds and smoke-tests these runtime bundles:

| Runtime key | GitHub runner | Archive |
| --- | --- | --- |
| `linux-x86_64` | Ubuntu | `bezel-native-linux-x86_64.tar.gz` |
| `windows-x86_64` | Windows | `bezel-native-windows-x86_64.zip` |
| `macosx-aarch64` | macOS | `bezel-native-macosx-aarch64.tar.gz` |

A runtime is not considered supported merely because the C++ shim compiles. The release pipeline must also pass a second clean-runner smoke test that installs Racket only, downloads the packaged runtime, runs `raco bezel doctor`, creates real Qt widgets, pumps the event loop, and cleans up successfully.

## Release flow

1. Merge only after the normal CI matrix and all clean runtime smoke jobs pass.
2. Update the Bezel version consistently in the Racket packages, CMake project, and changelog.
3. Create an annotated or lightweight `vX.Y.Z` tag from the intended main-branch commit.
4. The `Release` workflow rebuilds all native runtimes from the tag.
5. Every runtime is re-tested on a fresh runner without installing the Qt development environment.
6. Only after those smoke jobs pass does the workflow create the GitHub Release.
7. The release contains all runtime archives plus `SHA256SUMS`.
8. Before promoting a release to production customers, perform product-level signing/notarization and licensing checks appropriate to the final application.

The release workflow can also be started manually. Manual runs build and test artifacts but deliberately do not create a GitHub Release because there is no immutable version tag to publish.

## Runtime layout contract

The Racket loader searches in this order:

1. `BEZEL_LIBRARY` — an explicit shared-library file.
2. `BEZEL_NATIVE_DIR` — the root of an extracted runtime archive.
3. `bezel-lib/native/<os>-<arch>/` — package-local runtime files, for future platform-specific Racket packages.
4. A source-checkout `bezel-shim/build` directory.
5. The operating system's normal dynamic-library search paths.

If the runtime has a bundled Qt plugin directory and `QT_PLUGIN_PATH` has not been explicitly set by the application, Bezel configures it before creating `QApplication`.

Run:

```text
raco bezel doctor
```

for platform, architecture, environment, candidate-path, and ABI load diagnostics.

## Qt redistribution

The public CI configuration installs the open-source Qt packages available to the GitHub-hosted runners/package managers. That is suitable for open-source CI validation, but it does not by itself decide the license under which a commercial product should redistribute Qt.

For a commercial product, make that choice explicitly:

- If using a Qt commercial license, build release runtimes from the Qt distribution and terms applicable to that license.
- If redistributing under an open-source Qt license, satisfy all obligations that apply to the exact modules and version being shipped, including the required notices/license text, source/relinking requirements where applicable, and any other distribution conditions.

Do not treat Bezel's MIT license as replacing Qt's license terms for Qt binaries.

Official references:

- Qt licensing: https://www.qt.io/licensing/
- Qt open-source obligations: https://www.qt.io/licensing/open-source-lgpl-obligations
- Qt deployment overview: https://doc.qt.io/qt-6/deployment.html

## Product signing

The repository-level runtime artifacts are intended as SDK/runtime inputs. The final desktop product should own platform trust decisions:

- Windows: Authenticode-sign the executable/installer and any binaries required by the product's signing policy.
- macOS: sign the final application bundle and perform notarization when distributing outside the Mac App Store.
- Linux: publish package/repository signatures or another verifiable software-supply-chain mechanism appropriate to the distribution channel.

Signing identities and notarization credentials are intentionally not stored in this public repository.

## Release blockers

Do not publish a production release when any of these are true:

- ABI version in Racket and the shim disagree.
- A native-package job fails.
- A clean runtime smoke job fails.
- Generated bindings are dirty after regeneration.
- The changelog/version does not match the intended tag.
- Required Qt licensing material for the chosen distribution model has not been prepared.
- The final commercial application has not completed the signing/notarization process required by its distribution channel.
