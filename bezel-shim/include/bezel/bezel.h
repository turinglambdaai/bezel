/*
 * bezel.h — stable C ABI of the Bezel shim (libbezel).
 *
 * Bezel binds Qt 6 (Widgets) to Racket. Racket's FFI speaks C, Qt speaks
 * C++, so the shim exposes a flat C API over opaque `bezel_handle`s.
 * Racket callbacks are never invoked directly from Qt: signals are queued
 * by the shim and drained by a Racket dispatcher via `bezel_next_signal`.
 *
 * Conventions
 * -----------
 *  - Handles: `bezel_handle` is an opaque QObject*. A handle stays valid
 *    until the underlying object is destroyed (parent chain, explicit
 *    `bezel_object_delete`, or application teardown). Every Qt-facing
 *    entry point validates the handle and records an error on
 *    `bezel_last_error`.
 *  - Ownership: a widget created with a non-null parent is owned by Qt
 *    (parent deletes children). Parentless objects remain alive until
 *    explicit deletion or application teardown. The Racket binding does
 *    not use deleting GC finalizers because a late finalizer can target a
 *    recycled QObject address.
 *  - Strings: all `const char*` parameters are UTF-8, read synchronously
 *    before the call returns. Returned `const char*` values are heap
 *    buffers the caller must release with `bezel_free` (Racket copies
 *    first, then frees).
 *  - Threading: Qt-touching ABI calls are GUI-thread-affine. The public
 *    Racket API is free-threaded because its cooperative marshal layer
 *    enqueues calls onto the GUI pump before entering this ABI. The shim
 *    intentionally does not perform blocking cross-thread handoffs.
 *  - Error status: functions return int (1 = ok, 0 = failed) or a value;
 *    0/-1 with a message on `bezel_last_error` means failure.
 */

#ifndef BEZEL_H
#define BEZEL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  define BEZEL_EXPORT __declspec(dllexport)
#else
#  define BEZEL_EXPORT __attribute__((visibility("default")))
#endif

typedef void* bezel_handle;

/* ------------------------------------------------------------------ */
/* Library / memory                                                    */
/* ------------------------------------------------------------------ */

/* ABI version of this shim; bump when an incompatible C contract change
 * requires bindings and shim to be upgraded together. */
BEZEL_EXPORT int bezel_version(void);

/* Free a buffer returned by this library (strings, PNG bytes, ...). */
BEZEL_EXPORT void bezel_free(void* p);

/* Last error message on this thread, or NULL. Borrowed — do not free. */
BEZEL_EXPORT const char* bezel_last_error(void);

/* Set this thread's error slot. The Racket marshal layer replays the
 * GUI thread's error onto the calling thread, because thread-local
 * errors never cross the marshal boundary on their own. */
BEZEL_EXPORT void bezel_set_last_error(const char* msg);

/* ------------------------------------------------------------------ */
/* Application lifecycle                                               */
/* ------------------------------------------------------------------ */

/* Create the QApplication instance. Must be called before any widget
 * function. `name` may be NULL. Returns 1 on success. */
BEZEL_EXPORT int bezel_app_new(const char* name);

/* Run Qt's blocking event loop. The Racket binding normally uses its
 * cooperative pump instead so Racket threads continue to run. */
BEZEL_EXPORT int bezel_app_exec(void);

/* Ask the event loop/pump to stop with `code`. */
BEZEL_EXPORT int bezel_app_quit(int code);

/* 1 after bezel_app_quit, or after the pump observes the configured
 * quit-on-last-window-closed condition; 0 otherwise. */
BEZEL_EXPORT int bezel_app_quit_requested(void);

/* 1 when the calling OS thread is the thread recorded at app creation. */
BEZEL_EXPORT int bezel_on_gui_thread(void);

/* Default on. When enabled, the Racket pump stops after at least one
 * top-level window has been visible and no top-level window remains
 * visible. */
BEZEL_EXPORT int bezel_app_set_quit_on_last_window_closed(int enabled);

/* Pump the event loop for up to `ms` milliseconds. Returns 1 on success. */
BEZEL_EXPORT int bezel_process_events(int ms);

/* ------------------------------------------------------------------ */
/* Objects (QObject core)                                              */
/* ------------------------------------------------------------------ */

/* Create a bare QObject. */
BEZEL_EXPORT bezel_handle bezel_object_new(void);

/* deleteLater() the object. Safe during signal dispatch; the handle is
 * retired when Qt processes the deferred delete. */
BEZEL_EXPORT int bezel_object_delete(bezel_handle h);

/* 1 if the underlying object has not been destroyed. */
BEZEL_EXPORT int bezel_object_alive(bezel_handle h);

BEZEL_EXPORT const char* bezel_object_name(bezel_handle h);
BEZEL_EXPORT int bezel_object_set_name(bezel_handle h, const char* name);

/* Reparent (Qt semantics: passing a parent transfers ownership). */
BEZEL_EXPORT int bezel_object_set_parent(bezel_handle h, bezel_handle parent);

/* ------------------------------------------------------------------ */
/* Widgets — constructors                                              */
/* ------------------------------------------------------------------ */

