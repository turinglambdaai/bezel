# Packaging and signing a Bezel application

This guide takes a Bezel application from Racket source to a
redistributable, signed application folder. It is an engineering
checklist, not legal advice; Qt licensing decisions are covered by
[COMMERCIAL_RELEASE.md](COMMERCIAL_RELEASE.md).

## 1. Package

```bash
raco bezel package --entry my-app.rkt --name MyApp --dest dist
```

The command produces:

```text
dist/MyApp/
├── MyApp[.exe]            # Windows: single exe with the Racket runtime embedded
├── bin/MyApp              # macOS/Linux: launcher (raco distribute layout)
├── lib/                   # macOS/Linux: Racket runtime libraries
├── [bin/]native/<os>-<arch>/   # libbezel + Qt + plugins, beside the executable
└── RUNNING.txt
```

The native runtime always sits beside the actual executable — `<exe-dir>/native/<os>-<arch>/` is the loader search step that makes the folder self-contained.

Runtime selection order: `--runtime-dir`, then `$BEZEL_NATIVE_DIR`, then
the installed `bezel-lib` package's bundled runtime (the
`bezel-lib-<platform>.zip` release package). At startup the executable
resolves `<exe-dir>/native/<os>-<arch>/` — the loader search order is
documented in the README and `bezel-lib/private/lib.rkt`.

Verify headlessly before shipping:

```bash
# Windows
QT_QPA_PLATFORM=offscreen ./dist/MyApp/MyApp.exe
# macOS / Linux
QT_QPA_PLATFORM=offscreen ./dist/MyApp/bin/MyApp
```

CI performs this exact check on all three release targets via
`scripts/app-smoke.rkt`.

## 2. Cross-platform note

Build the package on each target platform — the native runtime and the
executable are platform-specific. The GitHub Release
`bezel-native-<platform>` archives can seed `--runtime-dir` on machines
without a local Qt toolchain.

## 3. Sign

Signing is product responsibility; Bezel ships helpers, not decisions.

**Windows** — Authenticode via `signtool` (Windows SDK):

```powershell
./scripts/sign-app-windows.ps1 -AppDir dist/MyApp -Thumbprint <sha1>
```

Every `.exe`/`.dll` under the folder is signed, timestamped, and
verified. For hardware-token or cloud-signing services, adapt the
signtool invocation.

**macOS** — Developer ID codesign + notarization:

```bash
./scripts/sign-app-macos.sh dist/MyApp "Developer ID Application: ACME Inc (TEAMID)"
NOTARY_PROFILE=acme-notary ./scripts/sign-app-macos.sh dist/MyApp "Developer ID Application: ACME Inc (TEAMID)"
```

With `NOTARY_PROFILE` set, the folder is also submitted to Apple's
notary service, stapled, and checked with `spctl`. The notary profile is
created once with `xcrun notarytool store-credentials`.

**Linux** — no equivalent platform signing; distribute checksums (the
release pipeline already publishes `SHA256SUMS` for runtime archives).

## 4. Ship

Zip (or `ditto` on macOS) the signed folder. End users need neither
Racket nor Qt. Reminders:

- A prebuilt Bezel runtime redistributes Qt under Qt's license terms —
  pick and comply with the right Qt license for the modules you ship.
- macOS Gatekeeper requires notarization for first-run approval outside
  `xattr -d com.apple.quarantine`.
- Keep `native/` beside the executable; the loader also honors
  `BEZEL_NATIVE_DIR`/`BEZEL_LIBRARY` for advanced deployment layouts.

## 5. Tell users about updates

Host one static JSON file anywhere you control (release bucket, GitHub
Pages, CDN) and check it from the app:

```racket
(after! 1000 (lambda ()
  (check-and-prompt-update!
   #:feed "https://example.com/myapp-updates.json"
   #:current "1.2.3"
   #:parent win)))
```

Feed format (update it when you publish a release):

```json
{"version": "1.3.0",
 "url": "https://github.com/me/myapp/releases/latest",
 "notes": "Highlight the changes"}
```

Failures are quiet (`#f`), so a dead URL or an offline machine never
disrupts startup. This is a check-and-notify flow; downloading and
replacing the application remains a distribution-channel decision.
