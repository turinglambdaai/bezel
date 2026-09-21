# Bezel

Native [Qt 6](https://www.qt.io/) GUIs for [Racket](https://racket-lang.org/). Write your app in Racket, get real native widgets everywhere — the missing piece for desktop Racket.

[![CI](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml) ![Racket](https://img.shields.io/badge/Racket-9F1D20?logo=racket&logoColor=white) ![Qt6](https://img.shields.io/badge/Qt_6-41CD52?logo=qt&logoColor=white) [![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE) [![Release](https://img.shields.io/badge/release-0.1.0-C15F3C)](CHANGELOG.md)

**English** · [中文](README.zh-CN.md)

## Why Bezel?

Racket's `racket/gui` works but is hard to style into a product-grade UI, and Glaze's web approach trades native widgets for HTML. Bezel takes the third path: bind the industry-standard widget toolkit, the way mature languages do it — a C++ shim with a stable C ABI, a signal bridge, explicit lifetime rules, and a spec-driven generator.

You get:

- **Real Qt widgets** — QMainWindow, buttons, inputs, lists, sliders, menus, dialogs, plus a generator for expanding coverage
- **QSS styling** — style widgets with Qt's CSS dialect (`QPushButton { background: #C15F3C; border-radius: 8px; }`)
- **A threading story that actually works** — call public Bezel widget APIs from any Racket thread; signal handlers are plain Racket procedures
- **Agent-friendly verification** — `widget-grab-png` renders widgets to PNG bytes; the test suite runs headless on CI with `QT_QPA_PLATFORM=offscreen`
- **A checked native boundary** — the Racket package verifies the loaded shim ABI before exposing the API

### Hello Bezel

```racket
#lang racket/base
(require bezel)

(make-application #:name "Hello Bezel")

(define n (box 0))
(define count (make-label "Clicked 0 times"))
(define btn (make-button "Click me"))
(connect! btn "clicked()" (lambda _
  (set-box! n (add1 (unbox n)))
  (widget-set-text! count (format "Clicked ~a times" (unbox n)))))

(define win (make-window #:title "Hello Bezel" #:size '(320 140)))
(layout! win (vbox count btn))
(run win)
```

### How it compares

| | Bezel (Qt 6) | racket/gui | Glaze (web UI) |
|---|---|---|---|
| Toolkit | Qt 6 Widgets | wx native wrappers | HTML/CSS/JS |
| Widget richness | core set today; generator-backed expansion | basic set | unlimited (web) |
| Styling | **QSS (CSS dialect)** | limited | full CSS |
| Threading | **public API callable from any Racket thread** | eventspace-bound | any thread |
| Native toolchain needed | currently yes | none | none |
| Binary size | small with system Qt | small | small |

Current gaps are explicit: the public release does not yet ship portable prebuilt shims/Qt deployment bundles, and v0.1 covers the core widget set rather than all of Qt. Supported typed signal arguments currently include `bool`, `int`, `double`, and `QString`; unsupported signal parameter types are delivered without converted arguments.

## How it works

Four pieces, mirroring mature binding families such as Shiboken and SIP:

1. **C++ shim, C ABI** (`bezel-shim/`) — Racket's FFI speaks C and Qt speaks C++, so flat C functions wrap Qt classes behind validated opaque handles (`bezel.h` is the native contract)
2. **Cooperative marshaling** — Qt demands its GUI thread; Racket CS schedules threads cooperatively and a raw foreign wait can freeze them all. Bezel's C side never performs a blocking cross-thread handoff: the Racket layer enqueues, waits on a Racket semaphore, and the GUI pump drains it
3. **Signal bridge** — Qt signal → C++ sink object → locked queue → Racket dispatcher thread → your procedure; Qt calls made from the handler marshal back automatically
4. **Lifetime registry** — Qt parent ownership plus a registry of live `QObject` handles. Parentless objects remain alive until explicit deletion or application teardown; Bezel deliberately avoids deleting GC finalizers, and dead handles are rejected instead of dereferenced

The deep dive is in [docs/architecture.md](docs/architecture.md).

## Platform status

| Capability | macOS | Windows | Linux |
|---|---|---|---|
| Application / run loop (pump) | ✅ | ✅ | ✅ |
| Core widgets + layouts | ✅ | ✅ | ✅ |
| Menus + actions | ✅ | ✅ | ✅ |
| Signals (typed: bool / int / double / QString) | ✅ | ✅ | ✅ |
| Cross-thread widget access | ✅ | ✅ | ✅ |
| Generated-binding cross-thread marshaling | ✅ | ✅ | ✅ |
| QSS styling | ✅ | ✅ | ✅ |
| `widget-grab-png` (screenshot) | ✅ | ✅ | ✅ |
| Headless CI (offscreen e2e) | ✅ | ✅ | ✅ |

All three platforms run the same real-object end-to-end suite in CI, covering widgets, layouts, typed signal delivery, cross-thread access, the pump loop, lifecycle/error paths, and PNG rendering. CI also verifies that checked-in generated bindings reproduce exactly from their JSON specs.

## Requirements

| Dependency | Purpose |
|------------|---------|
| [Racket](https://racket-lang.org/) | 8.0 or later (includes `raco`) |
| Qt 6 + CMake + C++17 compiler | required today to build `libbezel` |

## Quick Start

### 1. Build the shim

```bash
git clone https://github.com/turinglambdaai/bezel.git
cd bezel
cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release
cmake --build bezel-shim/build
```

Point `$BEZEL_LIBRARY` at the built library if it is not on the system path. macOS needs Qt from Homebrew (`brew install qt`); Linux needs the distribution's Qt 6 development package.

### 2. Install the package

```bash
raco pkg install --auto --link ./bezel-lib ./bezel
```

### 3. Run

```bash
racket examples/hello.rkt
```

A real Qt window opens. `examples/counter.rkt` shows QSS styling; `examples/form.rkt` shows form layouts, menus, and dialogs.

> Working on Bezel itself? `raco pkg install --auto --no-docs --link ./bezel-lib ./bezel ./bezel-test`, then `raco test bezel-test/`.

## API tour

### Application lifecycle

```racket
(make-application #:name "My App")  ; idempotent; required before widgets
(run win)                           ; shows win, pumps until quit
(quit! 0)                           ; run returns 0
```

`run` is a pump loop, not a blocking exec — that's what keeps signal handlers and cross-thread calls alive. Closing the last visible window also stops the pump; `(widget-close! win)` closes programmatically, and `set-quit-on-last-window-closed!` toggles that behavior.

### Widgets and layouts

```racket
(define win (make-window #:title "Team" #:size '(420 240) #:stylesheet qss))
(define name (make-line-edit)) (set-placeholder! name "Ada Lovelace")
(define experience (make-slider)) (set-widget-range! experience 0 15)

(layout! win
         (vbox #:margins '(20 20 20 20)
               (form (list "Name:" name)
                     (list "Experience:" experience))
               (hbox stretch (make-button "Submit"))))
```

Tree form for composition (`vbox` / `hbox` / `grid` / `form` / `stretch`), imperative builders (`make-vbox`, `layout-add!`, `grid-put!`) when you need them.

### Signals

```racket
(define conn-id
  (connect! btn "clicked()" (lambda _ (displayln "clicked!"))))
(connect! slider "valueChanged(int)" (lambda (v) (displayln v)))
(connect! edit "textChanged(QString)" (lambda (s) (displayln s)))
(disconnect! btn conn-id)
```

Signals use Qt normalized signatures. Handlers run on Bezel's dispatcher thread and may freely mix Racket computation with public widget calls; those calls are marshaled back to the GUI thread automatically. Connection records and Racket closures are retired on explicit disconnect, target destruction, and application cleanup.

### Menus and dialogs

```racket
(define file (menu! (menu-bar win) "File"))
(connect! (menu-action! file "Quit") "triggered()" (lambda _ (quit!)))
(msg-question "Delete 3 items?" #:parent win)   ; #t / #f
```

### Verification (agent-friendly)

```racket
(define png (widget-grab-png win))       ; real PNG bytes, any widget
(process-events! 50)                     ; pump without blocking
(emit-test-signal! btn "clicked()")      ; drive the signal bridge in tests
```

The README's showcase image is itself generated by `scripts/showcase.rkt` — a real Qt render produced headlessly.

### Object model

```racket
(bezel-alive? widget)             ; has Qt destroyed it?
(bezel-delete! widget)            ; explicit deleteLater
(qt-object-name widget)           ; QObject name
(set-qt-object-name! widget "x")
(object-set-parent! widget parent)
```

Ownership follows Qt's parent rule: created with a parent → Qt owns it; parentless → it remains live until explicit deletion or application teardown. `layout!` hands ownership to Qt automatically. There are no GC-driven deletes — a late finalizer destroying a recycled widget address is the kind of race Bezel deliberately avoids.

## Monorepo Structure

```
bezel/
├── bezel/            # Umbrella package (install `bezel` to get everything)
├── bezel-lib/        # Racket FFI bindings (collection `bezel`)
├── bezel-shim/       # C++ shim: C ABI over Qt 6 (CMake)
├── bezel-doc/        # Documentation (Scribble)
├── bezel-test/       # Tests (headless e2e, run on all 3 OSes)
├── examples/         # hello / counter / form
├── tools/generator/  # JSON class specs → C++ + Racket bindings
└── docs/             # architecture and design notes
```

## Adding Qt classes (the generator)

Coverage scales spec-first. Write a JSON spec describing constructors and methods, then:

```bash
racket tools/generator/generate.rkt tools/generator/specs/dial.json
```

This emits both the shim side (`bezel-shim/src/generated/dial_gen.cpp`) and the Racket side (`bezel-lib/generated/dial_gen.rkt`). Generated public calls use the same liveness checks, error propagation, and cooperative GUI marshaling rules as handwritten bindings. `QDial` ships as the worked example, and CI rejects stale generated files.

## Testing

```bash
QT_QPA_PLATFORM=offscreen raco test bezel-test/
```

Real Qt objects, real signal deliveries, real PNG grabs — headless on every OS. CI (`.github/workflows/ci.yml`) builds the shim with Qt 6 on Ubuntu, Windows, and macOS, runs the same suite, verifies generated output, builds docs, and produces showcase artifacts.

## Production / distribution status

The core runtime is tested on all three desktop platforms, but the distribution story is intentionally still marked incomplete: there are currently no GitHub release artifacts containing a portable prebuilt shim and its required Qt runtime deployment. Until that pipeline exists and is verified on clean machines, Bezel should be treated as **source-build ready**, not **zero-toolchain install ready**.

## Roadmap

- [x] **Phase 1** — C++ shim + C ABI, widgets, layouts, menus, dialogs
- [x] **Phase 2** — Signal bridge with typed args, cooperative threading model, lifetime registry, generator pipeline
- [x] **Phase 3** — Headless e2e on all 3 platforms, PNG verification, showcase generation
- [x] **Phase 3.5** — ABI guard, lifecycle hardening, generated-binding safety, reproducibility CI
- [ ] **Phase 4** — Portable prebuilt shim/runtime artifacts per platform (`raco pkg install` with no compiler)
- [ ] **Phase 5** — Wider widget coverage via specs; `bezel/class` (send-style API); app packaging story

## License

Licensed under the [MIT License](LICENSE).