/* Every constructor takes an optional parent widget (NULL for none).
 * With a parent, Qt owns the object; without, it lives until explicit
 * deletion or application teardown. */

BEZEL_EXPORT bezel_handle bezel_window_new(void);          /* QMainWindow */
BEZEL_EXPORT bezel_handle bezel_widget_new(bezel_handle parent);

BEZEL_EXPORT bezel_handle bezel_label_new(const char* text, bezel_handle parent);
BEZEL_EXPORT bezel_handle bezel_button_new(const char* text, bezel_handle parent);
BEZEL_EXPORT bezel_handle bezel_checkbox_new(const char* text, bezel_handle parent);
BEZEL_EXPORT bezel_handle bezel_lineedit_new(const char* text, bezel_handle parent);
BEZEL_EXPORT bezel_handle bezel_textedit_new(bezel_handle parent);   /* QPlainTextEdit */
BEZEL_EXPORT bezel_handle bezel_combo_new(bezel_handle parent);      /* QComboBox */
BEZEL_EXPORT bezel_handle bezel_spinbox_new(bezel_handle parent);
BEZEL_EXPORT bezel_handle bezel_slider_new(int vertical, bezel_handle parent);
BEZEL_EXPORT bezel_handle bezel_progress_new(bezel_handle parent);
BEZEL_EXPORT bezel_handle bezel_list_new(bezel_handle parent);       /* QListWidget */

/* ------------------------------------------------------------------ */
/* Widgets — QWidget shared API                                        */
/* ------------------------------------------------------------------ */

BEZEL_EXPORT int bezel_widget_show(bezel_handle h);
BEZEL_EXPORT int bezel_widget_hide(bezel_handle h);
BEZEL_EXPORT int bezel_widget_close(bezel_handle h);
BEZEL_EXPORT int bezel_widget_set_enabled(bezel_handle h, int enabled);
BEZEL_EXPORT int bezel_widget_is_enabled(bezel_handle h);
BEZEL_EXPORT int bezel_widget_resize(bezel_handle h, int w, int hgt);
BEZEL_EXPORT int bezel_widget_move(bezel_handle h, int x, int y);
BEZEL_EXPORT int bezel_window_set_title(bezel_handle h, const char* title);
BEZEL_EXPORT int bezel_widget_set_stylesheet(bezel_handle h, const char* qss);

/* Render the widget into a PNG buffer. Sets *len_out and returns bytes
 * owned by the caller; release them with bezel_free. Returns NULL on
 * failure. */
BEZEL_EXPORT const unsigned char* bezel_widget_grab_png(bezel_handle h, int* len_out);

/* ------------------------------------------------------------------ */
/* Widgets — value API (text / checked / int value)                    */
/* ------------------------------------------------------------------ */

/* Text-bearing widgets: label, button, checkbox, line edit,
 * text edit, combo (current), list (current row's text). */
BEZEL_EXPORT int bezel_widget_set_text(bezel_handle h, const char* text);
BEZEL_EXPORT const char* bezel_widget_text(bezel_handle h);

/* Checkable widgets: checkbox. */
BEZEL_EXPORT int bezel_widget_set_checked(bezel_handle h, int checked);
BEZEL_EXPORT int bezel_widget_is_checked(bezel_handle h);

/* Integer-valued widgets: slider, spinbox, progress bar. */
BEZEL_EXPORT int bezel_widget_set_value(bezel_handle h, int value);
BEZEL_EXPORT int bezel_widget_value(bezel_handle h);
BEZEL_EXPORT int bezel_widget_set_range(bezel_handle h, int min, int max);

/* Combo box / list widget items. */
BEZEL_EXPORT int bezel_combo_add(bezel_handle h, const char* item);
BEZEL_EXPORT int bezel_combo_current_index(bezel_handle h);
BEZEL_EXPORT int bezel_combo_set_index(bezel_handle h, int index);
BEZEL_EXPORT const char* bezel_combo_current_text(bezel_handle h);
BEZEL_EXPORT int bezel_list_add(bezel_handle h, const char* item);
BEZEL_EXPORT int bezel_list_current_row(bezel_handle h);
BEZEL_EXPORT int bezel_list_set_current_row(bezel_handle h, int row);
BEZEL_EXPORT const char* bezel_list_current_text(bezel_handle h);

/* Line edit / text edit placeholder + read-only flag. */
BEZEL_EXPORT int bezel_widget_set_placeholder(bezel_handle h, const char* text);
BEZEL_EXPORT int bezel_widget_set_readonly(bezel_handle h, int readonly);

/* ------------------------------------------------------------------ */
/* Layouts                                                             */
/* ------------------------------------------------------------------ */

BEZEL_EXPORT bezel_handle bezel_vbox_new(void);   /* QVBoxLayout */
BEZEL_EXPORT bezel_handle bezel_hbox_new(void);   /* QHBoxLayout */
BEZEL_EXPORT bezel_handle bezel_grid_new(void);   /* QGridLayout */
BEZEL_EXPORT bezel_handle bezel_form_new(void);   /* QFormLayout */

