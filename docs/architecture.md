# Architecture

How Bezel binds Qt 6 to Racket, and why each piece looks the way it does.
This is the document to read before touching `bezel-shim/` or
`bezel-lib/private/`.

## The problem space

Three hard constraints collide:

1. **Qt speaks C++, Racket's FFI speaks C.** A binding needs a C ABI in
   between.
2. **Qt owns a thread.** Widgets must be created, mutated, and destroyed
   on the GUI thread (the one that runs the event loop). On macOS that
   must be the process's main thread.
3. **Racket CS schedules threads cooperatively.** Racket threads can
   migrate between OS threads, and a raw blocking call into foreign code
   (a semaphore wait, a condition-variable wait) stalls the runtime's
   scheduler — every other Racket thread freezes at its next safe point.
   This is not theoretical: Bezel's first prototype deadlocked exactly
   this way.

Every design decision below traces back to one of these.

## Layer cake

```
┌──────────────────────────────────────────────────────────┐
│ your app (racket)         (require bezel)                │
├──────────────────────────────────────────────────────────┤
│ safe layer  bezel-lib/bezel/*.rkt                        │
│   make-window, widget-set-text!, connect!, run, ...      │
│   error checks · ownership flips · string conversion     │
├──────────────────────────────────────────────────────────┤
│ marshal + raw  bezel-lib/private/{marshal,raw}.rkt       │
│   every raw call routed through `gui` (coop. marshaling) │
│   kebab→snake symbol mapping, ctypes, structs            │
├──────────────────────────────────────────────────────────┤
│ dispatcher thread  bezel-lib/private/dispatch.rkt        │
│   polls bezel_next_signal, applies your handlers         │
├──────────────────────────────────────────────────────────┤
│ C++ shim (libbezel, C ABI)  bezel-shim/src/*.cpp         │
│   flat functions over opaque handles · signal queue ·    │
│   handle registry · PNG grab                             │
├──────────────────────────────────────────────────────────┤
│ Qt 6 Widgets                                             │
└──────────────────────────────────────────────────────────┘
```

## Threading: the core invariant

**The C ABI never blocks on a cross-thread handoff.**

Every exported shim function executes inline on its calling thread.
Marshaling happens in Racket (`private/marshal.rkt`):

```
caller thread (≠ GUI)                     main thread (pump)
─────────────────────                     ────────────────────
(gui thunk)
  bezel_on_gui_thread() → 0
  enqueue (thunk, sem, box)
  sync/timeout on sem ──┐                 run loop:
                        │                   bezel_process_events(30)
  ...cooperative...     │                   drain-gui!  ← runs thunk
                        │                     on the GUI thread,
  semaphore posted ◄────┼─────────────────────posts result
  read result box       │
  return value          │
```

- The wait is a **Racket semaphore** — the scheduler keeps running, the
  pump keeps pumping, nothing freezes.
- The queued thunk runs on the main OS thread, which *is* the GUI thread,
  so Qt is happy.
- Handlers (dispatcher thread) get the same treatment for free: a
  `widget-set-text!` inside a handler enqueues and waits exactly the same
  way.

The pump alternates `processEvents` (bounded foreign call) with a Racket
`sleep` yield. A blocking `QApplication::exec` cannot be used: it would
pin the main thread in foreign code forever, and every other Racket
thread — the dispatcher included — would starve. (Verified the hard way;
see "deadlocks we hit" below.)

## Signals: a bridge, not a callback

Racket CS callbacks are atomic, and the Qt loop thread is foreign to the
runtime — so Qt must never call Racket. Instead:

```
Qt emits "valueChanged(42)"  (GUI thread)
  → SignalSink::dispatchI(42)          (a tiny QObject per connection)
  → queue_signal: lock, copy args, unlock          (pure C++)
  → ...later, on the dispatcher thread...
  bezel_next_signal(0, &msg) → copies out, takes ownership of strings
  → variant→value conversion
  → (apply your-handler '(42))                     (full Racket, no limits)
```

Connection plumbing:

- `bezel-connect(target, "valueChanged(int)")` verifies the signal exists
  on the target's class, picks a typed sink slot
  (`dispatch0/B/I/S`) by the signal's first parameter type, and connects
  **QMetaMethod → QMetaMethod** (Qt 6 has no string-signal→functor
  overload).
- Signals whose first argument is not (yet) convertible fall back to
  `dispatch0` — Qt drops extra parameters, so every signal is connectable;
  typed ones deliver their argument.
- The test hook `bezel-signal-emit` delivers straight to the sinks —
  deterministic, and CI exercises the production path headlessly.

## Ownership and handles

- A `bezel-object` (Racket) = raw `QObject*` + kind tag + owned flag.
- **Lifetime**: objects live until application teardown
  (`bezel-cleanup!`, or `run` returning) destroys the whole
  QApplication, until their parent chain destroys them, or until an
  explicit `bezel-delete!`. There are deliberately **no deleting
  finalizers**: a finalizer firing late can hit a heap address Qt
  already freed and reused, destroying an innocent widget (observed on
  Windows). Widget memory is bounded by the app's own widget count.
