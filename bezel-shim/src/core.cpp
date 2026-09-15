// core.cpp — lifecycle, errors, handle registry, on_gui, signal queue.
//
// The GUI thread is fixed at bezel_app_new() (the thread that will call
// bezel_app_exec). Every exported function routes Qt access through
// bezel::on_gui, so Racket code may run on any thread.

#include "internal.h"

#include <QApplication>
#include <QMetaObject>
#include <QWidget>
#include <QObject>
#include <QThread>

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unordered_map>

namespace bezel {

// ---- errors ------------------------------------------------------------

static thread_local std::string t_last_error;

void clear_error() {
    t_last_error.clear();
}

bool set_error(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buf[512];
    std::vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    t_last_error = buf;
    return false;
}

// ---- application state -------------------------------------------------

namespace {
class ApplicationState {
public:
    QApplication* application = nullptr;
    QThread* gui_thread = nullptr;
    bool running = false;         // true between exec() entry and exit
    bool quit_requested = false;  // set by bezel_app_quit
    bool saw_window = false;      // a widget was shown at least once
    bool had_visible_window = false;  // a pump saw a visible top level
    int quit_code = 0;

    static ApplicationState& get() {
        static ApplicationState s;
        return s;
    }
};
}  // namespace

QApplication* app() { return ApplicationState::get().application; }

bool loop_running() { return ApplicationState::get().running; }

bool on_gui_thread() {
    ApplicationState& s = ApplicationState::get();
    if (!s.application) return true;  // pre-app calls run inline (Racket layer forbids them anyway)
    if (QThread::currentThread() == s.gui_thread) return true;
    if (!s.running) return true;  // after quit: best-effort inline, never deadlock
    return false;
}

// ---- handle registry ---------------------------------------------------

namespace {
// Handles are the raw QObject pointers. A destroyed flag is unnecessary:
// QPointer nulls itself on destruction and the destroyed() hook erases
// the entry, so a stale handle fails to resolve instead of aliasing.
class Registry {
public:
    static Registry& get() {
        static Registry r;
        return r;
    }

    void insert(QObject* obj) {
        std::lock_guard<std::mutex> lock(m_);
        map_[obj] = QPointer<QObject>(obj);
    }

    QObject* find(bezel_handle h) {
        std::lock_guard<std::mutex> lock(m_);
        auto it = map_.find(h);
        if (it == map_.end()) return nullptr;
        return it->second.data();  // nullptr when destroyed
    }

    void erase(QObject* obj) {
        std::lock_guard<std::mutex> lock(m_);
        map_.erase(obj);
    }

private:
    std::mutex m_;
    std::unordered_map<bezel_handle, QPointer<QObject>> map_;
};
}  // namespace

QObject* resolve(bezel_handle h) {
    if (!h) return nullptr;
    return Registry::get().find(h);
}

bezel_handle register_object(QObject* obj) {
    Registry::get().insert(obj);
    QObject::connect(obj, &QObject::destroyed, [](QObject* dead) {
        Registry::get().erase(dead);
    });
    return static_cast<bezel_handle>(obj);
}

char* strdup_q(const QString& s) {
    const QByteArray utf8 = s.toUtf8();
    char* out = static_cast<char*>(std::malloc(static_cast<size_t>(utf8.size()) + 1));
    if (!out) return nullptr;
    std::memcpy(out, utf8.constData(), static_cast<size_t>(utf8.size()) + 1);
    return out;
}

}  // namespace bezel

// ---- exported: library / memory / errors -------------------------------

using namespace bezel;

BEZEL_EXPORT int bezel_version(void) { return 1; }

BEZEL_EXPORT void bezel_free(void* p) { std::free(p); }

BEZEL_EXPORT const char* bezel_last_error(void) {
    return t_last_error.empty() ? nullptr : t_last_error.c_str();
}

BEZEL_EXPORT void bezel_set_last_error(const char* msg) {
    if (msg && *msg) t_last_error = msg;
    else t_last_error.clear();
}

// ---- exported: application lifecycle -----------------------------------

BEZEL_EXPORT int bezel_app_new(const char* name) {
    ApplicationState& s = ApplicationState::get();
    if (s.application) return 1;  // idempotent
    bezel::reset_signal_queue();
    s.saw_window = false;
    s.had_visible_window = false;

    static int fake_argc = 1;
    static char fake_arg0[] = "bezel";
    static char* fake_argv[] = {fake_arg0};
    s.application = new QApplication(fake_argc, fake_argv);
    s.gui_thread = QThread::currentThread();
    s.quit_requested = false;
    s.quit_code = 0;
    if (name && *name) s.application->setApplicationName(QString::fromUtf8(name));
    return 1;
}

BEZEL_EXPORT int bezel_on_gui_thread(void) {
    return bezel::on_gui_thread() ? 1 : 0;
}

namespace bezel {
void note_window_shown() {
    ApplicationState::get().saw_window = true;
}
}  // namespace bezel

BEZEL_EXPORT int bezel_app_set_quit_on_last_window_closed(int enabled) {
    return on_gui([enabled]() -> int {
        ApplicationState& s = ApplicationState::get();
        if (!s.application) {
            set_error("bezel_app_set_quit_on_last_window_closed: no application");
            return 0;
        }
        s.application->setQuitOnLastWindowClosed(enabled != 0);
        return 1;
    });
}

