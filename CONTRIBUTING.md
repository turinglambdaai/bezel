# Contributing to Bezel

## Development Setup

```bash
git clone https://github.com/turinglambdaai/bezel.git
cd bezel

# 1. Qt 6 + CMake
brew install qt cmake            # macOS
sudo apt install qt6-base-dev cmake   # Debian/Ubuntu

# 2. Build the shim
cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release
cmake --build bezel-shim/build -j

# 3. Link the Racket packages
raco pkg install --auto --no-docs --link ./bezel-lib ./bezel ./bezel-test
```

## Running Tests

```bash
QT_QPA_PLATFORM=offscreen raco test bezel-test/
```

The suite is fully headless (offscreen platform plugin): real Qt objects,
real signal deliveries, real PNG grabs. CI runs the same suite on
ubuntu, windows, and macos.

## Code Style

- **Racket**: `raco fmt` (if installed), standard Racket conventions;
  public API follows the `make-widget` / `widget-set-text!` convention.
- **C++**: C++17, match the surrounding style in `bezel-shim/src/`;
  every exported function is documented in `include/bezel/bezel.h` and
  routes Qt work through `on_gui`.
- New user-facing behavior needs a test in `bezel-test/`.

## Adding Qt classes

Two paths:

1. **Handwritten** (for classes that need tuned ergonomics): C ABI in
   `bezel.h`, implementation in `bezel-shim/src/`, raw binding in
   `private/raw.rkt`, safe wrapper in the matching `bezel/*.rkt`.
2. **Generated** (for coverage): add a JSON spec under
   `tools/generator/specs/`, run the generator, rebuild. See
   `specs/dial.json` and the README section.

## Pull Requests

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run the test suite (all-green on your platform)
5. Submit a PR with a clear description

## Version bumps and releases

The version lives in **five places**, and `scripts/check-version.rkt`
fails CI on any disagreement:

- `bezel-lib/info.rkt`, `bezel/info.rkt`, `bezel-lib/version.rkt`
- `bezel-shim/CMakeLists.txt` (`project(bezel-shim VERSION ...)`)
- `CHANGELOG.md` (topmost `## x.y.z` heading)

To release: bump all five, update the README release badge, merge, then
push a `vX.Y.Z` tag — the Release workflow builds, clean-smoke-tests,
checksums, and publishes the runtime packages. The complete checklist is
[docs/COMMERCIAL_RELEASE.md](docs/COMMERCIAL_RELEASE.md).

## Testing beyond the unit suite

Several suites run **without the Qt shim** on any machine
(`bezel-test/bezel-test/{timers,observable,sentry}.rkt`). The
packaging and silent self-update flows are exercised end to end by CI
against real built applications; `scripts/app-smoke.rkt` is the entry
point those jobs drive, and `scripts/make-feed.rkt` builds a local
update feed for reproducing the self-update loop manually.

## Package Structure

| Package | Purpose |
|---------|---------|
| `bezel` | Metapackage |
| `bezel-lib` | Core Racket bindings |
| `bezel-shim` | C++ shim (not a Racket package — CMake project) |
| `bezel-doc` | Scribble documentation |
| `bezel-test` | Tests |

## Before touching `private/` or `bezel-shim/`

Read [docs/architecture.md](docs/architecture.md) — especially the
threading invariant (the C side never blocks on a cross-thread handoff)
and the ownership rules. Most Bezel bugs historically trace back to a
violation of one of those two.
