// layouts.cpp — layouts, menus, and standard dialogs.

#include "internal.h"

#include <QBoxLayout>
#include <QFormLayout>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QLayout>
#include <QMainWindow>
#include <QMenuBar>
#include <QMessageBox>
#include <QVBoxLayout>
#include <QWidget>

namespace {

using namespace bezel;

QLayout* resolve_layout(bezel_handle h, const char* what) {
    return resolve_as<QLayout>(h, what);
}

}  // namespace

using namespace bezel;

// ---- layouts -------------------------------------------------------------

BEZEL_EXPORT bezel_handle bezel_vbox_new(void) {
    return on_gui([]() -> bezel_handle { return register_object(new QVBoxLayout()); });
}

BEZEL_EXPORT bezel_handle bezel_hbox_new(void) {
    return on_gui([]() -> bezel_handle { return register_object(new QHBoxLayout()); });
}

BEZEL_EXPORT bezel_handle bezel_grid_new(void) {
    return on_gui([]() -> bezel_handle { return register_object(new QGridLayout()); });
}

BEZEL_EXPORT bezel_handle bezel_form_new(void) {
    return on_gui([]() -> bezel_handle { return register_object(new QFormLayout()); });
}

BEZEL_EXPORT int bezel_widget_set_layout(bezel_handle w, bezel_handle layout) {
    return on_gui([w, layout]() -> int {
        QWidget* widget = resolve_as<QWidget>(w, "bezel_widget_set_layout");
        if (!widget) return 0;
        QLayout* lay = resolve_layout(layout, "bezel_widget_set_layout");
        if (!lay) return 0;
        widget->setLayout(lay);  // Qt reparents the layout onto the widget
        return 1;
    });
}

BEZEL_EXPORT int bezel_window_central_layout(bezel_handle window, bezel_handle layout) {
    return on_gui([window, layout]() -> int {
        QMainWindow* win = resolve_as<QMainWindow>(window, "bezel_window_central_layout");
        if (!win) return 0;
        QLayout* lay = resolve_layout(layout, "bezel_window_central_layout");
        if (!lay) return 0;
        auto* central = new QWidget(win);
        central->setLayout(lay);  // the layout (and its children) reparent here
        win->setCentralWidget(central);
        return 1;
    });
}

BEZEL_EXPORT int bezel_layout_add_widget(bezel_handle layout, bezel_handle w, int stretch) {
    return on_gui([layout, w, stretch]() -> int {
        QLayout* lay = resolve_layout(layout, "bezel_layout_add_widget");
        if (!lay) return 0;
        QWidget* widget = resolve_as<QWidget>(w, "bezel_layout_add_widget");
        if (!widget) return 0;
        // Stretch is a QBoxLayout feature; other layouts take the widget
        // without it.
        if (auto* box = qobject_cast<QBoxLayout*>(lay)) {
            box->addWidget(widget, stretch);
        } else {
            lay->addWidget(widget);
        }
        return 1;
    });
}

BEZEL_EXPORT int bezel_layout_add_layout(bezel_handle parent, bezel_handle child, int stretch) {
    return on_gui([parent, child, stretch]() -> int {
        QBoxLayout* p = resolve_as<QBoxLayout>(parent, "bezel_layout_add_layout");
        if (!p) return 0;
        QLayout* c = resolve_layout(child, "bezel_layout_add_layout");
        if (!c) return 0;
        p->addLayout(c, stretch);
        return 1;
    });
}

BEZEL_EXPORT int bezel_layout_add_stretch(bezel_handle layout, int stretch) {
    return on_gui([layout, stretch]() -> int {
        QBoxLayout* box = resolve_as<QBoxLayout>(layout, "bezel_layout_add_stretch");
        if (!box) return 0;
        box->addStretch(stretch);
        return 1;
    });
}

BEZEL_EXPORT int bezel_layout_set_spacing(bezel_handle layout, int spacing) {
    return on_gui([layout, spacing]() -> int {
        QLayout* lay = resolve_layout(layout, "bezel_layout_set_spacing");
        if (!lay) return 0;
        lay->setSpacing(spacing);
        return 1;
    });
}

BEZEL_EXPORT int bezel_layout_set_margins(bezel_handle layout, int l, int t, int r, int b) {
    return on_gui([layout, l, t, r, b]() -> int {
        QLayout* lay = resolve_layout(layout, "bezel_layout_set_margins");
        if (!lay) return 0;
        lay->setContentsMargins(l, t, r, b);
        return 1;
    });
}

