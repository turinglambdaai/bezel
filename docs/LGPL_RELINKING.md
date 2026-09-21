# Replacing or relinking the Qt libraries in a Bezel runtime

Bezel's public prebuilt runtime packages use dynamically linked QtBase libraries. The package layout is intentionally designed so a recipient can replace those Qt libraries and plugins with a compatible modified build and run Bezel against the replacement.

This document describes the Bezel SDK layout. It does not replace the LGPL text and is not legal advice. The authoritative license texts shipped with the runtime are under `LICENSES/Qt/LICENSES/`.

## General procedure

1. Copy the Bezel native runtime directory to a location you can modify.
2. Build or obtain a compatible QtBase build for the same operating system, CPU architecture, Qt major/minor ABI, and toolchain ABI required by the target. The official Bezel build starts from the published QtBase 6.8.4 archive and applies the release's published patch bundle in manifest order with `scripts/prepare-pinned-qt-source.py`.
3. Replace the Qt shared libraries/frameworks and any matching Qt plugins in that copied runtime. Keep the expected Qt library names and plugin directory layout.
4. Point Bezel at the copied runtime with `BEZEL_NATIVE_DIR`, or install a rebuilt `bezel-lib` package containing that runtime.
5. Run `raco bezel doctor` and the application's own tests before normal use.

Bezel does not require a cryptographic signature from the original Bezel distributor before loading the package-local Qt libraries. `BEZEL_REQUIRE_PACKAGED_RUNTIME=1` only disables fallback to source/system copies during hermetic testing; it does not prevent replacement of files inside the selected runtime.

## Linux

The package keeps `libbezel.so*`, the shipped `libQt6*.so*` files, and selected Qt plugins together. Their runtime search paths are relative to the package (`$ORIGIN` / `$ORIGIN/..`).

Replace the Qt shared objects and corresponding plugins in the copied runtime directory, preserving SONAME-compatible filenames. Then run, for example:

```text
BEZEL_NATIVE_DIR=/path/to/modified/bezel-native-linux-x86_64 \
QT_QPA_PLATFORM=offscreen \
raco bezel doctor
```

The Bezel public Linux archive does **not** copy general Ubuntu/system shared libraries into the runtime. Those remain operating-system prerequisites.

## Windows

The package keeps `bezel.dll`, `Qt6*.dll`, and Qt plugins such as `platforms/qwindows.dll` together. Replace the Qt DLLs/plugins in a copied runtime and point `BEZEL_NATIVE_DIR` at that directory.

The Microsoft Visual C++ runtime is an operating-system prerequisite for the official Bezel Windows build and is **not** redistributed inside the Bezel public archive. A replacement Qt build may have different toolchain runtime requirements.

## macOS

Qt frameworks and plugins are under:

```text
BezelRuntime.app/Contents/Frameworks/
BezelRuntime.app/Contents/PlugIns/
```

Replace the Qt frameworks/plugins there. Because modifying Mach-O files invalidates a prior code signature, re-sign the modified local bundle before loading it:

```text
codesign --force --deep --sign - --timestamp=none BezelRuntime.app
```

The `-` identity creates an ad-hoc signature suitable for local testing. It is not a Developer ID distribution signature.

Then point `BEZEL_NATIVE_DIR` at the directory that contains `BezelRuntime.app` and run `raco bezel doctor`.

## Downstream application signing and stores

A downstream application distributor using the LGPL path must preserve the recipient's applicable LGPL rights, including the practical ability to use a modified/relinked Qt library where required. Do not add DRM, signature enforcement, contractual restrictions, or a distribution mechanism that removes those rights.

Some application stores, hardened devices, managed-device policies, or signing/notarization designs can conflict with the LGPL replacement/relinking requirements. Evaluate the final product and distribution channel separately. If those obligations cannot be met, use a Qt licensing arrangement that grants the required rights instead of publishing under this Bezel public LGPL runtime path.
