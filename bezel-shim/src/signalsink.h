// signalsink.h — per-connection receiver object for the signal bridge.
//
// Qt 6 offers no "connect string-based signal to functor" overload, so
// Bezel connects QMetaMethod-to-QMetaMethod: each connection gets a
// SignalSink whose typed slots deliver the signal's first argument into
// the queue. One slot per convertible parameter type; signals with
// parameters Bezel cannot convert yet fall back to dispatch0() (Qt
// string/QMetaMethod connections drop extra parameters). The id is
// captured per sink, sinks are parented to qApp and live until quit.

#pragma once

#include <bezel/bezel.h>

#include <QObject>
#include <QString>

namespace bezel {

class SignalSink : public QObject {
    Q_OBJECT
public:
    explicit SignalSink(int64_t id, QObject* parent = nullptr);

public slots:
    void dispatch0();
    void dispatchB(bool a);
    void dispatchI(int a);
    void dispatchS(const QString& a);

public:
    // Test-hook path: deliver pre-converted variants directly.
    void deliver_variants(int argc, const bezel_variant* argv);

private:
    void deliver(int argc, const bezel_variant* argv);

    int64_t id_;
};

// Connect `target`'s signal to a fresh sink; returns the connection id
// (0 on failure). `norm_sig` is the normalized signature without the
// Qt '2' prefix, e.g. "clicked()".
int64_t sink_connect(QObject* target, const QByteArray& norm_sig);

}  // namespace bezel
