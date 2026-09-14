# Changelog

All notable changes to Bezel are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 0.1.0 — 2025-09-15

First release: Qt 6 Widgets bound to Racket, end to end.

### Added

- **C++ shim** (`bezel-shim/`): stable C ABI over Qt 6 — application
  lifecycle, 12 widget constructors, shared widget API (text, checked,
  int value, enable, geometry, stylesheet), 4 layouts with tree and
  imperative forms, menus/actions, standard dialogs, PNG widget capture
  (`bezel_widget_grab_png`).
- **Racket bindings** (`bezel-lib/`): collection `bezel` with
  `make-application` / `run` (cooperative pump loop) / `quit!`;
  `make-*` constructors with keyword options; `connect!` /
  `disconnect!` / `emit-test-signal!`; ownership model with
  finalizers (`bezel-alive?`, `bezel-delete!`); `exn:fail:bezel` error
  surface with shim messages attached.
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
