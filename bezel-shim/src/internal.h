// internal.h — shared internals of the Bezel shim (not part of the ABI).
//
// Three load-bearing pieces live here:
//   1. resolve()/register_object() — the handle registry (QObject* <->
//      QPointer) that lets Racket hold long-lived handles safely.
//   2. on_gui() — the threading rule of the whole shim: every exported
//      function runs its Qt work through on_gui, which either executes
//      inline (caller is the GUI thread) or marshals a blocking queued
//      call onto it. This is what makes the Racket API free-threaded.
//   3. queue_signal()/next_signal() — the signal bridge. Qt signal
//      handlers (plain C++ lambdas, no Racket involvement) pack their
//      arguments and append to a locked queue; a Racket dispatcher
//      thread drains it via the public bezel_next_signal.

#pragma once

#include <bezel/bezel.h>

#include <QApplication>
#include <QMetaObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QThread>

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <type_traits>

namespace bezel {

// ---- errors ------------------------------------------------------------

// Record a formatted error for bezel_last_error(); always returns false
// so call sites can `return set_error(...)`.
#ifdef __GNUC__
bool set_error(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
#else
bool set_error(const char* fmt, ...);
#endif

// Clear the calling thread's error slot. on_gui calls this at every ABI
// entry, so an error read through bezel_last_error always belongs to the
// call that just failed (never a stale one).
void clear_error();

// Called when a widget is shown; arms quit-on-last-window-closed for the
// pump loop (see bezel_app_quit_requested).
void note_window_shown();

// ---- handle registry ---------------------------------------------------

// The live QObject behind a handle, or nullptr if dead/unknown. Accepts
// any QObject (widgets, layouts, actions, bare QObjects).
QObject* resolve(bezel_handle h);

// Resolve and require that the object is (convertible to) T; on failure
// records an error naming the expected class.
template <typename T>
T* resolve_as(bezel_handle h, const char* what) {
    QObject* obj = resolve(h);
    if (!obj) {
        set_error("%s: dead or unknown handle %p", what, h);
        return nullptr;
    }
    T* typed = qobject_cast<T*>(obj);
    if (!typed) {
        set_error("%s: handle %p is a %s, not a %s", what, h,
                  obj->metaObject()->className(), T::staticMetaObject.className());
        return nullptr;
    }
    return typed;
}

// Register a newly created object; returns the handle (the raw pointer).
// Registry entries erase themselves when the object is destroyed.
bezel_handle register_object(QObject* obj);

// ---- GUI thread marshaling --------------------------------------------

// True when the caller is the thread that runs (or will run) the Qt loop.
bool on_gui_thread();

// Run f on the calling thread. Threading policy: the C ABI never blocks
// on a cross-thread handoff — a raw foreign wait freezes Racket CS's
// cooperatively scheduled threads when they migrate OS threads. Instead,
// the exported functions execute inline and the RACKET layer (see
// bezel-lib/private/gui.rkt) marshals: it enqueues the call, waits on a
// Racket semaphore (cooperative, scheduler-friendly), and the pump loop
// on the main thread drains the queue. C-side on_gui remains as the
// single seam all exported functions go through.
template <typename F>
auto on_gui(F&& f) -> decltype(f()) {
    clear_error();
    return f();
}

// QApplication access. Returns nullptr before bezel_app_new.
class QApplication* app();
bool loop_running();

// Duplicate a QString as a UTF-8 C string (bezel_free-able) or nullptr.
char* strdup_q(const QString& s);

// ---- signal queue ------------------------------------------------------

// Append one delivered signal invocation (called on the GUI thread by
// trampolines). Copies scalars; takes ownership of variant strings.
void queue_signal(int64_t conn_id, int argc, const bezel_variant* argv);

// Block up to timeout_ms for the next queued invocation and copy it into
// *out (string ownership transfers to the caller). Returns 1 on message,
// 0 on timeout, -1 on shutdown request.
int wait_signal(int timeout_ms, bezel_signal_msg* out);

// Ask wait_signal to return -1 (used by bezel_cleanup).
void shutdown_signal_queue();

// Clear the shutdown flag and drop undelivered entries (bezel_app_new).
void reset_signal_queue();

// Registry of live connections: conn_id -> QMetaObject::Connection.
// The id must be reserved before the connection is created (the
// trampoline captures it) and stored right after.
int64_t reserve_connection_id();
void store_connection_with_id(int64_t conn_id, QMetaObject::Connection conn,
                              QObject* target, class SignalSink* sink, const QByteArray& sig);
bool drop_connection(int64_t conn_id);

}  // namespace bezel
