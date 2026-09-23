# Bezel

Native [Qt 6](https://www.qt.io/) GUIs for [Racket](https://racket-lang.org/). Write your application in Racket and ship real Qt Widgets on Windows, macOS, and Linux.

[![CI](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml) ![Racket](https://img.shields.io/badge/Racket-9F1D20?logo=racket&logoColor=white) ![Qt6](https://img.shields.io/badge/Qt_6-41CD52?logo=qt&logoColor=white) [![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE) [![Release](https://img.shields.io/badge/release-0.3.0-C15F3C)](CHANGELOG.md)

**English** · [中文](README.zh-CN.md)

## Why Bezel?

Racket's `racket/gui` is useful but difficult to style into a modern product UI. Web-based shells give you CSS but trade away native widgets. Bezel takes a third path: a stable C ABI over Qt Widgets, with a Racket layer that handles GUI-thread marshaling, signals, lifetime rules, diagnostics, and generated bindings.

You get:

- **Real Qt widgets** — windows, buttons, inputs, lists, sliders, tables, tabs, splitters, group boxes, dials, LCD numbers, menus, dialogs, layouts, plus generator-backed expansion.
- **QSS styling** — Qt's CSS-like styling system.
- **Thread-safe public API semantics** — public widget calls can originate from any Racket thread and marshal to the GUI thread.
- **Timers** — `after!` / `every!` schedule Racket code that safely touches widgets from its own thread.
- **Agent-friendly verification** — `widget-grab-png` renders real widgets to PNG; CI runs headlessly with Qt's offscreen backend.
- **Checked native boundary** — the Racket layer validates the shim ABI before exposing the API.
- **Portable release packages** — supported release targets embed `libbezel`, Qt runtime libraries, and required Qt plugins inside the Racket package; end users do not need Qt, CMake, or a C++ compiler.
- **Final-application packaging** — `raco bezel package` turns an entry module into a self-contained executable-plus-runtime folder, with signing helpers for Windows and macOS.
- **Release diagnostics** — `raco bezel doctor` reports platform, architecture, runtime candidates, environment overrides, and ABI load status.

<p align="center"><img src="docs/showcase.png" alt="Bezel Qt showcase rendered from Racket" width="720"></p>

## Hello Bezel

```racket
#lang racket/base
(require bezel)

(make-application #:name "Hello Bezel")

(define n (box 0))
(define count (make-label "Clicked 0 times"))
(define btn (make-button "Click me"))

(connect! btn "clicked()"
          (lambda _
            (set-box! n (add1 (unbox n)))
            (widget-set-text! count
                              (format "Clicked ~a times" (unbox n)))))

(define win (make-window #:title "Hello Bezel" #:size '(320 140)))
(layout! win (vbox count btn))
(run win)
```

## Install a release package

For normal application development you only need **Racket 8.0+** on a supported release target. Download the matching `bezel-lib-<platform>.zip` from the GitHub Release and install it as package `bezel-lib`:

```text
raco pkg install --auto --name bezel-lib /path/to/bezel-lib-<platform>.zip
raco bezel doctor
```

Current prebuilt targets:

| Target | Release package | Qt/CMake/compiler needed by user? |
| --- | --- | --- |
| Linux x86_64 | `bezel-lib-linux-x86_64.zip` | No |
| Windows x86_64 | `bezel-lib-windows-x86_64.zip` | No |
| macOS Apple Silicon | `bezel-lib-macosx-aarch64.zip` | No |

Every release package is assembled from a platform runtime bundle and then tested on a **fresh runner that installs Racket only**. That runner installs the zip through `raco pkg install`, runs `raco bezel doctor`, constructs real Qt widgets, pumps the event loop, and tears the application down. CI does not set `BEZEL_NATIVE_DIR` for this test, so the package-local runtime path is exercised exactly as an end user sees it.

The Release also contains raw `bezel-native-*` runtime archives for embedding into other package/application workflows, Racket-compatible `.CHECKSUM` files for the self-contained package archives, and a `SHA256SUMS` manifest.

## Develop Bezel from source

Contributors and unsupported platforms still build the shim from source. This path requires Qt 6, CMake, and a C++17 compiler:

```bash
git clone https://github.com/turinglambdaai/bezel.git
cd bezel
cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release
cmake --build bezel-shim/build
raco pkg install --auto --no-docs --link ./bezel-lib
raco pkg install --auto --no-docs --link ./bezel-test
raco pkg install --auto --no-docs --link ./bezel
QT_QPA_PLATFORM=offscreen raco test bezel-test/
```

If a development build lives elsewhere, point `BEZEL_LIBRARY` at the shared library. For a manually extracted release runtime, point `BEZEL_NATIVE_DIR` at the runtime root.

## Architecture

Bezel deliberately keeps the native boundary small:

1. **C++ shim / stable C ABI** — Racket's FFI talks to flat C functions while Qt remains C++ behind validated opaque handles.
2. **Cooperative GUI-thread marshaling** — Qt calls are performed on the GUI thread without a blocking C-side cross-thread handoff that could freeze Racket CS scheduling.
3. **Signal bridge** — Qt signal → C++ sink → synchronized queue → Racket dispatcher → user handler. Widget calls made by handlers marshal back to the GUI thread.
4. **Lifetime registry** — Qt parent ownership plus live-handle validation. Parentless objects remain alive until explicit deletion or application teardown; Bezel intentionally avoids deleting GC finalizers.
5. **Generated bindings** — JSON specs generate both C++ and Racket code. Generated public wrappers use the same liveness checks, error propagation, and GUI marshaling rules as handwritten APIs.

See [docs/architecture.md](docs/architecture.md) for the deeper design.

## Platform status

| Capability | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Application / cooperative run loop | ✅ | ✅ | ✅ |
| Core widgets + layouts | ✅ | ✅ | ✅ |
| Menus + actions + shortcuts | ✅ | ✅ | ✅ |
| Typed signals (`bool`, `int`, `double`, `QString`) | ✅ | ✅ | ✅ |
| Cross-thread public widget access | ✅ | ✅ | ✅ |
| Generated-binding marshaling | ✅ | ✅ | ✅ |
| Generated classes (tabs/stacked/splitter/dial/…) | ✅ | ✅ | ✅ |
| Table widget + rich-text edit | ✅ | ✅ | ✅ |
| Timers (`after!` / `every!`) | ✅ | ✅ | ✅ |
| Native file dialogs | ✅ | ✅ | ✅ |
| QSS styling | ✅ | ✅ | ✅ |
| `widget-grab-png` | ✅ | ✅ | ✅ |
| Headless real-object CI | ✅ | ✅ | ✅ |
| Self-contained release package | Apple Silicon | x86_64 | x86_64 |
| `raco bezel package` app bundles | ✅ | ✅ | ✅ |

Unsupported Qt signal parameter types currently fall back to delivery without converted arguments. Bezel covers a broad, focused Widgets set today; the generator remains the expansion path rather than a claim of complete Qt coverage.

## API tour

### Application lifecycle

```racket
(make-application #:name "My App")
(run win)
(quit! 0)
```

`make-application` is idempotent and must happen before widgets are created. `run` is a cooperative pump rather than a blocking `exec`; closing the last visible window stops it by default.

### Widgets and layouts

```racket
(define win (make-window #:title "Team" #:size '(420 240) #:stylesheet qss))
(define name (make-line-edit))
(set-placeholder! name "Ada Lovelace")
(define experience (make-slider))
(set-widget-range! experience 0 15)

(layout! win
         (vbox #:margins '(20 20 20 20)
               (form (list "Name:" name)
                     (list "Experience:" experience))
               (hbox stretch (make-button "Submit"))))
```

Tree-style composition (`vbox`, `hbox`, `grid`, `form`, `stretch`) and imperative layout builders are both available. Constructors accept the parent positionally or as `#:parent`:

```racket
(define page (make-widget #:parent win))
```

### Broader widget coverage

Generator-backed classes (`tools/generator/specs/`): radio buttons, group boxes, double spin boxes, LCD numbers, tab widgets, stacked widgets, splitters, and rich-text edits:

```racket
(define tabs (tabs-new))
(tabs-add tabs (make-label "first page") "First")
(tabs-add tabs (make-label "second page") "Second")
(tabs-set-current-index tabs 1)

(define sp (splitter-new))
(splitter-add-widget sp editor)          ; 1/2 = horizontal/vertical
(splitter-set-orientation sp 2)

(define html (richtext-new "<b>Hello</b>"))
(richtext-set-html html "<i>styled</i>")
```

Plus a handwritten `QTableWidget`:

```racket
(define t (make-table-widget))
(table-set-dimensions! t 2 3)
(table-set-header-labels! t "Name\nScore\nNote")
(table-set-cell-text! t 0 0 "Ada")
(table-cell-text t 0 0)
```

### Timers

```racket
(after! 500 (lambda () (widget-set-text! status "done")))
(define clock (every! 100 (lambda () (widget-set-value! bar (tick)))))
(stop-timer! clock)
```

Handlers run on their own Racket thread; widget calls inside them marshal to the GUI thread automatically.

### Dialogs and shortcuts

```racket
(msg-question "Delete 3 items?" #:parent win)
(define path (get-open-file-name #:parent win #:filter "Images (*.png *.jpg);;All (*)"))
(define act (menu-action! (menu! (menu-bar win) "File") "Quit"))
(set-action-shortcut! act "Ctrl+Q")
```

### Update checks

Host one static JSON feed (`version` / `url` / optional `notes`) next to your releases; Bezel compares and prompts through the native dialog, opening the download page in the browser on confirmation. Best-effort by design — timeouts and unreachable feeds return `#f` instead of raising:

```racket
(after! 1000
        (lambda ()
          (check-and-prompt-update!
           #:feed "https://example.com/myapp-updates.json"
           #:current "1.2.3"
           #:parent win)))
```

`check-for-update` returns the raw `update-info` when you want your own presentation.

### Signals

```racket
(define conn-id
  (connect! btn "clicked()" (lambda _ (displayln "clicked!"))))
(connect! slider "valueChanged(int)" (lambda (v) (displayln v)))
(connect! edit "textChanged(QString)" (lambda (s) (displayln s)))
(disconnect! btn conn-id)
```

Handlers run on Bezel's dispatcher thread. Public widget calls made by handlers marshal back to the GUI thread. Explicit disconnect, target destruction, and application cleanup retire both native connection records and Racket handlers.

### Verification

```racket
(define png (widget-grab-png win))
(process-events! 50)
(emit-test-signal! btn "clicked()")
```

The repository showcase image is generated by `scripts/showcase.rkt` from a real headless Qt render.

### Object lifetime

```racket
(bezel-alive? widget)
(bezel-delete! widget)
(qt-object-name widget)
(set-qt-object-name! widget "x")
(object-set-parent! widget parent)
```

Ownership follows Qt parent rules. Bezel does not perform GC-driven deletes, avoiding late-finalizer races against recycled native addresses.

## Native runtime resolution

The loader searches in this order:

1. `BEZEL_LIBRARY` — explicit shared-library file.
2. `BEZEL_NATIVE_DIR` — explicit extracted runtime root.
3. package-local `bezel-lib/native/<os>-<arch>/` — normal self-contained release package path.
4. `<executable-dir>/native/<os>-<arch>/` — application folders produced by `raco bezel package`.
5. `bezel-shim/build` — source-checkout convenience.
6. normal operating-system library lookup.

When a bundled Qt plugin directory is present and the application has not set `QT_PLUGIN_PATH`, Bezel configures the package-local plugin path before `QApplication` is constructed.

Run `raco bezel doctor` whenever native loading fails.

## Package your application

`raco bezel package` turns an entry module into a distributable folder — embedded executable plus bundled native runtime; end users need neither Racket nor Qt:

```bash
raco bezel package --entry my-app.rkt --name MyApp --dest dist
QT_QPA_PLATFORM=offscreen ./dist/MyApp/MyApp   # headless verification
```

Ship it after signing: `scripts/sign-app-windows.ps1` (signtool + timestamp + verify) and `scripts/sign-app-macos.sh` (codesign hardened runtime, optional notarization + stapling). The full walkthrough — including CI checks that execute the packaged binary on clean runners — is in [docs/APP_PACKAGING.md](docs/APP_PACKAGING.md).

## Release engineering

A `v*` tag triggers the Release workflow. Publishing is gated on:

- consistent versions in `bezel-lib`, the umbrella package, CMake shim, changelog, and tag;
- reproducible generated bindings;
- three-platform native builds;
- portable runtime packaging;
- fresh-runner self-contained package installation and real-widget smoke tests;
- release SHA-256 generation.

See [docs/COMMERCIAL_RELEASE.md](docs/COMMERCIAL_RELEASE.md) for the complete release checklist.

## Commercial Qt note

Bezel is MIT licensed, but a prebuilt Bezel runtime redistributes Qt libraries and plugins. Shipping a commercial product therefore requires choosing and complying with an appropriate Qt license for the exact Qt version/modules being redistributed. Product-level code signing/notarization also remains the responsibility of the final application distribution. See [docs/COMMERCIAL_RELEASE.md](docs/COMMERCIAL_RELEASE.md); that document is an engineering checklist, not legal advice.

## Repository structure

```text
bezel/
├── bezel/            # umbrella package
├── bezel-lib/        # Racket collection `bezel`
├── bezel-shim/       # C++ shim / C ABI
├── bezel-doc/        # Scribble documentation
├── bezel-test/       # real-object headless tests
├── examples/         # hello / counter / form
├── scripts/          # packaging, smoke, showcase, release checks
├── tools/generator/  # JSON specs -> C++ + Racket bindings
└── docs/             # architecture and commercial release guide
```

## Roadmap

- [x] **Phase 1** — C++ shim, C ABI, widgets, layouts, menus, dialogs.
- [x] **Phase 2** — typed signal bridge, cooperative threading, lifetime registry, generator.
- [x] **Phase 3** — three-platform real-object CI, PNG verification, showcase.
- [x] **Phase 3.5** — ABI guard, lifecycle hardening, generated-binding safety, reproducibility.
- [x] **Phase 4** — relocatable native runtimes, self-contained Racket package archives, clean-machine install smoke tests, gated GitHub Releases.
- [x] **Phase 5** — broader Qt class coverage (radio/group box/double spin/LCD/tabs/stacked/splitter/rich text/table), higher-level ergonomics (`#:parent`, timers, tooltips, geometry, shortcuts, file dialogs), and final-application packaging/signing helpers (`raco bezel package` + platform signing scripts).

## License

Bezel is licensed under the [MIT License](LICENSE). Redistributed Qt components keep their own applicable license terms.