- The shim keeps a handle→`QPointer` registry; destroyed objects erase
  their entry, so stale handles fail `bezel-alive?` instead of aliasing
  into a new object at the same address.
- Structs in `bezel.h` are ordered naturally-aligned-fields-first with
  the `int8` tag **last**: Racket's `define-cstruct` packs without
  padding, so this is the only layout both sides agree on byte-for-byte.

## The ABI surface

`bezel-shim/include/bezel/bezel.h` is the entire contract (~90 functions,
documented). Conventions:

| Concern | Rule |
|---|---|
| strings in | UTF-8 `const char*`, read before the call returns |
| strings out | heap buffer, caller frees with `bezel_free` (Racket copies first) |
| errors | thread-local `bezel_last_error`; Racket raises `exn:fail:bezel` |
| status | `int` 1/0 or value-with-sentinel (`-1`), documented per function |
| symbols | C snake_case; Racket kebab-case mapped by `define-bezel` |

## The generator

The handwritten core optimizes for ergonomics; coverage scales by spec —
the Shiboken/SIP/Qtah model. `tools/generator/specs/*.json` describe a
class (constructors, methods, arg types) and one command emits **both**
sides:

- `bezel-shim/src/generated/<module>_gen.cpp` — `extern "C"` functions
  through the same `resolve_as`/`on_gui` seams as the handwritten core
- `bezel-lib/generated/<module>_gen.rkt` — raw bindings + safe wrappers

Rebuild, and the class is bound end to end. `QDial` is the checked-in
worked example (with an e2e test).

## Deadlocks we hit (so you don't have to)

1. **Blocking foreign call in a helper thread** (the first dispatcher
   design: `condition_variable::wait_for` in a poll loop) froze every
   other Racket thread mid-`sleep`. Fixed by moving all waiting to
   Racket (`sync/timeout` on semaphores) with a non-blocking C poll.
2. **`QApplication::exec` from the main thread** starved the dispatcher
   identically — the runtime never regained control. Fixed by replacing
   exec with the pump loop (`processEvents(30)` + `sleep` + drain).
3. **`on_gui` BlockingQueuedConnection marshaling** deadlocked whenever
   the calling Racket thread happened to be waiting on a raw semaphore —
   same root cause as (1). Fixed by the cooperative marshal queue.

The rule they all reduce to: *the C side never waits; Racket waits only
on Racket primitives.*

## Testing strategy

`QT_QPA_PLATFORM=offscreen` gives a real Qt with no display. The suite
(builds a real window, emits real signals, grabs real PNGs) runs on all
three CI operating systems. `emit-test-signal!` drives the production
signal path deterministically; `widget-grab-png` doubles as the
agent-friendly verification API and generates this README's showcase
image.

Suites that need no shim at all (`bezel/sentry`, `bezel/observable`,
`bezel/timers`, `bezel/updates`' pure helpers) run on any host — the
same headless-first principle pushed one layer further: as much logic
as possible lives in plain Racket where it can be tested without Qt.

## The application layer (since 0.3.0)

Everything a shipping application needs beyond widgets deliberately
lives in **pure Racket**, not the shim. The rule: if it doesn't have to
touch a QObject, it must not require libbezel.

- **Timers** (`timers.rkt`): worker threads + a cancellable flag; a
  registry lets `bezel-cleanup!` sweep pending timers so a late tick
  never surfaces "no application" after teardown.
- **Observables** (`observable.rkt`): watchers fire on their own thread
  (widget calls inside marshal to the GUI thread, exactly like timer
  handlers). The initial push from `observe!` is *synchronous* — an
  async push races the next `set-observable!` and can deliver the old
  value last, flipping the UI backwards.
- **Sentry reporting** (`sentry.rkt`): hooks `error-display-handler`,
  posts on a background thread, fails quiet. Native crashes inside
  Qt/libbezel bypass the Racket runtime and are out of scope by design.
- **Updates** (`updates.rkt`): feed check, best-effort download with
  optional SHA-1, then `auto-update!` hands off to an **out-of-process
  swapper**. Replacing a running binary in place is platform-hostile
  (Windows locks the running exe; macOS keeps the bundle mapped), so a
  tiny script waits for exit, swaps the directory, and relaunches.
  Two hard-won details: the swapper must be spawned fire-and-forget
  (`sh -c '... &'` / `Start-Process`) or the Racket runtime waits on
  the child before it can exit; and its parameters travel through the
  environment, because one quote-escaping bug in a nested
  `Start-Process` argument list hangs the whole chain.
- **Packaging** (`private/pack.rkt`): wraps `raco exe` +
  `raco distribute` with the layouts each platform expects (embedded
  DLLs on Windows, `.app` on macOS, `bin/+lib/` on Linux) and always
  places the native runtime beside the *actual* executable — the
  loader's exe-relative search step makes the folder self-contained
  with zero configuration.

The same rule explains the loader order in `private/lib.rkt`: env
overrides → package-local runtime → `<exe-dir>/native/<os>-<arch>/`
(the packaging output) → source-checkout build tree → system lookup.
