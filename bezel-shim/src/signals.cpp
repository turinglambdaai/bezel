// signals.cpp — the signal bridge.
//
// Qt signal handlers must not call Racket (Racket CS callbacks are
// atomic and the Qt loop thread is a foreign thread). So trampolines
// here are pure C++: each connection owns a SignalSink whose slot packs
// the signal's arguments into a locked queue. A Racket dispatcher
// thread drains the queue with bezel_next_signal() and runs the user's
// procedure; Qt calls made by that procedure are marshaled by the
// Racket layer back onto the GUI thread.
//
// Connection path: verify the signal exists on the target class, pick a
// sink slot matching the signal's first parameter type, then
// QObject::connect(QMetaMethod, QMetaMethod). Test hook
// bezel_signal_emit() drives the same sink/queue path deterministically.

#include "internal.h"
#include "signalsink.h"

#include <QByteArray>
#include <QMetaMethod>
#include <QMetaObject>
#include <QObject>
#include <QVector>

#include <chrono>
#include <cstring>
#include <vector>

namespace bezel {

namespace {
void clear_connections_impl();
}

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

void clear_queued_messages_locked() {
    while (!queue.empty()) {
        free_msg_strings(&queue.front());
        queue.pop_front();
    }
}

// Internal lifecycle notification: a negative connection id tells the
// Racket dispatcher to retire the handler for the corresponding positive
// id. It uses the existing queue ABI without exposing callbacks from C++.
void queue_disconnect_notice(int64_t conn_id) {
    bezel_signal_msg msg{};
    msg.conn_id = -conn_id;
    msg.argc = 0;
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        if (queue_shutdown) return;
        queue.push_back(msg);
    }
    queue_cv.notify_one();
}
}  // namespace

void queue_signal(int64_t conn_id, int argc, const bezel_variant* argv) {
    bezel_signal_msg msg{};
    msg.conn_id = conn_id;
    msg.argc = (argc > BEZEL_MAX_SIGNAL_ARGS) ? BEZEL_MAX_SIGNAL_ARGS : argc;
    for (int i = 0; i < msg.argc; ++i) msg.argv[i] = argv[i];
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        if (queue_shutdown) {
            free_msg_strings(&msg);
            return;
        }
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
    clear_queued_messages_locked();
    queue_shutdown = false;
}

void shutdown_signal_queue() {
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        queue_shutdown = true;
        clear_queued_messages_locked();
    }
    queue_cv.notify_all();

    // bezel_cleanup calls this on the GUI thread. Retire every native
    // connection before QApplication destruction so connection records
    // and sink objects never survive across app lifecycles.
    clear_connections_impl();
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

void clear_connections_impl() {
    std::vector<SignalSink*> sinks;
    {
        std::lock_guard<std::mutex> lock(conn_mutex);
        sinks.reserve(connections.size());
        for (auto& [id, rec] : connections) {
            Q_UNUSED(id);
            QObject::disconnect(rec.conn);
            if (rec.sink) sinks.push_back(rec.sink);
        }
        connections.clear();
    }
    for (SignalSink* sink : sinks) {
        if (sink) sink->deleteLater();
    }
}
}  // namespace

int64_t reserve_connection_id() {
    std::lock_guard<std::mutex> lock(conn_mutex);
    return ++next_conn_id;
}

void store_connection_with_id(int64_t conn_id, QMetaObject::Connection conn,
                              QObject* target, SignalSink* sink, const QByteArray& sig) {
    {
        std::lock_guard<std::mutex> lock(conn_mutex);
        connections[conn_id] = ConnectionRecord{std::move(conn), target, sink, sig};
    }

    // QObject automatically disconnects the signal when its sender dies,
    // but our registries also need to forget the connection. Keep this
    // pure C++ and notify Racket through the queue instead of invoking a
    // foreign callback from Qt.
    QObject::connect(target, &QObject::destroyed, sink,
                     [conn_id, sink](QObject*) {
                         {
                             std::lock_guard<std::mutex> lock(conn_mutex);
                             connections.erase(conn_id);
                         }
                         queue_disconnect_notice(conn_id);
                         sink->deleteLater();
                     },
                     Qt::DirectConnection);
}

