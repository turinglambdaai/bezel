// signals.cpp — the signal bridge.
//
// Qt signal handlers must not call Racket (Racket CS callbacks are
// atomic and the Qt loop thread is a foreign thread). So trampolines
// here are pure C++: each connection owns a SignalSink whose slot packs
// the signal's arguments into a locked queue. A Racket dispatcher
// thread drains the queue with bezel_next_signal() and runs the user's
// procedure; any Qt call that procedure makes is marshaled back onto
// the GUI thread by on_gui (see internal.h).
//
// Connection path: verify the signal exists on the target class, pick a
// sink slot matching the signal's first parameter type, then
// QObject::connect(QMetaMethod, QMetaMethod). Test hook
// bezel_signal_emit() emits through QMetaMethod::invoke so CI exercises
// the exact production path.

#include "internal.h"
#include "signalsink.h"

#include <QByteArray>
#include <QMetaMethod>
#include <QMetaObject>
#include <QObject>
#include <QVector>

#include <chrono>
#include <cstring>

namespace bezel {

// ---- signal delivery queue --------------------------------------------------

namespace {
std::mutex queue_mutex;
std::condition_variable queue_cv;
std::deque<bezel_signal_msg> queue;
bool queue_shutdown = false;

void free_msg_strings(bezel_signal_msg* msg) {
    for (int i = 0; i < msg->argc; ++i) {
        if (msg->argv[i].tag == BEZEL_VT_STRING) {
            std::free(const_cast<char*>(msg->argv[i].s));
            msg->argv[i].s = nullptr;
        }
    }
}
}  // namespace

void queue_signal(int64_t conn_id, int argc, const bezel_variant* argv) {
    bezel_signal_msg msg{};
    msg.conn_id = conn_id;
    msg.argc = (argc > BEZEL_MAX_SIGNAL_ARGS) ? BEZEL_MAX_SIGNAL_ARGS : argc;
    for (int i = 0; i < msg.argc; ++i) msg.argv[i] = argv[i];
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        queue.push_back(msg);
    }
    queue_cv.notify_one();
}

int wait_signal(int timeout_ms, bezel_signal_msg* out) {
    std::unique_lock<std::mutex> lock(queue_mutex);
    for (;;) {
        if (!queue.empty()) {
            *out = queue.front();
            queue.pop_front();
            return 1;
        }
        if (queue_shutdown) return -1;
        // timeout_ms <= 0: non-blocking poll (the Racket dispatcher uses
        // this — a blocking foreign wait would pin its OS thread).
        if (timeout_ms <= 0) return 0;
        if (queue_cv.wait_for(lock, std::chrono::milliseconds(timeout_ms)) ==
            std::cv_status::timeout) {
            return 0;
        }
        // Notified: loop to re-check the queue and shutdown flag.
    }
}

void reset_signal_queue() {
    std::lock_guard<std::mutex> lock(queue_mutex);
    queue_shutdown = false;
}

void shutdown_signal_queue() {
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        queue_shutdown = true;
        while (!queue.empty()) {
            free_msg_strings(&queue.front());
            queue.pop_front();
        }
    }
    queue_cv.notify_all();
}

// ---- connection registry -----------------------------------------------------

namespace {
struct ConnectionRecord {
    QMetaObject::Connection conn;
    QPointer<QObject> target;
    SignalSink* sink = nullptr;
    QByteArray sig;  // normalized signature
};
int64_t next_conn_id = 0;  // guarded by conn_mutex
std::mutex conn_mutex;
std::unordered_map<int64_t, ConnectionRecord> connections;
}  // namespace

int64_t reserve_connection_id() {
    std::lock_guard<std::mutex> lock(conn_mutex);
    return ++next_conn_id;
}

void store_connection_with_id(int64_t conn_id, QMetaObject::Connection conn,
                              QObject* target, SignalSink* sink, const QByteArray& sig) {
    std::lock_guard<std::mutex> lock(conn_mutex);
    connections[conn_id] = ConnectionRecord{std::move(conn), target, sink, sig};
}

bool drop_connection(int64_t conn_id) {
    std::lock_guard<std::mutex> lock(conn_mutex);
    auto it = connections.find(conn_id);
    if (it == connections.end()) return false;
    QObject::disconnect(it->second.conn);
    connections.erase(it);
    return true;
}

// ---- SignalSink ---------------------------------------------------------------

SignalSink::SignalSink(int64_t id, QObject* parent) : QObject(parent), id_(id) {}

void SignalSink::deliver(int argc, const bezel_variant* argv) {
    queue_signal(id_, argc, argv);
}

void SignalSink::dispatch0() { deliver(0, nullptr); }

void SignalSink::dispatchB(bool a) {
    bezel_variant v{};
    v.tag = BEZEL_VT_BOOL;
    v.i = a ? 1 : 0;
    deliver(1, &v);
}

void SignalSink::dispatchI(int a) {
    bezel_variant v{};
    v.tag = BEZEL_VT_INT;
    v.i = a;
    deliver(1, &v);
}

void SignalSink::dispatchS(const QString& a) {
    bezel_variant v{};
    v.tag = BEZEL_VT_STRING;
    v.s = strdup_q(a);  // ownership moves to the queue
    deliver(1, &v);
}

