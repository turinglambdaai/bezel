// tray.cpp — desktop integration: clipboard and the system tray.
//
// The clipboard is a QGuiApplication-level singleton, so its functions
// take no handle (they still require an application and run on_gui).
// The tray is a parentless QObject: it stays alive until explicit
// deletion or application teardown, like every other parentless Bezel
// object.

#include "internal.h"

#include <QApplication>
#include <QClipboard>
#include <QIcon>
#include <QMenu>
#include <QSystemTrayIcon>

using namespace bezel;

extern "C" {

// ---- clipboard ---------------------------------------------------------------

BEZEL_EXPORT int bezel_clipboard_set_text(const char* text) {
    return on_gui([text]() -> int {
        if (!app()) {
            set_error("bezel_clipboard_set_text: no application; call bezel_app_new first");
            return 0;
        }
        QGuiApplication::clipboard()->setText(QString::fromUtf8(text ? text : ""));
        return 1;
    });
}

BEZEL_EXPORT const char* bezel_clipboard_text(void) {
    return on_gui([]() -> const char* {
        if (!app()) {
            set_error("bezel_clipboard_text: no application; call bezel_app_new first");
            return nullptr;
        }
        return strdup_q(QGuiApplication::clipboard()->text());
    });
}

// ---- system tray ---------------------------------------------------------------

BEZEL_EXPORT bezel_handle bezel_tray_new(const char* icon_path, const char* tooltip) {
    return on_gui([icon_path, tooltip]() -> bezel_handle {
        if (!app()) {
            set_error("bezel_tray_new: no application; call bezel_app_new first");
            return nullptr;
        }
        const QString path = QString::fromUtf8(icon_path ? icon_path : "");
        QSystemTrayIcon* tray = new QSystemTrayIcon(QIcon(path));
        tray->setToolTip(QString::fromUtf8(tooltip ? tooltip : ""));
        // Not shown here: the caller decides when the icon goes live.
        return register_object(tray);
    });
}

BEZEL_EXPORT int bezel_tray_set_tooltip(bezel_handle h, const char* tooltip) {
    return on_gui([h, tooltip]() -> int {
        QSystemTrayIcon* t = resolve_as<QSystemTrayIcon>(h, "bezel_tray_set_tooltip");
        if (!t) return 0;
        t->setToolTip(QString::fromUtf8(tooltip ? tooltip : ""));
        return 1;
    });
}

BEZEL_EXPORT int bezel_tray_set_visible(bezel_handle h, int visible) {
    return on_gui([h, visible]() -> int {
        QSystemTrayIcon* t = resolve_as<QSystemTrayIcon>(h, "bezel_tray_set_visible");
        if (!t) return 0;
        t->setVisible(visible != 0);
        return 1;
    });
}

BEZEL_EXPORT int bezel_tray_show_message(bezel_handle h, const char* title, const char* text,
                                         int icon, int timeout_ms) {
    return on_gui([h, title, text, icon, timeout_ms]() -> int {
        QSystemTrayIcon* t = resolve_as<QSystemTrayIcon>(h, "bezel_tray_show_message");
        if (!t) return 0;
        QSystemTrayIcon::MessageIcon mi;
        switch (icon) {
            case 1: mi = QSystemTrayIcon::Warning; break;
            case 2: mi = QSystemTrayIcon::Critical; break;
            default: mi = QSystemTrayIcon::Information; break;
        }
        t->showMessage(QString::fromUtf8(title ? title : ""),
                       QString::fromUtf8(text ? text : ""), mi, timeout_ms);
        return 1;
    });
}

BEZEL_EXPORT int bezel_tray_set_menu(bezel_handle h, bezel_handle menu) {
    return on_gui([h, menu]() -> int {
        QSystemTrayIcon* t = resolve_as<QSystemTrayIcon>(h, "bezel_tray_set_menu");
        if (!t) return 0;
        QMenu* m = resolve_as<QMenu>(menu, "bezel_tray_set_menu");
        if (!m) return 0;
        // The tray does not take ownership; Bezel menus live until
        // application teardown, which satisfies that contract.
        t->setContextMenu(m);
        return 1;
    });
}

}  // extern "C"