bool drop_connection(int64_t conn_id, QObject* expected_target) {
    SignalSink* sink = nullptr;
    {
        std::lock_guard<std::mutex> lock(conn_mutex);
        auto it = connections.find(conn_id);
        if (it == connections.end()) {
            return set_error("bezel_disconnect: unknown connection id %lld",
                             static_cast<long long>(conn_id));
        }
        if (it->second.target.data() != expected_target) {
            return set_error("bezel_disconnect: connection id %lld does not belong to target %p",
                             static_cast<long long>(conn_id),
                             static_cast<void*>(expected_target));
        }
        QObject::disconnect(it->second.conn);
        sink = it->second.sink;
        connections.erase(it);
    }
    if (sink) sink->deleteLater();
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

void SignalSink::dispatchII(int a, int b) {
    bezel_variant vs[2] = {};
    vs[0].tag = BEZEL_VT_INT;
    vs[0].i = a;
    vs[1].tag = BEZEL_VT_INT;
    vs[1].i = b;
    deliver(2, vs);
}

void SignalSink::dispatchD(double a) {
    bezel_variant v{};
    v.tag = BEZEL_VT_DOUBLE;
    v.d = a;
    deliver(1, &v);
}

void SignalSink::dispatchS(const QString& a) {
    bezel_variant v{};
    v.tag = BEZEL_VT_STRING;
    v.s = strdup_q(a);  // ownership moves to the queue
    if (!v.s) return;   // OOM: do not enqueue a bogus string pointer
    deliver(1, &v);
}

void SignalSink::deliver_variants(int argc, const bezel_variant* argv) {
    if (argc <= 0) { dispatch0(); return; }
    if (argc == 1) {
        switch (argv[0].tag) {
            case BEZEL_VT_INT: dispatchI(static_cast<int>(argv[0].i)); break;
            case BEZEL_VT_BOOL: dispatchB(argv[0].i != 0); break;
            case BEZEL_VT_DOUBLE: dispatchD(argv[0].d); break;
            case BEZEL_VT_STRING: dispatchS(QString::fromUtf8(argv[0].s ? argv[0].s : "")); break;
            default: dispatch0(); break;
        }
        return;
    }
    // Multi-argument delivery (the emit test hook; multi-arg Qt signals
    // route through their typed slots instead). The queue owns string
    // buffers, so re-duplicate every string; scalars copy as-is.
    bezel_variant copy[BEZEL_MAX_SIGNAL_ARGS] = {};
    const int n = (argc > BEZEL_MAX_SIGNAL_ARGS) ? BEZEL_MAX_SIGNAL_ARGS : argc;
    for (int i = 0; i < n; ++i) {
        copy[i] = argv[i];
        if (copy[i].tag == BEZEL_VT_STRING) {
            copy[i].s = strdup_q(QString::fromUtf8(copy[i].s ? copy[i].s : ""));
        }
    }
    queue_signal(id_, n, copy);
}

namespace {
// Pick the sink slot matching the signal's first parameter type.
QByteArray slot_for_signal(const QMetaMethod& sig) {
    if (sig.parameterCount() == 0) return "dispatch0()";
    const QByteArray t0 = sig.parameterMetaType(0).name();
    if (sig.parameterCount() >= 2 && t0 == "int"
        && sig.parameterMetaType(1).name() == "int") {
        return "dispatchII(int,int)";
    }
    if (t0 == "bool") return "dispatchB(bool)";
    if (t0 == "int") return "dispatchI(int)";
    if (t0 == "double" || t0 == "qreal") return "dispatchD(double)";
    if (t0 == "QString") return "dispatchS(QString)";
    return "dispatch0()";  // parameter types not converted yet: deliver argless
}
}  // namespace

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
    SignalSink* sink = new SignalSink(id, qApp);  // lives until disconnect/target death/app teardown
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
        const QByteArray norm = normalized_signature(signal_sig);
        if (norm.isEmpty()) {
            set_error("bezel_connect: signal signature must not be empty");
            return 0;
        }
        return sink_connect(obj, norm);
    });
}

BEZEL_EXPORT int bezel_disconnect(bezel_handle target, int64_t conn_id) {
    return on_gui([target, conn_id]() -> int {
        QObject* obj = resolve(target);
        if (!obj) {
            set_error("bezel_disconnect: dead or unknown handle %p", target);
            return 0;
        }
        return drop_connection(conn_id, obj) ? 1 : 0;
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
// (and CI on headless machines) can drive the same queue/dispatcher path
// without a human.
int emit_to_sinks(QObject* obj, const char* signal_sig, int argc, const bezel_variant* argv) {
    const QByteArray norm = normalized_signature(signal_sig);
    if (norm.isEmpty()) {
        set_error("bezel_signal_emit: signal signature must not be empty");
        return -1;
    }
    const QMetaObject* mo = obj->metaObject();
    if (mo->indexOfSignal(norm.constData()) < 0) {
        set_error("bezel_signal_emit: %s has no signal %s", mo->className(), norm.constData());
        return -1;
    }

    std::lock_guard<std::mutex> lock(conn_mutex);
    int delivered = 0;
    for (auto& [id, rec] : connections) {
        Q_UNUSED(id);
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
        if (argc < 0 || argc > BEZEL_MAX_SIGNAL_ARGS) {
            set_error("bezel_signal_emit: argc %d is outside 0..%d", argc, BEZEL_MAX_SIGNAL_ARGS);
            return 0;
        }
        if (argc > 0 && !argv) {
            set_error("bezel_signal_emit: argv is null for argc %d", argc);
            return 0;
        }
        return emit_to_sinks(obj, signal_sig, argc, argv) >= 0 ? 1 : 0;
    });
}
