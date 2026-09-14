# Bezel

Native [Qt 6](https://www.qt.io/) GUIs for [Racket](https://racket-lang.org/). Write your app in Racket, get real native widgets everywhere — the missing piece for desktop Racket.

[![CI](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml) ![Racket](https://img.shields.io/badge/Racket-9F1D20?logo=racket&logoColor=white) ![Qt6](https://img.shields.io/badge/Qt_6-41CD52?logo=qt&logoColor=white) [![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE) [![Release](https://img.shields.io/badge/release-0.1.0-C15F3C)](CHANGELOG.md)

**English** · [中文](README.zh-CN.md)

## Why Bezel?

Racket's `racket/gui` works but is hard to style into a product-grade UI, and Glaze's web approach trades native widgets for HTML. Bezel takes the third path: bind the industry-standard widget toolkit, the way mature languages do it — a C++ shim with a stable C ABI, a signal bridge, ownership tracking, and a spec-driven generator (the PySide/Shiboken and PyQt/SIP architecture, brought to Racket).

You get:

- **Real native widgets** — QMainWindow, buttons, inputs, lists, sliders, menus, dialogs; native look on all three platforms
- **QSS styling** — style anything with Qt's CSS dialect (`QPushButton { background: #C15F3C; border-radius: 8px; }`)
- **A threading story that actually works** — call any widget from any Racket thread; signal handlers are plain Racket procedures
- **Agent-friendly verification** — `widget-grab-png` renders any widget to PNG bytes; the whole test suite runs headless on CI with `QT_QPA_PLATFORM=offscreen`

### Hello Bezel

```racket
#lang racket/base
(require bezel)

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
| Widget richness | full Qt set | basic set | unlimited (web) |
| Styling | **QSS (CSS dialect)** | limited | full CSS |
| Threading | **any Racket thread** | eventspace-bound | any thread |
| Native toolchain needed | C++ compiler + Qt 6 (or prebuilt shim) | none | none |
| Binary size | small (system Qt) | small | small |

Honest gaps: the shim needs a one-time native build (prebuilt binaries are on the roadmap); the typed-signal table covers `bool`/`int`/`QString` first arguments — other signal types deliver without arguments; and v0.1 covers the core widget set, not all of Qt.

## How it works

Four pieces, mirroring the mature binding families (Shiboken, SIP, Qtah):

1. **C++ shim, C ABI** (`bezel-shim/`) — Racket's FFI speaks C and Qt speaks C++, so ~90 flat C functions wrap the Qt classes behind opaque handles (`bezel.h` is the whole contract)
2. **Cooperative marshaling** — Qt demands its GUI thread; Racket CS schedules threads cooperatively and a raw foreign wait can freeze them all. Bezel's C side never blocks on a cross-thread handoff: the Racket layer enqueues, waits on a Racket semaphore, and the pump drains it
3. **Signal bridge** — Qt signal → C++ sink object → locked queue → Racket dispatcher thread → your procedure; Qt calls in the handler marshal back automatically
4. **Ownership registry** — Qt's parent rule with Racket finalizers for parentless objects; dead handles are detectable (`bezel-alive?`), never crash

The deep dive is in [docs/architecture.md](docs/architecture.md).

## Platform status

| Capability | macOS | Windows | Linux |
|---|---|---|---|
| Application / run loop (pump) | ✅ | ✅ | ✅ |
| Core widgets (13) + layouts (4) | ✅ | ✅ | ✅ |
| Menus + actions | ✅ | ✅ | ✅ |
| Signals (typed: bool / int / QString) | ✅ | ✅ | ✅ |
| Cross-thread widget access | ✅ | ✅ | ✅ |
| QSS styling | ✅ | ✅ | ✅ |
| `widget-grab-png` (screenshot) | ✅ | ✅ | ✅ |
| Headless CI (offscreen e2e) | ✅ | ✅ | ✅ |

All three platforms run the same real-object e2e suite in CI — 23 tests covering widgets, layouts, typed signal delivery, the pump loop, and PNG rendering.

## Requirements

| Dependency | Purpose |
|------------|---------|
| [Racket](https://racket-lang.org/) | 8.0 or later (includes `raco`) |
| Qt 6 + CMake + C++17 compiler | to build `libbezel` (one command; prebuilt binaries are on the roadmap) |

## Quick Start

### 1. Build the shim

```bash
git clone https://github.com/turinglambdaai/bezel.git
cd bezel
cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release
cmake --build bezel-shim/build
```

Point `$BEZEL_LIBRARY` at the built library if it is not on the system path. macOS needs Qt from Homebrew (`brew install qt`), Linux the distro's `qt6-base-dev`.

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

`run` is a pump loop, not a blocking exec — that's what keeps signal
handlers and cross-thread calls alive (see the architecture doc).
Closing the last visible window also stops the pump (the pump-loop
equivalent of Qt's quit-on-last-window-closed); `(widget-close! win)`
closes programmatically, and `set-quit-on-last-window-closed!` toggles
the behavior.

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
(connect! btn "clicked()" (lambda _ (displayln "clicked!")))
(connect! slider "valueChanged(int)" (lambda (v) (displayln v)))
(connect! edit "textChanged(QString)" (lambda (s) (displayln s)))
(disconnect! btn conn-id)
```

Signals use Qt normalized signatures. Handlers run on Bezel's dispatcher thread and may freely mix Racket computation with widget calls (marshaled back to the GUI thread automatically).

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
(emit-test-signal! btn "clicked()")      ; drive the full signal bridge in tests
```

The README's showcase image is itself generated by `scripts/showcase.rkt` — a real Qt render produced headlessly.

### Object model

```racket
(bezel-alive? widget)          ; has Qt destroyed it?
(bezel-delete! widget)         ; explicit deleteLater
(object-name widget)           ; names, reparenting, GC-safe handles
```

Ownership follows Qt's parent rule: created with a parent → Qt owns it; parentless → a Racket finalizer cleans up. `layout!` hands ownership to Qt automatically.

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
└── docs/             # architecture.md deep dive
```

## Adding Qt classes (the generator)

Coverage scales the way Shiboken/SIP scale it — spec-driven. Write a JSON spec describing constructors and methods, then:

```bash
racket tools/generator/generate.rkt tools/generator/specs/dial.json
```

emits both the shim side (`src/generated/dial_gen.cpp`) and the Racket side (`bezel-lib/generated/dial_gen.rkt`) — rebuild, and the new class is bound end to end. `QDial` ships as the worked example.

## Testing

```bash
QT_QPA_PLATFORM=offscreen raco test bezel-test/
```

Real Qt objects, real signal deliveries, real PNG grabs — headless on every OS. CI (`.github/workflows/ci.yml`) builds the shim with Qt 6 on ubuntu/windows/macos and runs the same suite, then regenerates the showcase screenshot as an artifact.

## Roadmap

- [x] **Phase 1** — C++ shim + C ABI, widgets, layouts, menus, dialogs
- [x] **Phase 2** — Signal bridge with typed args, cooperative threading model, ownership registry, generator pipeline
- [x] **Phase 3** — Headless e2e on all 3 platforms, PNG verification, showcase generation
- [ ] **Phase 4** — Prebuilt shim binaries per platform (`raco pkg install` with no toolchain)
- [ ] **Phase 5** — Wider widget coverage via specs; `bezel/class` (send-style API); packaging story for shipping apps

## License

Licensed under the [MIT License](LICENSE).
