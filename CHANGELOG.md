# Changelog

All notable changes to Bezel are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 0.3.0

Phase 5 release: broader Qt class coverage, higher-level ergonomics, and
final-application packaging/signing helpers.

### Added

- **Generator-produced widget classes** (specs in `tools/generator/specs/`):
  `QRadioButton` (`radio-*`), `QGroupBox` (`groupbox-*`), `QDoubleSpinBox`
  (`doublespin-*`), `QLCDNumber` (`lcd-*`), `QTabWidget` (`tabs-*`),
  `QStackedWidget` (`stacked-*`), `QSplitter` (`splitter-*`), and rich-text
  `QTextEdit` (`richtext-*`).
- **QTableWidget** (`make-table-widget`, `table-set-dimensions!`,
  `table-set-header-labels!`, `table-set-cell-text!`, `table-cell-text`,
  row/column counts) with out-of-range cell errors.
- **Timers**: `after!`, `every!`, `stop-timer!` — Racket-thread scheduling
  that marshals widget calls to the GUI thread without owning the pump.
- **Native file dialogs**: `get-open-file-name` / `get-save-file-name`
  (modal, same contract as the `msg-*` family; `#f` on cancel).
- **Tree widget** (`make-tree-widget`, row-addressed items, children,
  selection, expansion) and **date editor** (`make-date-edit`,
  `(dateedit-date e) => '(y m d)`, calendar popup, display format).
- **Window chrome**: `window-status-bar` + `status-show-message!` /
  `status-current-message`, `window-toolbar` + `toolbar-add-action!`.
- **Desktop integration**: `clipboard-set-text!` / `clipboard-text`,
  system tray with notifications and context menus (`make-tray`,
  `tray-notify!`, `tray-set-menu!`).
- **Sentry-compatible error reporting**: `install-sentry-reporter!`
  hooks uncaught Racket exceptions into background, best-effort POSTs
  (DSN parsing, event construction, quiet failure semantics); tested
  against a local throwaway HTTP server.
- **macOS .app bundles**: `raco bezel package` wraps macOS output in a
  real bundle with Info.plist (`--bundle-id`); the signing helper signs
  bundles inside-out.
- **Silent self-update**: `auto-update!` downloads the new app archive
  (optional SHA-1 verification), then an out-of-process swapper waits for
  exit, replaces the app folder, and relaunches — CI drives the full
  v1→v2 swap on all three release targets.
- **Platform installers**: `raco bezel package --installer` produces an
  Inno Setup installer (Windows, silently installable), a dmg (macOS),
  and an AppImage (Linux) around the same app folder; `--app-version`
  stamps the VERSION file updates read back.
- **Observables**: `make-observable` / `observe!` / `set-observable!` /
  `unobserve!` — synchronous initial push, own-thread watchers whose
  widget calls marshal to the GUI thread.
- **Typed `(int,int)` signals** (cellChanged, splitterMoved, ...) through
  a new `dispatchII` sink slot.
- **Timer lifecycle**: `bezel-cleanup!` now sweeps every pending timer
  (`stop-all-timers!`); a late tick no longer raises "no application"
  after teardown.
- **Version single source**: `bezel/version.rkt` (`bezel-version`),
  validated by check-version and surfaced in `raco bezel doctor`.
- **Widget API gaps**: `widget-focus!`, `widget-visible?`,
  `widget-window-title` (readback).
- **macOS dmg drag-to-install**: the installer dmg stages the app beside
  an /Applications symlink.
- **Best-effort update checks**: `check-for-update` /
  `check-and-prompt-update!` against a static JSON version feed
  (`version`/`url`/`notes`), with padded dotted-version comparison,
  bounded timeouts, and quiet-`#f` failure semantics; the prompt variant
  opens the release page in the system browser.
- **Widget extras**: tooltips (`set-tooltip!` / `widget-tooltip`),
  geometry readers (`widget-width` / `widget-height` / `widget-x` /
  `widget-y`), `center-widget!`, and menu-action keyboard shortcuts
  (`set-action-shortcut!`, e.g. `"Ctrl+Q"`).
- **Keyword parents**: every handwritten `make-*` constructor accepts
  `#:parent` (passing both positional and keyword parents is an error).
- **Generator `orientation` argument type** for enum-setters such as
  `QSplitter::setOrientation` (C-facing int, Qt-facing cast).
- **`raco bezel package`**: builds a self-contained application folder —
  embedded executable plus `native/<os>-<arch>/` runtime — from an entry
  module.
- **Exe-relative runtime resolution**: the loader now also searches
  `<executable-dir>/native/<os>-<arch>/`, which is how `raco bezel
  package` output finds its runtime on end-user machines.
- **Signing helpers**: `scripts/sign-app-windows.ps1` (signtool sign +
  timestamp + verify) and `scripts/sign-app-macos.sh` (codesign hardened
  runtime, optional notarytool submit + staple).
- **Packaging guide**: `docs/APP_PACKAGING.md` end-to-end from source to
  signed distribution.
- **CI**: clean-runner jobs now also package the demo application with
  `raco bezel package` and execute the packaged binary headlessly on all
  release targets.

## 0.2.0 — 2026-09-21

Commercial-hardening release focused on correctness, reproducibility, and portable native distribution.

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
- Commercial release engineering checklist covering runtime support, Qt redistribution decisions, signing/notarization, and release blockers.

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