// 1 when the pump should stop: explicit quit, or (matching Qt's
// quitOnLastWindowClosed) the pump has already seen a visible top-level
// window in this application's lifetime and none is visible now. The
// "seen one first" arming keeps app setup and hidden-window phases from
// stopping a pump that has not actually shown anything yet.
BEZEL_EXPORT int bezel_app_quit_requested(void) {
    ApplicationState& s = ApplicationState::get();
    if (s.quit_requested) return 1;
    if (s.saw_window && s.application && s.application->quitOnLastWindowClosed()) {
        bool any_visible = false;
        const auto top_levels = QApplication::topLevelWidgets();
        for (QWidget* w : top_levels) {
            if (w && w->isVisible()) { any_visible = true; break; }
        }
        if (any_visible) {
            s.had_visible_window = true;  // arm: we have shown something
        } else if (s.had_visible_window) {
            return 1;  // shown before, nothing visible now -> stop the pump
        }
    }
    return 0;
}

BEZEL_EXPORT int bezel_app_exec(void) {
    ApplicationState& s = ApplicationState::get();
    if (!s.application) {
        set_error("bezel_app_exec: no application; call bezel_app_new first");
        return -1;
    }
    s.quit_requested = false;
    s.running = true;
    const int code = QApplication::exec();
    s.running = false;
    return code;
}

BEZEL_EXPORT int bezel_app_quit(int code) {
    return on_gui([code]() -> int {
        ApplicationState& s = ApplicationState::get();
        if (!s.application) {
            set_error("bezel_app_quit: no application");
            return 0;
        }
        s.quit_requested = true;
        s.quit_code = code;
        QApplication::exit(code);
        return 1;
    });
}

BEZEL_EXPORT int bezel_process_events(int ms) {
    return on_gui([ms]() -> int {
        ApplicationState& s = ApplicationState::get();
        if (!s.application) {
            set_error("bezel_process_events: no application");
            return 0;
        }
        // Pump-style loops keep the app alive through this function, so
        // treat the first pump as "the loop is running" for on_gui
        // marshaling (a blocking exec would set it too).
        s.running = true;
        if (ms > 0) QCoreApplication::processEvents(QEventLoop::AllEvents, ms);
        else QCoreApplication::processEvents();
        // A pump loop has no executive event loop to deliver
        // DeferredDelete (deleteLater), so do it explicitly each pump.
        QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
        return 1;
    });
}

// ---- exported: objects -------------------------------------------------

BEZEL_EXPORT bezel_handle bezel_object_new(void) {
    return on_gui([]() -> bezel_handle {
        return register_object(new QObject());
    });
}

BEZEL_EXPORT int bezel_object_delete(bezel_handle h) {
    return on_gui([h]() -> int {
        QObject* obj = resolve(h);
        if (!obj) {
            set_error("bezel_object_delete: dead or unknown handle %p", h);
            return 0;
        }
        obj->deleteLater();  // safe even while a signal involving obj is dispatching
        return 1;
    });
}

BEZEL_EXPORT int bezel_object_alive(bezel_handle h) {
    // No on_gui: QPointer is safe to read from any thread and this gets
    // called from finalizers, which may run on any Racket thread.
    return resolve(h) ? 1 : 0;
}

BEZEL_EXPORT const char* bezel_object_name(bezel_handle h) {
    return on_gui([h]() -> const char* {
        QObject* obj = resolve(h);
        if (!obj) {
            set_error("bezel_object_name: dead or unknown handle %p", h);
            return nullptr;
        }
        return strdup_q(obj->objectName());
    });
}

BEZEL_EXPORT int bezel_object_set_name(bezel_handle h, const char* name) {
    return on_gui([h, name]() -> int {
        QObject* obj = resolve(h);
        if (!obj) {
            set_error("bezel_object_set_name: dead or unknown handle %p", h);
            return 0;
        }
        obj->setObjectName(QString::fromUtf8(name ? name : ""));
        return 1;
    });
}

BEZEL_EXPORT int bezel_object_set_parent(bezel_handle h, bezel_handle parent) {
    return on_gui([h, parent]() -> int {
        QObject* obj = resolve(h);
        QObject* p = parent ? resolve(parent) : nullptr;
        if (parent && !p) {
            set_error("bezel_object_set_parent: dead or unknown parent %p", parent);
            return 0;
        }
        if (!obj) {
            set_error("bezel_object_set_parent: dead or unknown handle %p", h);
            return 0;
        }
        obj->setParent(p);  // Qt semantics: parenting transfers ownership
        return 1;
    });
}

// ---- exported: shutdown -------------------------------------------------

BEZEL_EXPORT int bezel_cleanup(void) {
    shutdown_signal_queue();
    return on_gui([]() -> int {
        ApplicationState& s = ApplicationState::get();
        if (!s.application) return 1;
        QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
        delete s.application;
        s.application = nullptr;
        s.gui_thread = nullptr;
        s.running = false;
        return 1;
    });
}
