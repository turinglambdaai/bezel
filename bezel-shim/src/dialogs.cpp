// dialogs.cpp — native file dialogs.
//
// These follow the same contract as the msg-* modal dialogs in
// layouts.cpp: they run Qt's nested modal event loop on the calling
// thread, so the Racket side must call them from a signal handler or
// the main thread (never from deep inside another modal operation).
// Cancellation is reported as the empty string, not as an error.

#include "internal.h"

#include <QFileDialog>

using namespace bezel;

namespace {

// Resolve the optional parent once for both dialog flavors.
QWidget* dialog_parent(bezel_handle parent, const char* what) {
    return parent ? resolve_as<QWidget>(parent, what) : nullptr;
}

const char* file_dialog(bezel_handle parent, const char* what, const char* caption,
                        const char* dir, const char* filter, bool save) {
    return on_gui([parent, what, caption, dir, filter, save]() -> const char* {
        QWidget* p = dialog_parent(parent, what);
        if (parent && !p) return nullptr;
        const QString selected = save
            ? QFileDialog::getSaveFileName(p,
                                           QString::fromUtf8(caption ? caption : ""),
                                           QString::fromUtf8(dir ? dir : ""),
                                           QString::fromUtf8(filter ? filter : ""))
            : QFileDialog::getOpenFileName(p,
                                           QString::fromUtf8(caption ? caption : ""),
                                           QString::fromUtf8(dir ? dir : ""),
                                           QString::fromUtf8(filter ? filter : ""));
        return strdup_q(selected);  // empty string == user cancelled
    });
}

}  // namespace

extern "C" {

BEZEL_EXPORT const char* bezel_get_open_file_name(bezel_handle parent, const char* caption,
                                                  const char* dir, const char* filter) {
    return file_dialog(parent, "bezel_get_open_file_name", caption, dir, filter, false);
}

BEZEL_EXPORT const char* bezel_get_save_file_name(bezel_handle parent, const char* caption,
                                                  const char* dir, const char* filter) {
    return file_dialog(parent, "bezel_get_save_file_name", caption, dir, filter, true);
}

}  // extern "C"
