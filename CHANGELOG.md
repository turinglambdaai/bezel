# Changelog

All notable changes to Bezel are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 0.2.0 — 2026-09-21

Commercial-hardening release focused on correctness, reproducibility, portable native distribution, and auditable licensing.

### Added

- Native ABI compatibility guard between the Racket bindings and `libbezel`.
- Lifecycle-safe signal connection cleanup and target ownership validation.
- GUI-thread marshaling and error propagation for generated bindings.
- Cross-platform generated-binding reproducibility checks in CI.
- Portable native runtime discovery via `BEZEL_NATIVE_DIR` and package-local platform directories.
- `raco bezel doctor` for platform, runtime-path, environment, and ABI diagnostics.
- Windows runtime packaging through `windeployqt`, including headless/offscreen platform support.
- macOS runtime packaging through `macdeployqt`, with an intact relocatable app-bundle runtime layout.
- Linux relocatable runtime packaging with Qt libraries/plugins and explicit `$ORIGIN` RPATHs.
- Clean-runner runtime smoke tests on Linux x86_64, Windows x86_64, and macOS arm64. These jobs install Racket only and exercise real Qt widgets from the packaged runtime.
- Tag-driven GitHub Release workflow that rebuilds, clean-smoke-tests, checksums, and publishes verified native runtime archives.
- Fail-closed public Qt redistribution policy pinned to QtBase 6.8.3, LGPLv3 dynamic linking, and a reviewed exact-source SHA-256.
- Per-runtime `LICENSES/` bundle with Qt/LGPL license texts, Bezel MIT text, third-party attribution metadata/notices, relinking instructions, and machine-readable compliance metadata.
- Verified corresponding-source generation: tagged public releases publish the exact QtBase source archive beside binaries rather than relying on an upstream source URL alone.
- `scripts/check-license-policy.py` to prevent wildcard Qt versions, accidental public commercial-Qt claims, or reintroduction of unrelated bundled runtime libraries.
- Commercial release engineering checklist covering runtime support, Qt redistribution decisions, signing/notarization, and release blockers.

### Changed

- Public GitHub binary releases are LGPLv3-only. Commercial-Qt product builds must use a separate private pipeline backed by the license holder's commercial Qt distribution/provenance.
- Public Linux runtimes redistribute Bezel + Qt only; host/system libraries remain OS prerequisites instead of being recursively copied into the archive.
- Public Windows runtimes no longer redistribute MSVC CRT DLLs; a compatible Visual C++ runtime is a target prerequisite.

### Fixed

- Public lifetime documentation now matches the no-deleting-finalizer ownership model.
- Temporary FFI allocations in PNG capture and test-signal marshaling are released deterministically.
- Failed native disconnects no longer unregister live Racket signal handlers.
- Destroyed Qt targets retire native connection records and Racket handlers.
- Wrong-widget sentinel values now surface native errors instead of leaking sentinel integers to callers.
- Reparenting updates Racket-side ownership state.
- Pump arguments are validated before reaching native code.
- Example applications create `QApplication` before constructing widgets.

## 0.1.0 — 2025-09-15

First release: Qt 6 Widgets bound to Racket, end to end.

### Fixed (during stabilization, same release)

- Marshal queue races: enqueue (any caller thread) vs drain (pump) is
  lock-protected; lost tasks previously surfaced as random CI hangs.
- Shim errors are replayed across the marshal boundary (thread-local
  errors never traveled with marshaled calls).
- Qt inline calls are restricted to the Racket main thread (OS-thread
  identity checks are unsound under Racket CS thread multiplexing).
- No deleting finalizers: objects live until teardown or
  `bezel-delete!` (late finalizers destroyed recycled widget addresses).
- Quit-on-last-window-closed arms correctly for the pump; window-close
  exit code no longer leaks from a previous quit!.

### Added

- **C++ shim** (`bezel-shim/`): stable C ABI over Qt 6 — application
  lifecycle, 12 widget constructors, shared widget API (text, checked,
  int value, enable, geometry, stylesheet), 4 layouts with tree and
  imperative forms, menus/actions, standard dialogs, PNG widget capture
  (`bezel_widget_grab_png`).
- **Racket bindings** (`bezel-lib/`): collection `bezel` with
  `make-application` / `run` (cooperative pump loop) / `quit!`;
  `make-*` constructors with keyword options; `connect!` /
  `disconnect!` / `emit-test-signal!`; explicit lifetime/ownership APIs
  (`bezel-alive?`, `bezel-delete!`); `exn:fail:bezel` error surface with
  shim messages attached.
- **Threading model**: cooperative GUI-thread marshaling (any Racket
  thread can call any bezel function; calls from handlers and other
  threads are queued and drained by the pump) and a signal dispatcher
  thread that applies handlers outside the GUI thread. The C side never
  blocks on a cross-thread handoff.
- **Signal bridge**: QMetaMethod→sink connections with typed first
  argument delivery (bool / int / QString), argument-less fallback for
  everything else, and `emit-test-signal!` for deterministic headless
  testing.
- **Binding generator** (`tools/generator/`): JSON class specs emit both
  the shim and Racket sides; `QDial` ships as the worked example.
- **Headless e2e suite** (`bezel-test/`): 23 tests over real Qt objects
  (widgets, layouts, typed signals, pump loop, cross-thread calls, PNG
  rendering), run on all three platforms in CI with
  `QT_QPA_PLATFORM=offscreen`.
- **CI** (`.github/workflows/ci.yml`): 3-OS build of the shim against
  Qt 6 + full Racket test suite + showcase screenshot generation.
- **Examples**: `hello.rkt`, `counter.rkt` (QSS styling), `form.rkt`
  (form layout + menus + dialogs).
- **Docs**: bilingual README (EN/zh-CN), `docs/architecture.md`
  deep dive, Scribble docs, CONTRIBUTING, AGENTS.md.