/* Attach a layout to a widget (widget becomes the layout's parent). */
BEZEL_EXPORT int bezel_widget_set_layout(bezel_handle w, bezel_handle layout);

/* QMainWindow special case: wrap the layout in a central widget and
 * install it with setCentralWidget. */
BEZEL_EXPORT int bezel_window_central_layout(bezel_handle window, bezel_handle layout);

BEZEL_EXPORT int bezel_layout_add_widget(bezel_handle layout, bezel_handle w, int stretch);
BEZEL_EXPORT int bezel_layout_add_layout(bezel_handle parent, bezel_handle child, int stretch);
BEZEL_EXPORT int bezel_layout_add_stretch(bezel_handle layout, int stretch);
BEZEL_EXPORT int bezel_layout_set_spacing(bezel_handle layout, int spacing);
BEZEL_EXPORT int bezel_layout_set_margins(bezel_handle layout, int l, int t, int r, int b);

BEZEL_EXPORT int bezel_grid_add(bezel_handle layout, bezel_handle w,
                                int row, int col, int row_span, int col_span);
BEZEL_EXPORT int bezel_form_add_row(bezel_handle layout, const char* label, bezel_handle w);

/* ------------------------------------------------------------------ */
/* Menus                                                               */
/* ------------------------------------------------------------------ */

BEZEL_EXPORT bezel_handle bezel_menubar(bezel_handle window);
BEZEL_EXPORT bezel_handle bezel_menu_add(bezel_handle parent, const char* title);
BEZEL_EXPORT bezel_handle bezel_menu_action(bezel_handle menu, const char* text);
BEZEL_EXPORT bezel_handle bezel_menu_separator(bezel_handle menu);

/* ------------------------------------------------------------------ */
/* Dialogs — modal conveniences                                        */
/* ------------------------------------------------------------------ */

BEZEL_EXPORT int bezel_msg_information(bezel_handle parent, const char* title, const char* text);
BEZEL_EXPORT int bezel_msg_warning(bezel_handle parent, const char* title, const char* text);
BEZEL_EXPORT int bezel_msg_question(bezel_handle parent, const char* title, const char* text);

/* ------------------------------------------------------------------ */
/* Signals                                                             */
/* ------------------------------------------------------------------ */

/*
 * Racket never passes function pointers across this ABI. Instead:
 *   - `bezel_connect` registers a connection id for a normalized Qt
 *     signal signature such as "clicked()" or "valueChanged(int)".
 *   - When the signal fires, the shim serializes its supported arguments
 *     into an internal queue.
 *   - A Racket dispatcher drains that queue with `bezel_next_signal` and
 *     applies the user procedure outside Qt.
 *   - When a target QObject dies, the queue emits an internal lifecycle
 *     message with a negative conn_id. `-conn_id` is the retired positive
 *     connection id and argc is zero; ordinary user deliveries always
 *     carry positive ids.
 *
 * `bezel_signal_emit` is a test hook used by headless end-to-end tests.
 */

/* Field order note: Racket's define-cstruct layout must match this C
 * struct exactly; keep the int8 tag last unless both sides are changed. */
typedef struct bezel_variant {
    int64_t i;         /* VT_INT / VT_BOOL */
    double d;          /* VT_DOUBLE */
    void* p;           /* VT_OBJECT (bezel_handle) */
    const char* s;     /* VT_STRING (heap buffer; see lifetime rules) */
    int8_t tag;        /* BEZEL_VT_* below */
} bezel_variant;

enum {
    BEZEL_VT_NIL    = 0,
    BEZEL_VT_INT    = 1,
    BEZEL_VT_DOUBLE = 2,
    BEZEL_VT_BOOL   = 3,
    BEZEL_VT_STRING = 4,
    BEZEL_VT_OBJECT = 5
};

#define BEZEL_MAX_SIGNAL_ARGS 6

typedef struct bezel_signal_msg {
    int64_t conn_id;
    bezel_variant argv[BEZEL_MAX_SIGNAL_ARGS];
    int argc;
} bezel_signal_msg;

/* String argument lifetimes:
 *  - `bezel_next_signal` transfers ownership of VT_STRING buffers to the
 *    caller, which must release each `s` with bezel_free after copying.
 *  - `bezel_signal_emit` copies caller strings synchronously; ownership
 *    remains with the caller. */

BEZEL_EXPORT int64_t bezel_connect(bezel_handle target, const char* signal_sig);
BEZEL_EXPORT int bezel_disconnect(bezel_handle target, int64_t conn_id);
BEZEL_EXPORT int bezel_next_signal(int timeout_ms, bezel_signal_msg* out);
BEZEL_EXPORT int bezel_signal_emit(bezel_handle target, const char* signal_sig,
                                   int argc, bezel_variant* argv);

/* ------------------------------------------------------------------ */
/* Shutdown                                                            */
/* ------------------------------------------------------------------ */

/* Flush deferred deletions, retire signal connections, and release
 * application-level state. Idempotent. */
BEZEL_EXPORT int bezel_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif /* BEZEL_H */