void SignalSink::deliver_variants(int argc, const bezel_variant* argv) {
    if (argc <= 0) { dispatch0(); return; }
    switch (argv[0].tag) {
        case BEZEL_VT_INT: dispatchI(static_cast<int>(argv[0].i)); break;
        case BEZEL_VT_BOOL: dispatchB(argv[0].i != 0); break;
        case BEZEL_VT_DOUBLE: dispatchS(QString::number(argv[0].d)); break;
        case BEZEL_VT_STRING: dispatchS(QString::fromUtf8(argv[0].s ? argv[0].s : "")); break;
        default: dispatch0(); break;
    }
}

QByteArray slot_for_signal(const QMetaMethod& sig) {
    if (sig.parameterCount() == 0) return "dispatch0()";
    const QByteArray t = sig.parameterMetaType(0).name();
    if (t == "bool") return "dispatchB(bool)";
    if (t == "int" || t == "uint" || t == "long" || t == "qint32") return "dispatchI(int)";
    if (t == "QString") return "dispatchS(QString)";
    return "dispatch0()";  // parameter types not converted yet: deliver argless
}

// forward decl from internal.h usage below
int64_t sink_connect(QObject* target, const QByteArray& norm_sig) {
    const QMetaObject* mo = target->metaObject();
    const int sidx = mo->indexOfSignal(norm_sig.constData());
    if (sidx < 0) {
        set_error("bezel_connect: %s has no signal %s", mo->className(), norm_sig.constData());
        return 0;
    }
    const QMetaMethod sig = mo->method(sidx);

    if (!app()) {
        set_error("bezel_connect: no application; call bezel_app_new first");
        return 0;
    }
    const int64_t id = reserve_connection_id();
    SignalSink* sink = new SignalSink(id, qApp);  // lives until the app dies
    const QMetaObject* smo = sink->metaObject();
    const QByteArray slot_sig = slot_for_signal(sig);
    const int ridx = smo->indexOfSlot(slot_sig.constData());
    if (ridx < 0) {
        set_error("bezel_connect: internal: missing sink slot %s", slot_sig.constData());
        delete sink;
        return 0;
    }
    const QMetaObject::Connection conn =
        QObject::connect(target, sig, sink, smo->method(ridx), Qt::DirectConnection);
    if (!conn) {
        set_error("bezel_connect: failed to connect %s", norm_sig.constData());
        delete sink;
        return 0;
    }
    store_connection_with_id(id, conn, target, sink, norm_sig);
    return id;
}

}  // namespace bezel

// ---- exported ------------------------------------------------------------

using namespace bezel;

namespace {
QByteArray normalized_signature(const char* signal_sig) {
    QByteArray s(signal_sig ? signal_sig : "");
    if (!s.isEmpty() && (s.at(0) == '1' || s.at(0) == '2')) s.remove(0, 1);
    return QMetaObject::normalizedSignature(s.constData());
}
}  // namespace

BEZEL_EXPORT int64_t bezel_connect(bezel_handle target, const char* signal_sig) {
    return on_gui([target, signal_sig]() -> int64_t {
        QObject* obj = resolve(target);
        if (!obj) {
            set_error("bezel_connect: dead or unknown handle %p", target);
            return 0;
        }
        return sink_connect(obj, normalized_signature(signal_sig));
    });
}

BEZEL_EXPORT int bezel_disconnect(bezel_handle target, int64_t conn_id) {
    return on_gui([target, conn_id]() -> int {
        QObject* obj = resolve(target);
        if (!obj) {
            set_error("bezel_disconnect: dead or unknown handle %p", target);
            return 0;
        }
        return drop_connection(conn_id) ? 1 : 0;
    });
}

BEZEL_EXPORT int bezel_next_signal(int timeout_ms, bezel_signal_msg* out) {
    if (!out) return 0;
    return wait_signal(timeout_ms, out);
}

// ---- test hook: emit a signal ----------------------------------------------

namespace {

// Deliver argv straight to the sinks of every live connection on
// `target` for `signal_sig`. Real user interaction activates signals
// through Qt's own machinery; this deterministic path exists so tests
// (and CI on headless machines) can drive the exact same bridge —
// queue, dispatcher thread, handler — without a human.
int emit_to_sinks(QObject* obj, const char* signal_sig, int argc, const bezel_variant* argv) {
    QByteArray norm(signal_sig ? signal_sig : "");
    if (!norm.isEmpty() && (norm.at(0) == '1' || norm.at(0) == '2')) norm.remove(0, 1);
    norm = QMetaObject::normalizedSignature(norm.constData());

    std::lock_guard<std::mutex> lock(conn_mutex);
    int delivered = 0;
    for (auto& [id, rec] : connections) {
        if (rec.sink && rec.target == obj && rec.sig == norm) {
            rec.sink->deliver_variants(argc, argv);
            ++delivered;
        }
    }
    return delivered;
}

}  // namespace

BEZEL_EXPORT int bezel_signal_emit(bezel_handle target, const char* signal_sig,
                                   int argc, bezel_variant* argv) {
    return on_gui([target, signal_sig, argc, argv]() -> int {
        QObject* obj = resolve(target);
        if (!obj) {
            set_error("bezel_signal_emit: dead or unknown handle %p", target);
            return 0;
        }
        return emit_to_sinks(obj, signal_sig, argc, argv) >= 0 ? 1 : 0;
    });
}