BEZEL_EXPORT int bezel_grid_add(bezel_handle layout, bezel_handle w,
                                int row, int col, int row_span, int col_span) {
    return on_gui([layout, w, row, col, row_span, col_span]() -> int {
        QGridLayout* grid = resolve_as<QGridLayout>(layout, "bezel_grid_add");
        if (!grid) return 0;
        QWidget* widget = resolve_as<QWidget>(w, "bezel_grid_add");
        if (!widget) return 0;
        grid->addWidget(widget, row, col, row_span, col_span);
        return 1;
    });
}

BEZEL_EXPORT int bezel_form_add_row(bezel_handle layout, const char* label, bezel_handle w) {
    return on_gui([layout, label, w]() -> int {
        QFormLayout* form = resolve_as<QFormLayout>(layout, "bezel_form_add_row");
        if (!form) return 0;
        QWidget* widget = resolve_as<QWidget>(w, "bezel_form_add_row");
        if (!widget) return 0;
        form->addRow(QString::fromUtf8(label ? label : ""), widget);
        return 1;
    });
}

// ---- menus -----------------------------------------------------------------

BEZEL_EXPORT bezel_handle bezel_menubar(bezel_handle window) {
    return on_gui([window]() -> bezel_handle {
        QMainWindow* win = resolve_as<QMainWindow>(window, "bezel_menubar");
        if (!win) return nullptr;
        return register_object(win->menuBar());
    });
}

BEZEL_EXPORT bezel_handle bezel_menu_add(bezel_handle parent, const char* title) {
    return on_gui([parent, title]() -> bezel_handle {
        const QString t = QString::fromUtf8(title ? title : "");
        if (auto* bar = resolve_as<QMenuBar>(parent, "bezel_menu_add")) {
            return register_object(bar->addMenu(t));
        }
        if (auto* menu = resolve_as<QMenu>(parent, "bezel_menu_add")) {
            return register_object(menu->addMenu(t));
        }
        return nullptr;
    });
}

BEZEL_EXPORT bezel_handle bezel_menu_action(bezel_handle menu, const char* text) {
    return on_gui([menu, text]() -> bezel_handle {
        QMenu* m = resolve_as<QMenu>(menu, "bezel_menu_action");
        if (!m) return nullptr;
        return register_object(m->addAction(QString::fromUtf8(text ? text : "")));
    });
}

BEZEL_EXPORT bezel_handle bezel_menu_separator(bezel_handle menu) {
    return on_gui([menu]() -> bezel_handle {
        QMenu* m = resolve_as<QMenu>(menu, "bezel_menu_separator");
        if (!m) return nullptr;
        m->addSeparator();
        return nullptr;  // separators have no useful handle
    });
}

// ---- dialogs -----------------------------------------------------------------

namespace {
// QMessageBox::StandardButton values are bit flags; map the two useful
// answers to 1/0 so Racket gets a stable contract.
int standardize(QMessageBox::StandardButton b) {
    switch (b) {
        case QMessageBox::Ok:
        case QMessageBox::Yes:
            return 1;
        case QMessageBox::No:
        case QMessageBox::Cancel:
            return 0;
        default:
            return -1;
    }
}
}  // namespace

BEZEL_EXPORT int bezel_msg_information(bezel_handle parent, const char* title, const char* text) {
    return on_gui([parent, title, text]() -> int {
        QWidget* p = parent ? resolve_as<QWidget>(parent, "bezel_msg_information") : nullptr;
        if (parent && !p) return -1;
        return standardize(QMessageBox::information(
            p, QString::fromUtf8(title ? title : ""), QString::fromUtf8(text ? text : "")));
    });
}

BEZEL_EXPORT int bezel_msg_warning(bezel_handle parent, const char* title, const char* text) {
    return on_gui([parent, title, text]() -> int {
        QWidget* p = parent ? resolve_as<QWidget>(parent, "bezel_msg_warning") : nullptr;
        if (parent && !p) return -1;
        return standardize(QMessageBox::warning(
            p, QString::fromUtf8(title ? title : ""), QString::fromUtf8(text ? text : "")));
    });
}

BEZEL_EXPORT int bezel_msg_question(bezel_handle parent, const char* title, const char* text) {
    return on_gui([parent, title, text]() -> int {
        QWidget* p = parent ? resolve_as<QWidget>(parent, "bezel_msg_question") : nullptr;
        if (parent && !p) return -1;
        return standardize(QMessageBox::question(
            p, QString::fromUtf8(title ? title : ""), QString::fromUtf8(text ? text : "")));
    });
}
